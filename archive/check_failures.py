#!/usr/bin/env python3
"""Interactive classifier for non-zero-exit test runs.

Scans a project's output folder for `*.exit_code` sidecars with a value > 0,
locates the matching run log, extracts failure keywords inside the suite span,
and lets you label each failure (one classification per failure occurrence).

Definition of labels (per study):
  acceptable               -> a genuine test failure devs of that era would also have seen
  problematic              -> an ENVIRONMENT issue in our pipeline that caused the failure
  unclear                  -> ambiguous / could not decide (a starting state, must be resolved)
  false_positive           -> not a real failure (e.g. jest console-output capture)
  reevaluated_acceptable   -> was unclear/problematic, assessed as a genuine dev-facing failure

Keyboard shortcuts (interactive / review mode):
  ArrowUp    -> acceptable
  ArrowDown  -> problematic
  Space      -> unclear
  ArrowRight -> false_positive
  e          -> reevaluated_acceptable
  ArrowLeft  -> undo (re-classify the previous failure)
  s          -> skip (do not label, advance)
  .          -> create auto_classify rule from this failure
  r          -> reload rules from disk and re-check the current item
  q          -> quit (save and exit)

Labels are stored in projects/<project>/failure_labels_project.csv.

Config (projects/<project>/failure_patterns.json):
  general.patterns / general.exclude   what counts as a failure line
  min_gap                              proximity window (lines); same as --min-gap.
                                       CLI --min-gap overrides it. Default 5.
  auto_classify                        rules mapping an error body to a label

Modes:
  (default)           label unlabeled failures interactively
  --verify            drop labels whose failure no longer occurs, then label as usual
  --dry-run           preview failures, do not prompt / store
  --report-env        list failures whose lines match environment signals + current label
  --review <label>    re-display existing labels of <label> and let you change them
"""

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import termios
import tty
import uuid
from datetime import datetime, timezone

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))

# Failure detection is driven entirely by per-project JSON config
# (projects/<project>/failure_patterns.json). There are NO hardcoded patterns:
# every project must ship its own self-contained config so the rules are
# glanceable in one place. See failure_patterns.example.json for the schema.
EXAMPLE_CONFIG = os.path.join(REPO_ROOT, "failure_patterns.example.json")

# Cache of resolved (patterns, excludes) lives per-call in iter_failures
# (keyed by suite_stem), so resolve_patterns stays a pure function.


def load_pattern_config(project):
    """Load and return the project's failure-pattern config dict.

    Exits with a helpful message if the project has no config, since there
    is no fallback: the user must create one first.
    """
    path = os.path.join(REPO_ROOT, "projects", project, "failure_patterns.json")
    if not os.path.isfile(path):
        sys.exit(
            f"[error] no failure_patterns.json for project {project!r}\n"
            f"        create one first: copy {os.path.basename(EXAMPLE_CONFIG)} "
            f"to projects/{project}/failure_patterns.json and tune it."
        )
    with open(path) as f:
        return json.load(f)


def _compile(patterns):
    return [re.compile(p) for p in patterns]


def gen_rule_id():
    """Stable-ish unique id for an auto_classify rule (12 hex chars)."""
    return uuid.uuid4().hex[:12]


def resolve_patterns(cfg, suite=None):
    """Return (compiled_patterns, compiled_excludes) for a suite.

    `general` is the base. An optional `suites[<suite>]` block adjusts it
    additively via remove_patterns / add_patterns / remove_exclude / add_exclude.
    """
    general = cfg.get("general", {})
    patterns = list(general.get("patterns", []))
    excludes = list(general.get("exclude", []))
    if suite is not None:
        ov = cfg.get("suites", {}).get(suite, {})
        for p in ov.get("remove_patterns", []):
            if p in patterns:
                patterns.remove(p)
        patterns += ov.get("add_patterns", [])
        for p in ov.get("remove_exclude", []):
            if p in excludes:
                excludes.remove(p)
        excludes += ov.get("add_exclude", [])
    return _compile(patterns), _compile(excludes)


# --- Auto-classify rules ---------------------------------------------------
# A rule captures the normalized error *body* (the lines below a failure's
# trigger line) and maps it to a label. Once created (via the `*` key during
# labeling, or hand-written in the config), every failure whose body matches
# is labeled automatically.

def item_body(it, n=5):
    """The `n` normalized lines used as an auto-classify signature.

    `n == 0` captures only the matched (trigger) line itself.
    `n > 0` captures the `n` lines immediately BELOW the trigger line
    (the trigger line is excluded).
    """
    lines = it["lines"]
    start = it["line"] - 1      # convert 1-indexed line to 0-indexed
    if n == 0:
        body = lines[start: start + 1]   # matched line only
    else:
        body = lines[start + 1: start + 1 + n]
    return "\n".join(normalize_line(l) for l in body)


