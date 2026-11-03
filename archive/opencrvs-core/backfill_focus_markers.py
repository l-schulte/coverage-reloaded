#!/usr/bin/env python3
"""Backfill focus_marker.txt sidecars for already-collected runs.

Exhaustive, parallel, no prefilter: every run's revision is grepped directly, so
a missing sidecar can only mean the commit genuinely has no focus marker. (An
earlier version used a git-log interval prefilter; a false negative there would
silently skip a marked commit, which is unacceptable, so it is gone.)

The sidecar produced by helper/na-if-focus-marker.sh is a pure function of the
commit tree plus the run's revision/timestamp/project, so it can be regenerated
without re-executing any test. This reproduces _na_focus_marker_record()
byte-for-byte and writes <output>/<timestamp>_<revision>/focus_marker.txt -- the
destination execute.sh copies it to after a real run.

Usage:
    python3 backfill_focus_markers.py --workers 100
    python3 backfill_focus_markers.py --dry-run --limit 20
"""

import argparse
import concurrent.futures
import os
import subprocess
import sys
import time

PATTERN = r'(describe|it|context|test|suite)\.only[[:space:]]*\('

TEMPLATE = """Commit: {revision}
Timestamp: {timestamp}
Project: {project}
Runner: {runner}
Policy: per-file .only — the run continues, the marked file(s) only are reduced
Markers: {markers}
Affected files: {files}
Matches:
{matches}
Note: coverage for this commit is valid for every file not listed above. Within the files listed above, the tests that are not marked .only did not execute.
"""


def grep_marker(repo, revision, pathspec):
    """Return the `file:line:content` match lines for one commit.

    git prepends "<revision>:" when a tree-ish is given; the runtime helper
    greps the checked-out working tree and therefore has no prefix, so it is
    stripped here to keep the sidecar identical.
    """
    proc = subprocess.run(
        ["git", "-C", repo, "grep", "-nE", PATTERN, revision, "--", pathspec],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 1:
        return []
    if proc.returncode != 0:
        raise RuntimeError(
            f"git grep failed for {revision} (rc={proc.returncode}): {proc.stderr.strip()}"
        )
    prefix = revision + ":"
    return [
        line[len(prefix):] if line.startswith(prefix) else line
        for line in proc.stdout.splitlines()
        if line.strip()
    ]


def human(seconds):
    m, s = divmod(int(seconds), 60)
    return f"{m}m{s:02d}s"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project-dir", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--repo", default="repo")
    ap.add_argument("--pathspec", default="packages")
    ap.add_argument("--runner", default="jest vitest")
    ap.add_argument("--project-id", default="opencrvs-core")
    ap.add_argument("--workers", type=int, default=64)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    output_dir = os.path.join(args.project_dir, "output")
    if not os.path.isdir(output_dir):
        raise SystemExit(f"no output directory: {output_dir}")

    todo = []
    already = 0
    skipped_no_coverage = 0
    for run in sorted(os.listdir(output_dir)):
        run_dir = os.path.join(output_dir, run)
        if not os.path.isdir(run_dir):
            continue
        if not any(f.endswith(".lcov") for f in os.listdir(run_dir)):
            skipped_no_coverage += 1  # hard error: no coverage to qualify
            continue
        if os.path.exists(os.path.join(run_dir, "focus_marker.txt")):
            already += 1
            continue
        if "_" not in run:
            print(f"WARNING: unexpected run directory name: {run}", file=sys.stderr)
            continue
        timestamp, revision = run.split("_", 1)
        todo.append((run, timestamp, revision))
        if args.limit and len(todo) >= args.limit:
            break

    total = len(todo)
    print(
        f"runs to scan: {total} | already have a sidecar: {already} | "
        f"hard errors (no lcov): {skipped_no_coverage} | workers: {args.workers}",
        flush=True,
    )

    started = time.time()
    done = 0
    written = 0
    no_marker = 0

    def work(item):
        run, timestamp, revision = item
        return item, grep_marker(args.repo, revision, args.pathspec)

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(work, item) for item in todo]
        try:
            for fut in concurrent.futures.as_completed(futures):
                (run, timestamp, revision), matches = fut.result()
                done += 1
                if not matches:
                    no_marker += 1
                else:
                    files = len({m.split(":", 1)[0] for m in matches})
                    content = TEMPLATE.format(
                        revision=revision,
                        timestamp=timestamp,
                        project=args.project_id,
                        runner=args.runner,
                        markers=len(matches),
                        files=files,
                        matches="\n".join("  " + m for m in matches),
                    )
                    if args.dry_run:
                        print(f"[dry-run] would write {run} ({len(matches)} markers / {files} files)")
                    else:
                        with open(os.path.join(output_dir, run, "focus_marker.txt"), "w", encoding="utf-8") as fh:
                            fh.write(content)
                    written += 1
                if done % 500 == 0 or done == total:
                    elapsed = time.time() - started
                    rate = elapsed / done
                    eta = rate * (total - done)
                    print(
                        f"  {done}/{total} scanned | sidecars={written} | {rate*1000:.0f} ms/run | "
                        f"elapsed {human(elapsed)} | eta {human(eta)}",
                        flush=True,
                    )
        except Exception:
            for f in futures:
                f.cancel()
            raise

    verb = "would write" if args.dry_run else "wrote"
    print(
        f"done in {human(time.time() - started)} | runs scanned: {total} | {verb}: {written} | "
        f"no marker: {no_marker} | already present: {already}",
        flush=True,
    )


if __name__ == "__main__":
    main()
