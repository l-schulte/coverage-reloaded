"""argparse + dispatch for check_failures_v2.py."""

import argparse
import os
import sys

from . import config, detect, label, metrics, paths, store
from .config import ALL_LABELS


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="v2 failure-fingerprint classifier")
    p.add_argument("project")
    p.add_argument("--window", choices=["min", "max", "both"], default="min")
    p.add_argument("--build", action="store_true", help="scan and write SQLite + CSVs")
    p.add_argument("--dedup", action="store_true", help="alias for --build")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--verify", action="store_true")
    p.add_argument("--verify-only", action="store_true")
    p.add_argument("--review", choices=ALL_LABELS)
    p.add_argument("--auto-classify", action="store_true")
    p.add_argument("--report-env", action="store_true")
    p.add_argument("--stats", action="store_true")
    p.add_argument("--progress", action="store_true",
                   help="labeling progress: labeled vs total fingerprints/detections/runs")
    p.add_argument("--analyze", action="store_true")
    p.add_argument("--crosscheck-v1", action="store_true",
                   help="cross-check retired v1 labels against v2 fingerprints; "
                        "writes the double-check artifact into label_analysis/v1/")
    p.add_argument("--all", dest="only_unlabeled", action="store_false")
    p.add_argument("--only-unlabeled", dest="only_unlabeled", action="store_true",
                   default=True)
    p.add_argument("--context-above", type=int, default=4)
    p.add_argument("--context-below", type=int, default=40)
    p.add_argument("--min-gap", type=int, default=None)
    p.add_argument("--suite", default=None)
    p.add_argument("--output-dir", default=None)
    p.add_argument("--db", default=None, help="SQLite path, or 'none'")
    return p.parse_args(argv)


def do_build(project, cfg, args, con, windows):
    pdir = paths.project_dir(project)
    out_root = args.output_dir or os.path.join(pdir, "output")
    os.makedirs(paths.analysis_dir(project), exist_ok=True)
    min_gap = args.min_gap if args.min_gap is not None else int(cfg.get("min_gap", 5))
    families, failures, runs = detect.scan(
        project, cfg, out_root, min_gap, args.suite, windows,
    )
    label_rows_db = []
    for w in windows:
        name = "min" if w == 2 else "max"
        rows = store.build_csv_rows(project, w, families)
        store.save_csv(paths.csv_path(project, w), rows)
        for r in rows:
            if r["label"]:
                label_rows_db.append((name, r["fingerprint"], r["label"],
                                      r["labeled_at"], r["auto_rule_id"]))
        print(f"wrote {paths.csv_path(project, w)} ({len(rows)} fingerprints)")
    if con is not None:
        store.write_db(con, failures, runs, label_rows_db)
        unique = con.execute("SELECT COUNT(*) FROM failures").fetchone()[0]
        print(f"wrote {args.db or paths.db_path(project)} "
              f"({len(failures)} detections -> {unique} unique tuples, {len(runs)} runs)")


def main(argv=None):
    args = parse_args(argv)
    project = args.project
    pdir = paths.project_dir(project)
    if not os.path.isdir(pdir):
        sys.exit(f"[error] project {project!r} not found at {pdir}")
    cfg = config.load_pattern_config(project)
    windows = ([2, 5] if args.window == "both"
               else ([2] if args.window == "min" else [5]))

    con = None
    if args.db != "none":
        db_file = args.db or paths.db_path(project)
        db_dir = os.path.dirname(db_file)
        if db_dir:
            os.makedirs(db_dir, exist_ok=True)
        con = store.open_db(db_file)

    if args.build or args.dedup:
        do_build(project, cfg, args, con, windows)
        return
    if args.progress:
        for w in windows:
            metrics.do_progress(project, con, w)
        return
    if args.stats:
        for w in (2, 5):
            metrics.do_progress(project, con, w)
        metrics.do_stats(project, con)
        return
    if args.analyze:
        metrics.do_analyze(project, 5 if args.window == "max" else 2, con)
        return
    if args.crosscheck_v1:
        metrics.do_crosscheck(project, con)
        return

    window = 5 if args.window == "max" else 2
    if args.dry_run:
        rows = store.load_csv(paths.csv_path(project, window))
        for r in rows[:200]:
            print(f"[{r['run_id']}] {r['suite']} L{r['line_number']} "
                  f"fp={r['fingerprint']} n_runs={r['n_runs']} "
                  f"variants={r['n_variants']}: {r['keyword'][:80]}")
        return
    if args.verify:
        label.do_verify(project, window, cfg, args, con)
        return
    if args.review:
        label.do_review(project, window, args, con)
        return
    if args.auto_classify:
        label.do_auto_classify(project, window, con)
        return
    if args.report_env:
        label.do_report_env(project, window, args, con)
        return

    label.label_rows(project, window, args, con)