def match_auto_rule(it, rules, default_region=12):
    """Return (label, rule_id) of the first rule whose `match` (a regex string)
    searches within the normalized lines below the trigger. Each rule carries its
    own body line-count (`lines`), so we scan far enough to contain it. Returns
    None when no rule matches."""
    lines = it["lines"]
    start = it["line"] - 1
    for stored, label, _note, n, rid in rules:
        if not stored:
            continue
        region = max(default_region, (n or 5) + 4)
        region_text = "\n".join(normalize_line(l) for l in lines[start: start + region])
        try:
            if re.compile(stored).search(region_text):
                return label, rid
        except re.error:
            continue
    return None


def load_auto_rules(project):
    """Return list of (match, label, note, lines, rule_id) from the project config.

    `match` is always a regex string; every rule has an `id`."""
    cfg = load_pattern_config(project)
    out = []
    for r in cfg.get("auto_classify", []):
        m = r.get("match")
        label = r.get("label")
        if m and label in ALL_LABELS:
            out.append((m, label, r.get("note", ""), int(r.get("lines", 5)),
                        r.get("id", "")))
    return out


def add_auto_rule(project, body, label, note="", lines=5):
    """Append an auto_classify rule to the project's failure_patterns.json.

    `body` is literal log text; it is escaped so it is stored as a regex string.
    Returns the generated rule id."""
    path = os.path.join(REPO_ROOT, "projects", project, "failure_patterns.json")
    with open(path) as f:
        cfg = json.load(f)
    cfg.setdefault("auto_classify", [])
    rid = gen_rule_id()
    cfg["auto_classify"].append({"match": re.escape(body), "label": label,
                                 "note": note, "lines": lines, "id": rid})
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    return rid


# Environment signals: failures our pipeline (not the devs) typically causes.
ENV_PATTERNS = [
    re.compile(r"Cannot find module", re.I),
    re.compile(r"Cannot use import statement outside a module", re.I),
    re.compile(r"Test suite failed to run", re.I),
    re.compile(r"SyntaxError", re.I),
    re.compile(r"EADDRINUSE"),
    re.compile(r"gyp ERR"),
    re.compile(r"Killed|out of memory|\bOOM\b"),
    re.compile(r"webpack.*(?:Module build failed|Loader|Error)", re.I),
    re.compile(r"timed out|ETIMEDOUT|ECONNREFUSED|ENOTFOUND|EAI_AGAIN", re.I),
    re.compile(r"node-sass|node-gyp|Missing binding"),
]

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
SUITE_START_RE = re.compile(r"\[SUITE_START\]\s*(\S+)")
SUITE_END_RE = re.compile(r"\[SUITE_END\]\s*(\S+)")

LABELS = {
    "UP": "acceptable",
    "DOWN": "problematic",
    " ": "unclear",
    "RIGHT": "false_positive",
    "e": "reevaluated_acceptable",
}
ALL_LABELS = ["acceptable", "problematic", "unclear", "false_positive",
              "reevaluated_acceptable"]


def clean(line):
    # Fast path: ANSI escapes all start with ESC, so skip the regex for the vast
    # majority of lines (identical result, much cheaper on multi-MB logs).
    if "\x1b" in line:
        line = ANSI_RE.sub("", line)
    return line.rstrip()


def env_signals(text_lines):
    """Return list of matched environment-signal snippets in the given lines."""
    hits = []
    for pat in ENV_PATTERNS:
        for ln in text_lines:
            m = pat.search(ln)
            if m:
                hits.append(m.group(0))
                break
    return hits


# Tokens stripped when normalizing a line for fingerprinting.
TIMING_RE = re.compile(r"\(\d+(?:\.\d+)?\s*(?:s|ms)\)")
# vitest >=2.x appends a bare duration to the live failing-test line, e.g.
# "× suite > test 8305ms". Stripped so the identity is stable across runs.
VITEST_TRAIL_TIME_RE = re.compile(r"\s+\d+(?:\.\d+)?\s*(?:ms|s)\s*$")
REPO_PREFIX_RE = re.compile(r"/coverage_reloaded/repo/?")


# Turbo's per-task log prefix, e.g. "n8n-editor-ui:test: " or "n8n-core:test:unit: ".
# Only stripped when a project opts in via failure_patterns.json ->
# fingerprint.strip_package_prefix (or the --fingerprint pkg-prefix override).
_TURBO_PREFIX_RE = re.compile(r"^[A-Za-z0-9_@./-]+:test(?::[A-Za-z0-9_@./-]+)*:\s*")


def resolve_fingerprint(cfg, mode=None):
    """Return the compiled package-prefix regex to strip, or None.

    Precedence: explicit CLI ``mode`` ('default' -> None, 'pkg-prefix' -> turbo
    regex), else the project config's ``fingerprint.strip_package_prefix`` which
    may be a bool (True = built-in turbo regex) or an explicit regex string.
    Absent / False -> None, i.e. the historical, project-independent behavior.
    """
    if mode == "default":
        return None
    if mode == "pkg-prefix":
        return _TURBO_PREFIX_RE
    spec = ((cfg or {}).get("fingerprint") or {}).get("strip_package_prefix", False)
    if spec is True:
        return _TURBO_PREFIX_RE
    if isinstance(spec, str) and spec:
        return re.compile(spec)
    return None


