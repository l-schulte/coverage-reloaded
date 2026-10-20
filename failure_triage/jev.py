"""Jev v2: independent automated classification on v2 fingerprints.

Jev remains a separate labeler and a separate artifact
(`failure_labels_jev_min.csv`). It shares the v2 family definitions (fp_min /
fp_max) and the SQLite run-set sidecar, but never writes the human label CSVs.

The provider/prompt layer lives in `failure_triage/jev_provider.py` (vendored
from the v1 labeler when it was archived, now v2-owned); Jev v2 has no
dependency on the frozen v1 toolchain. v2 only changes detection input,
output schema, confirmation and union reporting.
"""

import argparse
import asyncio
import csv
import json
import os
import sys
from datetime import datetime, timezone

from . import config, detect, jev_provider, paths, store

JEV_FIELDS = [
    "project", "window", "run_id", "suite", "exit_code", "line_number",
    "fingerprint", "n_runs", "keyword", "is_pipeline_issue", "confidence",
    "env_subsystem", "labeled_at",
]


def jev_csv_path(project, window):
    name = "min" if window == 2 else "max"
    return os.path.join(paths.analysis_dir(project),
                        f"failure_labels_jev_{name}.csv")


def load_jev_labels(path):
    if not os.path.isfile(path):
        return {}
    with open(path, newline="") as f:
        return {r["fingerprint"]: r for r in csv.DictReader(f)
                if r.get("fingerprint")}


def save_jev_labels(path, rows):
    rows = sorted(rows, key=lambda r: (r["run_id"], int(r["line_number"])))
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=JEV_FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in JEV_FIELDS})


def _load_env_file():
    env_file = os.path.join(paths.REPO_ROOT, ".env")
    if not os.path.isfile(env_file):
        return
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k and k not in os.environ:
                    os.environ[k] = v


def resolve_provider(provider):
    eden_key = os.getenv("EDENAI_API_KEY")
    typesafe_key = os.getenv("TYPESAFE_API_KEY")
    if provider == "auto":
        if eden_key:
            return "edenai", eden_key
        if typesafe_key:
            return "typesafe", typesafe_key
        print("[error] Neither EDENAI_API_KEY nor TYPESAFE_API_KEY is set.",
              file=sys.stderr)
        sys.exit(1)
    if provider == "edenai":
        if not eden_key:
            print("[error] EDENAI_API_KEY environment variable is not set.",
                  file=sys.stderr)
            sys.exit(1)
        return "edenai", eden_key
    if not typesafe_key:
        print("[error] TYPESAFE_API_KEY environment variable is not set.",
              file=sys.stderr)
        sys.exit(1)
    return "typesafe", typesafe_key


def build_items(project, window, suite_filter, limit, only_unlabeled):
    """Return (items, already_labeled_count, total_candidates)."""
    pdir = paths.project_dir(project)
    rows = store.load_csv(paths.csv_path(project, window))
    if not rows:
        print(f"[error] no rows in {paths.csv_path(project, window)}; "
              f"run --build first", file=sys.stderr)
        return [], 0, 0
    existing = load_jev_labels(jev_csv_path(project, window))
    candidates = [r for r in rows if not suite_filter or suite_filter in r["suite"]]
    total = len(candidates)
    if only_unlabeled and existing:
        candidates = [r for r in candidates if r["fingerprint"] not in existing]
    already = total - len(candidates)
    if limit:
        candidates = candidates[:limit]

    items = []
    for r in candidates:
        lines = detect.iter_log_lines(project, r["run_id"])
        if lines is None:
            continue
        spans = detect._collect_spans(lines)
        span = detect._select_span(spans, r["suite"])
        if not span:
            continue
        items.append({
            "project": project,
            "run_id": r["run_id"],
            "suite": r["suite"],
            "exit_code": int(r["exit_code"]),
            "line": int(r["line_number"]),
            "text": r["keyword"],
            "fp": r["fingerprint"],
            "occurrences": int(r["n_runs"]),
            "lines": lines,
            "span": span,
        })
    return items, already, total


