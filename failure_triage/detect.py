"""Suite-span detection, failure collection and the per-project scan."""

import os
import re

from .config import resolve_patterns
from .fingerprint import compute_fingerprints
from .normalize import clean

SUITE_START_RE = re.compile(r"\[SUITE_START\]\s*(\S+)")
SUITE_END_RE = re.compile(r"\[SUITE_END\]\s*(\S+)")


def _collect_spans(lines):
    starts, ends = [], []
    for i, ln in enumerate(lines, 1):
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
    if not spans:
        return None
    stem_norm = stem.replace("-", "_")
    for name, s, e in spans:
        if name.replace("-", "_") == stem_norm:
            return (s, e, name)
    for name, s, e in spans:
        n = name.replace("-", "_")
        if (stem_norm == n or stem_norm.endswith("_" + n)
                or stem_norm.startswith(n + "_") or n in stem_norm):
            return (s, e, name)
    # Fallback: first span, in the same (start, end, name) order as above.
    return spans[0][1], spans[0][2], spans[0][0]


def _combined(compiled):
    if not compiled:
        return None
    try:
        return re.compile("|".join("(?:%s)" % p.pattern for p in compiled))
    except re.error:
        return None


def _compute_excluded_lines(lines, span, exclude_blocks):
    if not exclude_blocks:
        return set()
    start, end, _ = span
    excluded = set()
    for start_re, end_re in exclude_blocks:
        in_block = False
        for i in range(start, end + 1):
            text = clean(lines[i - 1])
            if not in_block:
                if start_re.search(text):
                    in_block = True
                    excluded.add(i)
                    if end_re.search(text):
                        in_block = False
            else:
                excluded.add(i)
                if end_re.search(text):
                    in_block = False
    return excluded


def collect_failures(lines, span, min_gap, patterns, excludes, exclude_blocks=None):
    if min_gap is None:
        min_gap = 5
    start, end, _ = span
    comb_exc = _combined(excludes)
    comb_pat = _combined(patterns)
    blocked_lines = _compute_excluded_lines(lines, span, exclude_blocks) if exclude_blocks else set()
    hits = []
    for i in range(start, end + 1):
        if i in blocked_lines:
            continue
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


def iter_log_lines(project, run_id):
    from .paths import logs_dir
    path = os.path.join(logs_dir(project), run_id + ".log")
    if not os.path.isfile(path):
        return None
    with open(path, errors="replace") as f:
        return f.read().split("\n")


def scan(project, cfg, out_root, min_gap, suite_filter, windows):
    """Return (families, failures, runs).

    families[window] = {fp: {exemplar, runs:set, variants:set, first, last}}
    failures = [{run_id, suite, line, fp_min, fp_max, text, exit_code}]
    runs = {run_id: exit_code}
    """
    if min_gap is None:
        min_gap = int(cfg.get("min_gap", 5))
    resolved = {}
    families = {w: {} for w in windows}
    failures = []
    runs = {}

    for run_dir in sorted(os.listdir(out_root)):
        run_path = os.path.join(out_root, run_dir)
        if not os.path.isdir(run_path):
            continue
        failing = []
        for f in sorted(os.listdir(run_path)):
            if not f.endswith(".exit_code"):
                continue
            try:
                code = int(open(os.path.join(run_path, f)).read().strip())
            except (ValueError, OSError):
                continue
            if code > 0:
                failing.append((f[:-len(".exit_code")], code))
        if not failing:
            continue
        lines = iter_log_lines(project, run_dir)
        if lines is None:
            continue
        runs[run_dir] = max(code for _, code in failing)
        spans = _collect_spans(lines)
        for stem, code in failing:
            span = _select_span(spans, stem)
            if not span:
                continue
            if suite_filter and suite_filter not in span[2]:
                continue
            if stem not in resolved:
                resolved[stem] = resolve_patterns(cfg, stem)
            res = resolved[stem]
            if len(res) == 3:
                pats, excs, blocks = res
            else:
                pats, excs = res
                blocks = None
            for ln, text in collect_failures(lines, span, min_gap, pats, excs, blocks):
                fp_min, fp_max, bmin, bmax = compute_fingerprints(lines, ln)
                failures.append({
                    "run_id": run_dir, "suite": stem, "line": ln,
                    "fp_min": fp_min, "fp_max": fp_max,
                    "text": text, "exit_code": code,
                })
                for w, fp, block, variant in (
                    (2, fp_min, bmin, fp_max),
                    (5, fp_max, bmax, fp_min),
                ):
                    if w not in families:
                        continue
                    rec = families[w].get(fp)
                    if rec is None:
                        rec = {
                            "exemplar": {"run_id": run_dir, "suite": stem,
                                         "line": ln, "text": text,
                                         "exit_code": code, "block": block},
                            "runs": set(),
                            "variants": set(),
                            "first": run_dir,
                            "last": run_dir,
                        }
                        families[w][fp] = rec
                    else:
                        ex = rec["exemplar"]
                        if (run_dir, ln) < (ex["run_id"], ex["line"]):
                            rec["exemplar"] = {"run_id": run_dir, "suite": stem,
                                               "line": ln, "text": text,
                                               "exit_code": code, "block": block}
                        if run_dir < rec["first"]:
                            rec["first"] = run_dir
                        if run_dir > rec["last"]:
                            rec["last"] = run_dir
                    rec["runs"].add(run_dir)
                    rec["variants"].add(variant)
    return families, failures, runs
