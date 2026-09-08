#!/usr/bin/env python3
"""Interactive classifier for non-zero-exit test runs.

Scans a project's output folder for `*.exit_code` sidecars with a value > 0,
locates the matching run log, extracts failure keywords inside the suite span,
and lets you label each failure (one classification per failure occurrence).

Definition of labels (per study):
  acceptable      -> a genuine test failure devs of that era would also have seen
  problematic     -> an ENVIRONMENT issue in our pipeline that caused the failure
  unclear         -> ambiguous / could not decide
  false_positive  -> not a real failure (e.g. jest console-output capture)

Keyboard shortcuts (interactive / review mode):
  ArrowUp    -> acceptable
  ArrowDown  -> problematic
  Space      -> unclear
  ArrowRight -> false_positive
  ArrowLeft  -> undo (re-classify the previous failure)
  s          -> skip (do not label, advance)
  .          -> create auto_classify rule from this failure
  r          -> reload rules from disk and re-check the current item
  q          -> quit (save and exit)

Labels are stored in projects/<project>/failure_labels.csv.

Modes:
  (default)           label unlabeled failures interactively
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
}
ALL_LABELS = ["acceptable", "problematic", "unclear", "false_positive"]


def clean(line):
    return ANSI_RE.sub("", line).rstrip()


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
REPO_PREFIX_RE = re.compile(r"/coverage_reloaded/repo/?")


def normalize_line(line):
    """Normalize a log line so identical failures print differently across a run match."""
    s = ANSI_RE.sub("", line)
    s = s.strip()
    s = TIMING_RE.sub("", s)
    s = REPO_PREFIX_RE.sub("", s)
    if s.startswith("src/"):
        s = s[4:]
    return s


def fingerprint(fail_line, lines, window=5):
    """Stable per-failure identity (sha1) used to dedupe jest's re-prints.

    Rather than hashing a raw block (which differs between jest's mid-run print and
    its end-of-log 'Summary of all failing tests' re-print), extract the failing
    test/file identity from a scan window around the line. This also collapses the
    `FAIL <file>` / `✕ <test>` / `● <suite> › <test>` representations of one failure
    into a single unit.
    """
    lo = max(0, fail_line - 1 - 4)
    hi = fail_line - 1 + window + 4
    blk = [normalize_line(ln) for ln in lines[lo: hi + 1]]

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
    block = "\n".join(normalize_line(ln) for ln in lines[fail_line - 1: fail_line - 1 + window])
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


def labels_path(project, dedup):
    name = "failure_labels.csv" if dedup == "run" else "failure_labels_project.csv"
    return os.path.join(REPO_ROOT, "projects", project, name)


def load_existing(project, dedup):
    path = labels_path(project, dedup)
    rows = []
    if os.path.isfile(path):
        with open(path, newline="") as f:
            rows = list(csv.DictReader(f))
    for r in rows:
        r.setdefault("occurrences", "1")
    if dedup == "project":
        done = {r["fingerprint"] for r in rows if r.get("fingerprint")}
    else:
        done = {(r["run_id"], r["fingerprint"]) for r in rows if r.get("fingerprint")}
    return path, rows, done


def find_suite_span(lines, stem):
    """Return (start_line, end_line, matched_name) for the suite, 1-indexed."""
    starts, ends = [], []
    for i, ln in enumerate(lines, 1):
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

    if not spans:
        return None

    for name, s, e in spans:
        if name == stem:
            return (s, e, name)
    for name, s, e in spans:
        if stem == name or stem.endswith("_" + name) or stem.startswith(name + "_") or name in stem:
            return (s, e, name)
    return spans[0][1], spans[0][2], spans[0][0]


def collect_failures(lines, span, min_gap, patterns, excludes):
    """Return list of (line_number, cleaned_text) failure occurrences.

    `patterns` are regexes marking a failure; a line is skipped if it also
    matches any `excludes` regex (both come from the project config).
    """
    start, end, _ = span
    hits = []
    for i in range(start, end + 1):
        text = clean(lines[i - 1])
        if any(p.search(text) for p in excludes):
            continue
        if any(p.search(text) for p in patterns):
            hits.append((i, text))

    out = []
    last = -10**9
    for ln, text in hits:
        if ln - last > min_gap:
            out.append((ln, text))
            last = ln
    return out


def iter_failures(project, out_root, min_gap, suite_filter, fp_window=5, dedup="run", cfg=None):
    """Yield each failure occurrence as a dict, in deterministic order.

    Failures are deduplicated by a normalized block fingerprint:
      - dedup="run"     -> first occurrence per fingerprint *within each log*
      - dedup="project" -> first occurrence per fingerprint *across all logs*
    `occurrences` is the number of distinct runs/commits sharing the fingerprint.

    `cfg` is the pattern config used for failure DETECTION. If None, the
    project's failure_patterns.json is loaded (the default/human behavior).
    """
    fp_runs = {}          # fingerprint -> set of run_ids (distinct-run count)
    all_f = []
    if cfg is None:
        cfg = load_pattern_config(project)
    resolved = {}        # suite_stem -> (patterns, excludes)
    for run_dir in sorted(os.listdir(out_root)):
        run_path = os.path.join(out_root, run_dir)
        if not os.path.isdir(run_path):
            continue
        run_failures = []
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
            if code <= 0:
                continue

            log_path = os.path.join(REPO_ROOT, "projects", project, "logs", run_dir + ".log")
            if not os.path.isfile(log_path):
                print(f"[warn] missing log for {run_dir}", file=sys.stderr)
                continue

            with open(log_path, errors="replace") as f:
                lines = f.read().split("\n")

            span = find_suite_span(lines, stem)
            if not span:
                print(f"[warn] no suite span for {run_dir} / {stem}", file=sys.stderr)
                continue
            if suite_filter and suite_filter not in span[2]:
                continue

            if stem not in resolved:
                resolved[stem] = resolve_patterns(cfg, stem)
            pats, excs = resolved[stem]
            for ln, text in collect_failures(lines, span, min_gap, pats, excs):
                fp = fingerprint(ln, lines, fp_window)
                run_failures.append({
                    "run_id": run_dir,
                    "suite": stem,
                    "exit_code": code,
                    "line": ln,
                    "text": text,
                    "span": span,
                    "lines": lines,
                    "fp": fp,
                })

        for f in run_failures:
            fp_runs.setdefault(f["fp"], set()).add(run_dir)
        all_f.extend(run_failures)

    # Deduplicate. run -> reset seen per log; project -> global seen.
    seen_global = set()
    per_run_seen = {}
    out = []
    for f in all_f:
        seen = seen_global if dedup == "project" else per_run_seen.setdefault(f["run_id"], set())
        if f["fp"] in seen:
            continue
        seen.add(f["fp"])
        out.append(f)

    # Assign failure_index/total: run mode per log (familiar "failure 1/N of this
    # run"), project mode globally across all logs.
    if dedup == "run":
        by_run = {}
        for f in out:
            by_run.setdefault(f["run_id"], []).append(f)
        renumbered = []
        for items in by_run.values():
            for idx, f in enumerate(items, 1):
                g = dict(f)
                g["failure_index"] = idx
                g["total"] = len(items)
                renumbered.append(g)
        out = renumbered
    else:
        out = [dict(f, failure_index=idx, total=len(out))
               for idx, f in enumerate(out, 1)]

    for f in out:
        yield {
            "run_id": f["run_id"],
            "suite": f["suite"],
            "exit_code": f["exit_code"],
            "failure_index": f["failure_index"],
            "total": f["total"],
            "line": f["line"],
            "text": f["text"],
            "span": f["span"],
            "lines": f["lines"],
            "fp": f["fp"],
            "occurrences": 1 if dedup == "run" else len(fp_runs[f["fp"]]),
        }


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
    print("↑ acceptable   ↓ problematic   space unclear   → false_positive   . create-rule   r reload-rules   ← undo   s skip   q quit")


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
    p.add_argument("--min-gap", type=int, default=5,
                   help="Only report a failure if it is more than N lines after the previous one.")
    p.add_argument("--suite", type=str, default=None, help="Only process suites whose name contains this.")
    p.add_argument("--only-unlabeled", action="store_true", default=True,
                   help="Skip failures already present in failure_labels.csv (default).")
    p.add_argument("--all", dest="only_unlabeled", action="store_false",
                   help="Re-process even already-labeled failures.")
    p.add_argument("--dry-run", action="store_true",
                   help="Print failures without prompting; do not store labels.")
    p.add_argument("--report-env", action="store_true",
                   help="List failures matching environment signals with their current label.")
    p.add_argument("--auto-classify", action="store_true",
                   help="Non-interactively apply auto_classify rules to all unlabeled failures.")
    p.add_argument("--review", type=str, default=None, choices=ALL_LABELS,
                   help="Re-display existing labels of the given class and let you change them.")
    p.add_argument("--fp-window", type=int, default=5,
                   help="Size of the normalized failure block (failure line + N-1 below) used to dedupe re-prints.")
    p.add_argument("--dedup", type=str, default="run", choices=["run", "project"],
                   help="run: dedupe within each log (default). project: dedupe across all logs into failure_labels_project.csv.")
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


def do_report_env(args, out_root, existing_rows, dedup):
    if dedup == "project":
        label_of = {r.get("fingerprint"): r["label"] for r in existing_rows}
    else:
        label_of = {(r["run_id"], r.get("fingerprint")): r["label"] for r in existing_rows}
    shown = 0
    for it in iter_failures(args.project, out_root, args.min_gap, args.suite, args.fp_window, dedup):
        start, end, _ = it["span"]
        hits = env_signals(it["lines"][start - 1: end])
        if not hits:
            continue
        key = it["fp"] if dedup == "project" else (it["run_id"], it["fp"])
        lab = label_of.get(key, "unlabeled")
        occ = f" occ={it['occurrences']}" if dedup == "project" else ""
        print(f"[{it['run_id']}] {it['suite']} #{it['failure_index']} L{it['line']} "
              f"label={lab}{occ}  env={{{', '.join(hits)}}}  :: {it['text'][:80]}")
        shown += 1
        print(f"\nenv-signal failures shown: {shown}")


def do_auto_classify(args, out_root, csv_path, existing_rows, dedup):
    """Apply auto_classify rules to all (unlabeled) failures non-interactively."""
    rules = load_auto_rules(args.project)
    if not rules:
        print("no auto_classify rules in project config; nothing to do")
        return
    def keyfn(it):
        return it["fp"] if dedup == "project" else (it["run_id"], it["fp"])
    done = {r["fingerprint"] if dedup == "project" else (r["run_id"], r["fingerprint"])
            for r in existing_rows}
    current = {}
    for r in existing_rows:
        k = r["fingerprint"] if dedup == "project" else (r["run_id"], r["fingerprint"])
        current[k] = dict(r)
    applied = 0
    for it in iter_failures(args.project, out_root, args.min_gap, args.suite,
                             args.fp_window, dedup):
        key = keyfn(it)
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
        else:
            cur += 1
            print(f"  -> unknown key {k!r}, skipped")
    print(f"\nreview done. labels changed: {changed}")


def main():
    args = parse_args()
    if args.context is not None:
        c_above = c_below = args.context
    else:
        c_above, c_below = args.context_above, args.context_below
    out_root = os.path.join(REPO_ROOT, "projects", args.project, "output")
    if not os.path.isdir(out_root):
        print(f"no output dir for project {args.project!r}", file=sys.stderr)
        sys.exit(1)

    csv_path, existing_rows, done = load_existing(args.project, args.dedup)
    rules = load_auto_rules(args.project)

    if args.report_env:
        do_report_env(args, out_root, existing_rows, args.dedup)
        return

    if args.auto_classify:
        do_auto_classify(args, out_root, csv_path, existing_rows, args.dedup)
        return

    if args.review:
        do_review(args, csv_path, existing_rows)
        return

    failures = list(iter_failures(args.project, out_root, args.min_gap, args.suite,
                                  args.fp_window, args.dedup))

    if args.dry_run:
        for it in failures:
            occ = f" occ={it['occurrences']}" if args.dedup == "project" else ""
            print(f"[{it['run_id']}] {it['suite']} exit={it['exit_code']} "
                  f"#{it['failure_index']}/{it['total']} L{it['line']}{occ}: {it['text']}")
        return

    # Working set keyed by the resume key. Seeded from existing_rows so prior labels
    # are ALWAYS preserved (the previous flush() discarded them -> data loss bug).
    def keyfn(it):
        return it["fp"] if args.dedup == "project" else (it["run_id"], it["fp"])

    current = {}
    for r in existing_rows:
        k = r["fingerprint"] if args.dedup == "project" else (r["run_id"], r["fingerprint"])
        current[k] = dict(r)

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
                print("  choose label for rule: ↑ acceptable  ↓ problematic  space unclear  → false_positive")
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
        else:
            history.append(("skip", key, None))
            skipped += 1
            print(f"  -> unknown key {k!r}, skipped")
            i += 1

    print(f"done. labeled={labeled} auto-labeled={auto_labeled} skipped={skipped}")


if __name__ == "__main__":
    main()