async def classify_batch(project, window, provider, api_key, model, items,
                         existing, concurrency, c_above, c_below):
    sem = asyncio.Semaphore(concurrency)
    write_lock = asyncio.Lock()
    out_path = jev_csv_path(project, window)
    all_rows = dict(existing)
    total = len(items)
    completed = 0

    if provider == "typesafe":
        try:
            from typesafe_sdk import AsyncTypeSafeClient
        except ImportError:
            print("[error] typesafe-sdk is not installed. Run: "
                  "pip install typesafe-sdk", file=sys.stderr)
            sys.exit(1)
        client = AsyncTypeSafeClient()
        sdk_questions = jev_provider.get_jev_questions_sdk()
    else:
        eden_questions = jev_provider.get_jev_questions_dict()

    async def one(it):
        nonlocal completed
        state = jev_provider.build_state_for_item(it, c_above, c_below)
        async with sem:
            try:
                if provider == "typesafe":
                    resp = await client.system_one(state=state,
                                                   questions=sdk_questions)
                    noul = resp.nouls["is_pipeline_issue"]
                    choice = resp.choices["env_subsystem"]
                    is_issue = bool(noul.noul)
                    conf = getattr(noul, "probability",
                                   getattr(noul, "score", 1.0))
                    subsystem = choice.choice
                else:
                    is_issue, conf, subsystem = await asyncio.to_thread(
                        jev_provider.call_edenai_decisions_sync,
                        api_key, state, eden_questions, model,
                    )
                row = {
                    "project": project,
                    "window": "min" if window == 2 else "max",
                    "run_id": it["run_id"],
                    "suite": it["suite"],
                    "exit_code": it["exit_code"],
                    "line_number": it["line"],
                    "fingerprint": it["fp"],
                    "n_runs": it["occurrences"],
                    "keyword": it["text"][:120],
                    "is_pipeline_issue": str(is_issue),
                    "confidence": f"{conf:.4f}",
                    "env_subsystem": subsystem,
                    "labeled_at": datetime.now(timezone.utc).isoformat(),
                }
                async with write_lock:
                    all_rows[row["fingerprint"]] = row
                    save_jev_labels(out_path, list(all_rows.values()))
                    completed += 1
                    status = ("PROBLEMATIC" if is_issue else "ACCEPTABLE")
                    print(f"[{completed}/{total}] {it['run_id']} L{it['line']} "
                          f"-> {status} ({conf*100:.1f}% | {subsystem})")
            except Exception as e:
                print(f"[error] {it['run_id']} L{it['line']}: {e}",
                      file=sys.stderr)

    await asyncio.gather(*(one(it) for it in items))
    return all_rows


def print_report(project, window, con):
    name = "min" if window == 2 else "max"
    path = jev_csv_path(project, window)
    if not os.path.isfile(path):
        print(f"No Jev labels at {path}. Run without --report first.")
        return
    rows = list(csv.DictReader(open(path, newline="")))
    if not rows:
        print("Jev labels file is empty.")
        return
    issues = [r for r in rows if r.get("is_pipeline_issue", "").lower() == "true"]
    acceptable = [r for r in rows if r.get("is_pipeline_issue", "").lower() == "false"]

    def union_runs(group):
        if con is None:
            print("[warn] no SQLite sidecar; run counts are per-fingerprint "
                  "sums, not unions", file=sys.stderr)
            return sum(int(r.get("n_runs", 1)) for r in group)
        fps = [r["fingerprint"] for r in group]
        runs = set()
        for chunk in store.chunks(fps):
            ph = ",".join("?" * len(chunk))
            runs.update(x[0] for x in con.execute(
                f"SELECT DISTINCT run_id FROM failures WHERE fp_{name} IN ({ph})",
                chunk,
            ).fetchall())
        return len(runs)

    print("=" * 76)
    print(f" JEV v2 PIPELINE HEALTH — {project} ({name})")
    print("=" * 76)
    print(f"fingerprints: {len(rows)}  "
          f"(problematic {len(issues)}, acceptable {len(acceptable)})")
    print(f"union runs:   problematic {union_runs(issues)}, "
          f"acceptable {union_runs(acceptable)}")
    print("-" * 76)
    print(f"{'Subsystem':<24} {'Unique':<8} {'Union runs':<10} Sample keyword")
    print("-" * 76)
    subsystems = {}
    for r in issues:
        subsystems.setdefault(r.get("env_subsystem", "unspecified"), []).append(r)
    for sub, group in sorted(subsystems.items(),
                             key=lambda kv: -len(kv[1])):
        print(f"{sub:<24} {len(group):<8} {union_runs(group):<10} "
              f"{group[0].get('keyword', '')[:36]}")
    print("=" * 76)