def normalize_line(line, prefix_re=None):
    """Normalize a log line so identical failures print differently across a run match.

    ``prefix_re`` (optional) removes a leading runner/tool prefix (e.g. turbo's
    ``pkg:task:``) before the failure identity is extracted; it is only supplied
    when the project opts in.
    """
    s = ANSI_RE.sub("", line)
    s = s.strip()
    if prefix_re is not None:
        s = prefix_re.sub("", s, count=1)
    s = TIMING_RE.sub("", s)
    s = REPO_PREFIX_RE.sub("", s)
    if s.startswith("src/"):
        s = s[4:]
    return s


def fingerprint(fail_line, lines, window=5, prefix_re=None):
    """Stable per-failure identity (sha1) used to dedupe jest's re-prints.

    Rather than hashing a raw block (which differs between jest's mid-run print and
    its end-of-log 'Summary of all failing tests' re-print), extract the failing
    test/file identity from a scan window around the line. This also collapses the
    `FAIL <file>` / `✕ <test>` / `● <suite> › <test>` representations of one failure
    into a single unit.

    vitest's live failing-test line is also recognised:
      `❯ <file> > <suite> > <test>`  (vitest <=1.x)  -> same identity as `FAIL <file> > ...`
      `× <suite> > <test> [<duration>]` (vitest >=2.x) -> duration stripped
    and is anchored on the trigger line only, because adjacent failures are only
    3-4 lines apart and a wider scan would pick up the previous test's line.

    ``prefix_re`` (optional) is passed to normalize_line so prefixed logs (e.g.
    turbo's ``pkg:task:``) reach the ``startswith("FAIL")`` branch.
    """
    lo = max(0, fail_line - 1 - 4)
    hi = fail_line - 1 + window + 4
    blk = [normalize_line(ln, prefix_re) for ln in lines[lo: hi + 1]]

    # Trigger line first: vitest live per-test failure (see docstring).
    self_s = normalize_line(lines[fail_line - 1], prefix_re)
    if self_s[:1] in ("\u276f", "\u00d7") and ">" in self_s:
        ident = VITEST_TRAIL_TIME_RE.sub("", self_s[1:].strip()).strip()
        if ident:
            return hashlib.sha1(("file:" + ident).encode("utf-8", "replace")).hexdigest()[:16]

    for s in blk:
        if "✕" in s:
            name = s.split("✕", 1)[1].strip()
            if name:
                return hashlib.sha1(("test:" + name).encode("utf-8", "replace")).hexdigest()[:16]
    for s in blk:
        if "●" in s and "›" in s:
            name = s.split("›", 1)[1].strip()
            if name:
                return hashlib.sha1(("test:" + name).encode("utf-8", "replace")).hexdigest()[:16]
    for s in blk:
        if s.startswith("FAIL"):
            path = s[4:].strip()
            if path:
                return hashlib.sha1(("file:" + path).encode("utf-8", "replace")).hexdigest()[:16]
    # Fallback: normalized block (failure line + lines below). Exact re-prints share
    # an identical block and collapse; distinct messages (e.g. different console output)
    # stay separate.
    block = "\n".join(normalize_line(ln, prefix_re) for ln in lines[fail_line - 1: fail_line - 1 + window])
    return hashlib.sha1(("blk:" + block).encode("utf-8", "replace")).hexdigest()[:16]


