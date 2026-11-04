#!/usr/bin/env python3
"""Archive logs/outputs that no longer match projects/<p>/commits.csv.

Usage:
    python3 archive_commits.py <project> "<description>" [--dry-run]

Every artifact in projects/<p>/logs and projects/<p>/output carries a leading
{timestamp}_{commit_hash} prefix. An artifact matches commits.csv only when
that prefix EXACTLY equals a {timestamp}_{commit_hash} row (both the timestamp
and the commit hash must agree).

Three outcomes:

1. Cleanly moved — artifact prefix not in commits.csv (stale timestamp or
   removed commit). Moved to projects/<p>/archive/<snake>/logs|outputs and
   recorded in moved.txt.

2. Inconsistency detected — commit in commits.csv that is missing entirely
   (no log, no output) or only partially processed (log without output, or
   output without log). Partial artifacts are moved to force a re-run, and
   the commit hash is recorded in inconsistencies.txt.

3. Untouched — artifact prefix matches commits.csv AND the commit has both a
   log and an output (consistent).

Helper files that are not commit artifacts (e.g. .dashboard-index.json) are
never touched.
"""

import argparse
import csv
import os
import re
import shutil
import sys
from collections import defaultdict

PREFIX_RE = re.compile(r"^\d{1,13}_[0-9a-fA-F]{40}")


def snake_case(text):
    name = re.sub(r"[^0-9a-zA-Z]+", "_", text).strip("_").lower()
    if not name:
        sys.exit("error: description did not produce a snake_case folder name")
    return name


def load_commit_prefixes(csv_path):
    prefixes = set()
    with open(csv_path, newline="") as f:
        for row in csv.DictReader(f):
            ts = row.get("timestamp", "")
            commit_hash = row.get("commit_hash", "")
            if ts and commit_hash:
                prefixes.add(f"{ts}_{commit_hash}")
    return prefixes


def scan(directory):
    entries = defaultdict(list)
    skipped = []
    if not os.path.isdir(directory):
        return entries, skipped
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        match = PREFIX_RE.match(name)
        if not match:
            skipped.append(path)
            continue
        entries[match.group(0)].append(path)
    return entries, skipped


def move_to(path, dest_dir, dry_run):
    rel = os.path.join(os.path.basename(dest_dir), os.path.basename(path))
    if not dry_run:
        if os.path.exists(os.path.join(dest_dir, os.path.basename(path))):
            sys.exit(f"error: destination already exists for {path}")
        shutil.move(path, os.path.join(dest_dir, os.path.basename(path)))
    return rel


def write_file(path, lines, dry_run):
    if dry_run:
        return
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Archive logs/outputs that no longer match commits.csv."
    )
    parser.add_argument("project", help="project name under projects/")
    parser.add_argument(
        "description", help="free text, snake_cased into the archive folder name"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print actions without changing anything"
    )
    args = parser.parse_args()

    base = os.path.join("projects", args.project)
    csv_path = os.path.join(base, "commits.csv")
    logs_path = os.path.join(base, "logs")
    output_path = os.path.join(base, "output")

    if not os.path.isfile(csv_path):
        sys.exit(f"error: {csv_path} not found")
    if not (os.path.isdir(logs_path) or os.path.isdir(output_path)):
        sys.exit(
            f"error: neither {logs_path} nor {output_path} exists "
            f"for project {args.project}"
        )

    prefixes = load_commit_prefixes(csv_path)
    log_entries, log_skipped = scan(logs_path)
    out_entries, out_skipped = scan(output_path)

    name = snake_case(args.description)
    archive_dir = os.path.join(base, "archive", name)
    if os.path.exists(archive_dir):
        sys.exit(f"error: {archive_dir} already exists")
    logs_dest = os.path.join(archive_dir, "logs")
    outputs_dest = os.path.join(archive_dir, "outputs")

    moved = []
    inconsistencies = {"missing": [], "log_only": [], "output_only": []}

    if not args.dry_run:
        os.makedirs(logs_dest, exist_ok=True)
        os.makedirs(outputs_dest, exist_ok=True)

    for prefix in sorted(prefixes):
        log_files = log_entries.get(prefix, [])
        out_files = out_entries.get(prefix, [])
        if log_files and out_files:
            continue
        if not log_files and not out_files:
            inconsistencies["missing"].append(prefix)
        elif log_files:
            for path in log_files:
                move_to(path, logs_dest, args.dry_run)
            inconsistencies["log_only"].append(prefix)
        else:
            for path in out_files:
                move_to(path, outputs_dest, args.dry_run)
            inconsistencies["output_only"].append(prefix)

    for prefix, files in sorted(log_entries.items()):
        if prefix not in prefixes:
            for path in files:
                moved.append(move_to(path, logs_dest, args.dry_run))
    for prefix, files in sorted(out_entries.items()):
        if prefix not in prefixes:
            for path in files:
                moved.append(move_to(path, outputs_dest, args.dry_run))

    moved_lines = [
        "# Cleanly moved — logs/outputs whose {timestamp}_{commit_hash} prefix no longer matches",
        f"# any row in commits.csv (stale timestamp or removed commit). Project: {args.project}",
        f"# Moved to projects/{args.project}/archive/{name}/logs and .../outputs.",
    ]
    moved_lines.extend(f"  {rel}" for rel in moved)

    inc_lines = [
        f"# Inconsistency detected — commits in commits.csv for {args.project} "
        "that are not fully processed.",
        "# Re-run these commits to produce fresh logs and outputs.",
        "",
        "# Missing entirely (no log, no output):",
    ]
    inc_lines.extend(f"  {prefix.split('_', 1)[1]}" for prefix in inconsistencies["missing"])
    inc_lines.append("")
    inc_lines.append(f"# Log present but no output (broken run; log moved to {name}/logs):")
    inc_lines.extend(
        f"  {prefix.split('_', 1)[1]}" for prefix in inconsistencies["log_only"]
    )
    inc_lines.append("")
    inc_lines.append(
        f"# Output present but no log (output moved to {name}/outputs):"
    )
    inc_lines.extend(
        f"  {prefix.split('_', 1)[1]}" for prefix in inconsistencies["output_only"]
    )

    if not args.dry_run:
        write_file(os.path.join(archive_dir, "moved.txt"), moved_lines, dry_run=False)
        write_file(
            os.path.join(archive_dir, "inconsistencies.txt"), inc_lines, dry_run=False
        )

    moved_logs = sum(1 for rel in moved if rel.startswith("logs/"))
    moved_outputs = sum(1 for rel in moved if rel.startswith("outputs/"))

    print(f"project:   {args.project}")
    print(f"archive:   {archive_dir}" + (" (dry run, nothing changed)" if args.dry_run else ""))
    print(f"cleanly moved logs:    {moved_logs}")
    print(f"cleanly moved outputs: {moved_outputs}")
    print(f"missing entirely:      {len(inconsistencies['missing'])}")
    print(f"log without output:    {len(inconsistencies['log_only'])}")
    print(f"output without log:    {len(inconsistencies['output_only'])}")
    print(f"helper files skipped:  {len(log_skipped) + len(out_skipped)}")
    print(f"overview files:        moved.txt, inconsistencies.txt")


if __name__ == "__main__":
    main()