def parse_args(argv=None):
    p = argparse.ArgumentParser(
        description="Jev v2 automated failure classifier (independent labels).")
    p.add_argument("--project", required=False, default=None)
    p.add_argument("--window", choices=["min", "max"], default="min")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--provider", choices=["auto", "edenai", "typesafe"],
                   default="auto")
    p.add_argument("--model", default="typesafe/jev-latest")
    p.add_argument("--suite", default=None)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--concurrency", type=int, default=5)
    p.add_argument("--context-above", type=int, default=4)
    p.add_argument("--context-below", type=int, default=35)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--report", action="store_true")
    p.add_argument("--all", dest="only_unlabeled", action="store_false",
                   default=True)
    p.add_argument("--yes", action="store_true",
                   help="skip the confirmation prompt (still prints the count)")
    p.add_argument("--db", default=None)
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    _load_env_file()

    if args.self_test:
        provider, api_key = resolve_provider(args.provider)
        jev_provider.run_self_test(provider, api_key)
        return

    if not args.project:
        print("[error] --project is required unless --self-test",
              file=sys.stderr)
        sys.exit(1)

    window = 5 if args.window == "max" else 2
    con = None
    if args.db != "none":
        db = args.db or paths.db_path(args.project)
        if os.path.isfile(db):
            con = store.open_db(db)

    if args.report:
        print_report(args.project, window, con)
        return

    items, already, total = build_items(
        args.project, window, args.suite, args.limit, args.only_unlabeled,
    )
    name = "min" if window == 2 else "max"
    print(f"Jev v2 — project {args.project} / window {name}")
    print(f"candidates: {total}  already labeled (skipped): {already}  "
          f"to send: {len(items)}")
    if args.limit:
        print(f"limit: {args.limit}")
    if not items:
        print("Nothing to send.")
        return

    if args.dry_run:
        sample = jev_provider.build_state_for_item(
            items[0], args.context_above, args.context_below)
        print(f"provider: {args.provider}  model: {args.model}")
        print("\n--- [DRY RUN] first state ---")
        print(json.dumps(sample, indent=2)[:4000])
        print("\nNo API calls made.")
        return

    print(f"provider (requested): {args.provider}  model: {args.model}")
    print("\nFirst items:")
    for it in items[:5]:
        print(f"  {it['run_id']} {it['suite']} L{it['line']} "
              f"fp={it['fp']} n_runs={it['occurrences']} :: {it['text'][:70]}")
    if len(items) > 5:
        print(f"  … and {len(items) - 5} more")

    if not args.yes:
        try:
            answer = input(f"\nSend {len(items)} items to the API? [y/N] ")
        except EOFError:
            answer = ""
        if answer.strip().lower() not in ("y", "yes"):
            print("Aborted; no API calls made.")
            return

    provider, api_key = resolve_provider(args.provider)
    print(f"provider: {provider}  model: {args.model}")

    existing = load_jev_labels(jev_csv_path(args.project, window))
    asyncio.run(classify_batch(
        args.project, window, provider, api_key, args.model, items,
        existing, args.concurrency, args.context_above, args.context_below,
    ))
    print(f"\nwrote {jev_csv_path(args.project, window)}")