def get_key():
    """Read a single keypress. Returns an arrow token, a char, or 'ESC'."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        ch = sys.stdin.read(1)
        if ch == "\x03":  # Ctrl-C
            raise KeyboardInterrupt
        if ch == "\x1b":
            ch2 = sys.stdin.read(1)
            ch3 = sys.stdin.read(1)
            return {
                "A": "UP",
                "B": "DOWN",
                "C": "RIGHT",
                "D": "LEFT",
            }.get(ch3, "ESC")
        return ch
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def labels_path(project):
    return os.path.join(REPO_ROOT, "projects", project, "failure_labels_project.csv")


def load_existing(project):
    path = labels_path(project)
    rows = []
    if os.path.isfile(path):
        with open(path, newline="") as f:
            rows = list(csv.DictReader(f))
    for r in rows:
        r.setdefault("occurrences", "1")
    done = {r["fingerprint"] for r in rows if r.get("fingerprint")}
    return path, rows, done


def _collect_spans(lines):
    """Return the list of (name, start, end) suite spans in *lines* (1-indexed).

    Scanning the log for span markers is O(len(lines)); callers that need spans
    for several suite names in the same log should compute this once and reuse
    it via _select_span instead of calling find_suite_span repeatedly.
    """
    starts, ends = [], []
    for i, ln in enumerate(lines, 1):
        # Markers always contain "[SUITE_"; skip the two regexes for the vast
        # majority of lines (identical result).
        if "[SUITE_" not in ln:
            continue
        m = SUITE_START_RE.search(ln)
        if m:
            starts.append((m.group(1), i))
        m = SUITE_END_RE.search(ln)
        if m:
            ends.append((m.group(1), i))

    spans = []
    for name, s in starts:
        e = next((e_i for n, e_i in ends if n == name and e_i > s), None)
        if e:
            spans.append((name, s, e))
    return spans


def _select_span(spans, stem):
    """Pick the (start, end, name) span matching *stem*, or None."""
    if not spans:
        return None
    stem_norm = stem.replace("-", "_")
    for name, s, e in spans:
        name_norm = name.replace("-", "_")
        if name_norm == stem_norm:
            return (s, e, name)
    for name, s, e in spans:
        name_norm = name.replace("-", "_")
        if stem_norm == name_norm or stem_norm.endswith("_" + name_norm) or stem_norm.startswith(name_norm + "_") or name_norm in stem_norm:
            return (s, e, name)
    return spans[0][1], spans[0][2], spans[0][0]



def find_suite_span(lines, stem):
    """Return (start_line, end_line, matched_name) for the suite, 1-indexed."""
    return _select_span(_collect_spans(lines), stem)


def _combined(compiled):
    """One regex matching any of *compiled*, or None when the list is empty.

    Equivalent to ``any(p.search(t) for p in compiled)`` but with a single
    search. Returns None (so callers keep the ``any`` path) if the alternation
    cannot be compiled, e.g. due to duplicate group names across patterns.
    """
    if not compiled:
        return None
    try:
        return re.compile("|".join("(?:%s)" % p.pattern for p in compiled))
    except re.error:
        return None


def collect_failures(lines, span, min_gap, patterns, excludes):
    """Return list of (line_number, cleaned_text) failure occurrences.

    `patterns` are regexes marking a failure; a line is skipped if it also
    matches any `excludes` regex (both come from the project config).
    """
    start, end, _ = span
    comb_exc = _combined(excludes)
    comb_pat = _combined(patterns)
    hits = []
    for i in range(start, end + 1):
        text = clean(lines[i - 1])
        if comb_exc is not None:
            if comb_exc.search(text):
                continue
        elif any(p.search(text) for p in excludes):
            continue
        if comb_pat is not None:
            if comb_pat.search(text):
                hits.append((i, text))
        elif any(p.search(text) for p in patterns):
            hits.append((i, text))

    out = []
    last = -10**9
    for ln, text in hits:
        if ln - last > min_gap:
            out.append((ln, text))
            last = ln
    return out


# Bounded LRU of parsed run logs, used only to back the lazy `lines` of the
# failure records yielded by iter_failures (most-recently-used last).
_LINES_CACHE = {}
_LINES_CACHE_MAX = 4


def _log_lines(logs_dir, run_id):
    """Return the parsed lines of a run's log, re-reading with a bounded LRU.

    iter_failures streams failures and must not retain every run's log in
    memory. The full `lines` of a run are materialized only when a consumer
    actually indexes `it["lines"]` (interactive labeling / context display).
    """
    lines = _LINES_CACHE.pop(run_id, None)
    if lines is None:
        with open(os.path.join(logs_dir, run_id + ".log"), errors="replace") as fh:
            lines = fh.read().split("\n")
    _LINES_CACHE[run_id] = lines
    while len(_LINES_CACHE) > _LINES_CACHE_MAX:
        _LINES_CACHE.pop(next(iter(_LINES_CACHE)))
    return lines


class _Failure(dict):
    """Failure record whose `lines` are loaded lazily from the run's log.

    Behaves like the plain dict iter_failures used to yield, except that
    `lines` is filled in on first access instead of being held for every run.
    """

    __slots__ = ("_logs_dir", "_run_id")

    def __init__(self, logs_dir, run_id, **fields):
        super().__init__(**fields)
        self["run_id"] = run_id
        self._logs_dir = logs_dir
        self._run_id = run_id

    def __missing__(self, key):
        if key == "lines":
            value = _log_lines(self._logs_dir, self._run_id)
            self["lines"] = value
            return value
        raise KeyError(key)


def iter_failures(project, out_root, min_gap, suite_filter, fp_window=5, cfg=None,
                  fp_mode=None):
    """Yield each failure occurrence as a dict, in deterministic order.

    Failures are deduplicated by a normalized block fingerprint: the first
    occurrence per fingerprint across all logs. `occurrences` is the number of
    distinct runs/commits sharing the fingerprint.

    Streaming implementation: each run's log is read ONCE and only lightweight
    per-failure metadata is retained across runs; the run's `lines` are re-read
    lazily (bounded LRU) when a consumer indexes them. This keeps peak memory
    bounded regardless of corpus size (previously every processed log stayed
    resident, so n8n's ~9 GB of logs needed ~100+ GB of RAM).

    `cfg` is the pattern config used for failure DETECTION. If None, the
    project's failure_patterns.json is loaded (the default/human behavior).
    """
    if cfg is None:
        cfg = load_pattern_config(project)
    prefix_re = resolve_fingerprint(cfg, fp_mode)
    logs_dir = os.path.join(REPO_ROOT, "projects", project, "logs")

    resolved = {}        # suite_stem -> (patterns, excludes)
    fp_runs = {}         # fingerprint -> set of run_ids (distinct-run count)
    order = []           # first-seen record per fingerprint (no `lines`)
    seen = set()

    for run_dir in sorted(os.listdir(out_root)):
        run_path = os.path.join(out_root, run_dir)
        if not os.path.isdir(run_path):
            continue

        # Failing sidecars for this run, in sorted order.
        failing = []
        for ec_file in sorted(os.listdir(run_path)):
            if not ec_file.endswith(".exit_code"):
                continue
            stem = ec_file[: -len(".exit_code")]
            with open(os.path.join(run_path, ec_file)) as f:
                val = f.read().strip()
            try:
                code = int(val)
            except ValueError:
                continue
            if code > 0:
                failing.append((stem, code))
        if not failing:
            continue

        log_path = os.path.join(logs_dir, run_dir + ".log")
        if not os.path.isfile(log_path):
            print(f"[warn] missing log for {run_dir}", file=sys.stderr)
            continue

        # Read the log once for the whole run (was: once per failing sidecar).
        with open(log_path, errors="replace") as f:
            lines = f.read().split("\n")

        # Collect suite spans once for the whole run (span-finding is O(len(lines))
        # and all of a run's failing stems share the same log).
        spans = _collect_spans(lines)

        # Scan the shared span at most once per (span, pattern-set): all of a
        # run's failing stems usually resolve to the same span and the same
        # resolved patterns (n8n averages ~15 failing sidecars/run), and
        # collect_failures is O(len(span)). Iteration order per stem is kept,
        # so first-seen attribution/dedup is unchanged.
        scan_cache = {}

        for stem, code in failing:
            span = _select_span(spans, stem)
            if not span:
                print(f"[warn] no suite span for {run_dir} / {stem}", file=sys.stderr)
                continue
            if suite_filter and suite_filter not in span[2]:
                continue

            if stem not in resolved:
                resolved[stem] = resolve_patterns(cfg, stem)
            pats, excs = resolved[stem]
            sig = (tuple(p.pattern for p in pats), tuple(e.pattern for e in excs))
            key = (span, sig)
            hits = scan_cache.get(key)
            if hits is None:
                hits = collect_failures(lines, span, min_gap, pats, excs)
                scan_cache[key] = hits
            for ln, text in hits:
                fp = fingerprint(ln, lines, fp_window, prefix_re)
                fp_runs.setdefault(fp, set()).add(run_dir)
                if fp in seen:
                    continue
                seen.add(fp)
                order.append({
                    "run_id": run_dir,
                    "suite": stem,
                    "exit_code": code,
                    "line": ln,
                    "text": text,
                    "span": span,
                    "fp": fp,
                })
        del lines

    total = len(order)
    for idx, f in enumerate(order, 1):
        yield _Failure(
            logs_dir,
            f["run_id"],
            suite=f["suite"],
            exit_code=f["exit_code"],
            failure_index=idx,
            total=total,
            line=f["line"],
            text=f["text"],
            span=f["span"],
            fp=f["fp"],
            occurrences=len(fp_runs[f["fp"]]),
        )


def print_context(item, c_above, c_below):
    lines = item["lines"]
    start, end, name = item["span"]
    fail_line = item["line"]
    lo = max(start, fail_line - c_above)
    hi = min(end, fail_line + c_below)
    window = lines[lo - 1: hi]
    env_hits = env_signals(window)

    print("\n" + "─" * 72)
    print(f"failure {item['failure_index']}/{item['total']}  | "
          f"{item['run_id']}  | suite={name}  | exit={item['exit_code']}  | line {fail_line}")
    if env_hits:
        print(f"  \033[93m⚠ ENV (likely problematic — not a real test failure): {', '.join(env_hits)}\033[0m")
    for i in range(lo, hi + 1):
        marker = "▶" if i == fail_line else " "
        txt = clean(lines[i - 1])
        if i == fail_line:
            print(f"{marker} \033[91m{i:5}: {txt}\033[0m")
        else:
            print(f"{marker}  {i:5}: {txt}")
    print("─" * 72)
    print("↑ acceptable   ↓ problematic   space unclear   → false_positive   e re-eval   . create-rule   r reload-rules   ← undo   s skip   q quit")


def build_item_from_row(row, project):
    """Reconstruct a displayable item dict from a stored CSV row."""
    run_id = row["run_id"]
    stem = row["suite"]
    line = int(row["line_number"])
    log_path = os.path.join(REPO_ROOT, "projects", project, "logs", run_id + ".log")
    if not os.path.isfile(log_path):
        return None
    with open(log_path, errors="replace") as f:
        lines = f.read().split("\n")
    span = find_suite_span(lines, stem)
    if not span:
        return None
    return {
        "run_id": run_id,
        "suite": stem,
        "exit_code": row.get("exit_code", ""),
        "failure_index": int(row["failure_index"]),
        "total": 1,
        "line": line,
        "text": row["keyword"],
        "span": span,
        "lines": lines,
    }


def parse_args():
    p = argparse.ArgumentParser(description="Interactive failure classifier.")
    p.add_argument("--project", required=True, help="Project name (must be in projects/).")
    p.add_argument("--context", type=int, default=None,
                   help="Lines shown above AND below a failure (sets both).")
    p.add_argument("--context-above", type=int, default=4,
                   help="Lines shown ABOVE a failure (failure detail follows the marker).")
    p.add_argument("--context-below", type=int, default=40,
                   help="Lines shown BELOW a failure (where the error is).")
    p.add_argument("--min-gap", type=int, default=None,
                   help="Only report a failure if it is more than N lines after the previous "
                        "one. Omitted -> use the project config's top-level 'min_gap', else 5.")
    p.add_argument("--suite", type=str, default=None, help="Only process suites whose name contains this.")
    p.add_argument("--only-unlabeled", action="store_true", default=True,
                   help="Skip failures already present in failure_labels_project.csv (default).")
    p.add_argument("--all", dest="only_unlabeled", action="store_false",
                   help="Re-process even already-labeled failures.")
    p.add_argument("--dry-run", action="store_true",
                   help="Print failures without prompting; do not store labels.")
    p.add_argument("--report-env", action="store_true",
                   help="List failures matching environment signals with their current label.")
    p.add_argument("--auto-classify", action="store_true",
                   help="Non-interactively apply auto_classify rules to all unlabeled failures.")
    p.add_argument("--verify", action="store_true",
                   help="Drop labels whose failure no longer occurs in the current output, then "
                        "continue in the normal labeling flow (re-label only what changed).")
    p.add_argument("--review", type=str, default=None, choices=ALL_LABELS,
                   help="Re-display existing labels of the given class and let you change them.")
    p.add_argument("--fp-window", type=int, default=5,
                   help="Size of the normalized failure block (failure line + N-1 below) used to dedupe re-prints.")
    p.add_argument("--fingerprint", type=str, default=None,
                   choices=["default", "pkg-prefix"],
                   help="Override the dedup fingerprint strategy. 'default' = historical "
                        "behavior; 'pkg-prefix' = strip a leading turbo 'pkg:task:' prefix "
                        "before fingerprinting (fixes cross-run dedup for prefixed logs). "
                        "Omitted -> use the project config's fingerprint.strip_package_prefix.")
    p.add_argument("--dedup", type=str, default="project", choices=["project"],
                   help="Deduplicate across all logs into failure_labels_project.csv (only mode).")
    return p.parse_args()


def save_rows(path, rows):
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=[
            "project", "run_id", "suite", "exit_code",
            "failure_index", "line_number", "keyword", "label", "labeled_at",
            "fingerprint", "occurrences", "auto_rule_id",
        ])
        w.writeheader()
        for r in rows:
            w.writerow(r)


def do_report_env(args, out_root, existing_rows):
    label_of = {r.get("fingerprint"): r["label"] for r in existing_rows}
    shown = 0
    for it in iter_failures(args.project, out_root, args.min_gap, args.suite, args.fp_window,
                            args.fingerprint):
        start, end, _ = it["span"]
        hits = env_signals(it["lines"][start - 1: end])
        if not hits:
            continue
        lab = label_of.get(it["fp"], "unlabeled")
        print(f"[{it['run_id']}] {it['suite']} #{it['failure_index']} L{it['line']} "
              f"label={lab} occ={it['occurrences']}  env={{{', '.join(hits)}}}  :: {it['text'][:80]}")
        shown += 1
        print(f"\nenv-signal failures shown: {shown}")


def do_auto_classify(args, out_root, csv_path, existing_rows):
    """Apply auto_classify rules to all (unlabeled) failures non-interactively."""
    rules = load_auto_rules(args.project)
    if not rules:
        print("no auto_classify rules in project config; nothing to do")
        return
    done = {r["fingerprint"] for r in existing_rows}
    current = {}
    for r in existing_rows:
        current[r["fingerprint"]] = dict(r)
    applied = 0
    for it in iter_failures(args.project, out_root, args.min_gap, args.suite,
                             args.fp_window, args.fingerprint):
        key = it["fp"]
        if args.only_unlabeled and key in done:
            continue
        res = match_auto_rule(it, rules)
        if res is None:
            continue
        lab, rid = res
        current[key] = {
            "project": args.project,
            "run_id": it["run_id"],
            "suite": it["suite"],
            "exit_code": it["exit_code"],
            "failure_index": it["failure_index"],
            "line_number": it["line"],
            "keyword": it["text"],
            "label": lab,
            "labeled_at": datetime.now(timezone.utc).isoformat(),
            "fingerprint": it["fp"],
            "occurrences": it["occurrences"],
            "auto_rule_id": rid,
        }
        applied += 1
    save_rows(csv_path, list(current.values()))
    print(f"auto-classified {applied} failures (project={args.project})")


def do_review(args, csv_path, existing_rows):
    if not existing_rows:
        print("no labels to review")
        return
    filtered = [(i, r) for i, r in enumerate(existing_rows) if r["label"] == args.review]
    if not filtered:
        print(f"no labels with class {args.review!r}")
        return

    history = []  # (filtered_position, prev_label)
    cur = 0
    changed = 0
    while cur < len(filtered):
        pos, row = filtered[cur]
        item = build_item_from_row(row, args.project)
        if not item:
            print(f"[skip] cannot reconstruct {row['run_id']} {row['suite']} #{row['failure_index']}")
            cur += 1
            continue
        item["total"] = len(filtered)
        item["failure_index"] = cur + 1
        print(f"\n[current label: {row['label']}]")
        print_context(item, c_above, c_below)
        k = get_key()
        if k in LABELS:
            prev = row["label"]
            row["label"] = LABELS[k]
            row["labeled_at"] = datetime.now(timezone.utc).isoformat()
            history.append((cur, prev))
            save_rows(csv_path, existing_rows)
            changed += 1
            print(f"  -> changed {prev} -> {LABELS[k]}")
            cur += 1
        elif k == "LEFT":
            if history:
                c, prev = history.pop()
                filtered[c][1]["label"] = prev
                save_rows(csv_path, existing_rows)
                changed += 1
                cur = c
                print("  -> undo")
            else:
                print("  -> nothing to undo")
        elif k in ("s",):
            cur += 1
        elif k in ("q", "ESC"):
            print("  -> quit")
            break
    print(f"\nreview done. labels changed: {changed}")


def main():
    args = parse_args()
    # `--min-gap` may be omitted -> fall back to the project config's `min_gap`
    # so the proximity window is reproducible from failure_patterns.json.
    cfg = load_pattern_config(args.project)
    if args.min_gap is None:
        args.min_gap = int(cfg.get("min_gap", 5))
    if args.context is not None:
        c_above = c_below = args.context
    else:
        c_above, c_below = args.context_above, args.context_below
    out_root = os.path.join(REPO_ROOT, "projects", args.project, "output")
    if not os.path.isdir(out_root):
        print(f"no output dir for project {args.project!r}", file=sys.stderr)
        sys.exit(1)

    csv_path, existing_rows, done = load_existing(args.project)
    rules = load_auto_rules(args.project)

    if args.report_env:
        do_report_env(args, out_root, existing_rows)
        return

    if args.auto_classify:
        do_auto_classify(args, out_root, csv_path, existing_rows)
        return

    if args.review:
        do_review(args, csv_path, existing_rows)
        return

    failures = list(iter_failures(args.project, out_root, args.min_gap, args.suite,
                                  args.fp_window, args.fingerprint))

    # --verify: drop labels whose failure no longer occurs in the current output,
    # then fall through to the normal labeling flow so only newly-changed failures
    # are re-presented. The auto_classify rules stay in place, so a resolved error
    # that reappears is re-detected and surfaces again.
    if args.verify:
        present = {it["fp"] for it in failures}
        before = len(existing_rows)
        existing_rows = [r for r in existing_rows if r.get("fingerprint") in present]
        done = {r["fingerprint"] for r in existing_rows if r.get("fingerprint")}
        print(f"[verify] dropped {before - len(existing_rows)} resolved label(s); "
              f"{len(existing_rows)} still present, {len(failures)} current failures")

    if args.dry_run:
        for it in failures:
            print(f"[{it['run_id']}] {it['suite']} exit={it['exit_code']} "
                  f"#{it['failure_index']}/{it['total']} L{it['line']} occ={it['occurrences']}: {it['text']}")
        return

    # Working set keyed by fingerprint. Seeded from existing_rows so prior labels
    # are ALWAYS preserved (the previous flush() discarded them -> data loss bug).
    def keyfn(it):
        return it["fp"]

    current = {}
    for r in existing_rows:
        current[r["fingerprint"]] = dict(r)

    history = []  # (action, key, prev_row_or_None)
    labeled = 0
    skipped = 0
    auto_labeled = 0

    def flush():
        save_rows(csv_path, list(current.values()))

    i = 0
    while i < len(failures):
        # Reload rules from disk every page so regex rules manually added to
        # failure_patterns.json mid-session take effect immediately.
        rules = load_auto_rules(args.project)
        it = failures[i]
        key = keyfn(it)
        if args.only_unlabeled and key in done:
            i += 1
            continue

        # Auto-classify: if a rule matches, label silently and move on.
        res = match_auto_rule(it, rules)
        if res is not None:
            auto_label, rid = res
            current[key] = {
                "project": args.project,
                "run_id": it["run_id"],
                "suite": it["suite"],
                "exit_code": it["exit_code"],
                "failure_index": it["failure_index"],
                "line_number": it["line"],
                "keyword": it["text"],
                "label": auto_label,
                "labeled_at": datetime.now(timezone.utc).isoformat(),
                "fingerprint": it["fp"],
                "occurrences": it["occurrences"],
                "auto_rule_id": rid,
            }
            flush()
            labeled += 1
            auto_labeled += 1
            print(f"  -> auto-labeled {auto_label}: {it['text'][:60]}")
            i += 1
            continue

        print_context(it, c_above, c_below)
        k = get_key()

        if k in LABELS:
            prev = current.get(key)
            current[key] = {
                "project": args.project,
                "run_id": it["run_id"],
                "suite": it["suite"],
                "exit_code": it["exit_code"],
                "failure_index": it["failure_index"],
                "line_number": it["line"],
                "keyword": it["text"],
                "label": LABELS[k],
                "labeled_at": datetime.now(timezone.utc).isoformat(),
                "fingerprint": it["fp"],
                "occurrences": it["occurrences"],
                "auto_rule_id": "",
            }
            history.append(("label", key, prev, i))
            flush()
            labeled += 1
            print(f"  -> labeled {LABELS[k]}")
            i += 1
        elif k == ".":
            # Create an auto_classify rule from this failure's error body,
            # letting the user choose how many lines below the trigger to capture.
            print("  body lines below trigger [5] (0 = matched line only): ", end="", flush=True)
            try:
                ans = input()
            except EOFError:
                ans = ""
            ans = ans.strip()
            if ans == "0":
                n = 0
            elif ans.isdigit() and 1 <= int(ans) <= 60:
                n = int(ans)
            else:
                n = 5
            lab = (current.get(key) or {}).get("label")
            if not lab:
                print("  choose label for rule: ↑ acceptable  ↓ problematic  space unclear  → false_positive  e re-eval")
                kk = get_key()
                if kk in LABELS:
                    lab = LABELS[kk]
                    current[key] = {
                        "project": args.project,
                        "run_id": it["run_id"],
                        "suite": it["suite"],
                        "exit_code": it["exit_code"],
                        "failure_index": it["failure_index"],
                        "line_number": it["line"],
                        "keyword": it["text"],
                        "label": lab,
                        "labeled_at": datetime.now(timezone.utc).isoformat(),
                        "fingerprint": it["fp"],
                        "occurrences": it["occurrences"],
                        "auto_rule_id": "",
                    }
                    flush()
                    labeled += 1
                else:
                    print("  -> no label chosen, rule not created")
                    i += 1
                    continue
            body = item_body(it, n)
            rid = add_auto_rule(args.project, body, lab, lines=n)
            rules.append((re.escape(body), lab, "", n, rid))
            print(f"  -> rule created (label={lab}, lines={n}); future matches auto-labeled")
            i += 1
        elif k == "LEFT":
            if history:
                kind, k2, prev, pos = history.pop()
                if kind == "label":
                    if prev is None:
                        current.pop(k2, None)
                    else:
                        current[k2] = prev
                    flush()
                    labeled -= 1
                i = pos
                print("  -> undo")
            else:
                print("  -> nothing to undo")
        elif k in ("s",):
            history.append(("skip", key, None))
            skipped += 1
            print("  -> skipped")
            i += 1
        elif k in ("r", "R"):
            # Reload rules from disk and re-check the CURRENT item against them,
            # so rules added/edited externally (e.g. in failure_patterns.json)
            # apply to the failure already on screen.
            rules = load_auto_rules(args.project)
            res = match_auto_rule(it, rules)
            if res is not None:
                auto_label, rid = res
                current[key] = {
                    "project": args.project,
                    "run_id": it["run_id"],
                    "suite": it["suite"],
                    "exit_code": it["exit_code"],
                    "failure_index": it["failure_index"],
                    "line_number": it["line"],
                    "keyword": it["text"],
                    "label": auto_label,
                    "labeled_at": datetime.now(timezone.utc).isoformat(),
                    "fingerprint": it["fp"],
                    "occurrences": it["occurrences"],
                    "auto_rule_id": rid,
                }
                flush()
                labeled += 1
                auto_labeled += 1
                print(f"  -> reloaded rules, auto-labeled {auto_label}: {it['text'][:60]}")
                i += 1
            else:
                print("  -> reloaded rules, no match for current item; unchanged")
        elif k in ("q", "ESC"):
            print("  -> quit")
            break

    # Persist even when nothing new was labeled (e.g. --verify pruned resolved rows
    # and every remaining failure already had a label).
    flush()
    print(f"done. labeled={labeled} auto-labeled={auto_labeled} skipped={skipped}")


if __name__ == "__main__":
    main()
