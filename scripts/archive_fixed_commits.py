#!/usr/bin/env python3
"""Archive logs and outputs for commits affected by a fixed issue.

Usage:
    python3 archive_fixed_commits.py <project> <archive_name> [options]

Examples:
    # Dry-run by grepping for a failure message in logs:
    python3 archive_fixed_commits.py uwazi dns_eai_again \
        --grep-log "EAI_AGAIN" \
        --reason "Postinstall binary downloads failed with EAI_AGAIN" \
        --fix "Added resolve-and-pin.sh to install-and-run.sh" \
        --dry-run

    # Move runs for specific commit hashes:
    python3 archive_fixed_commits.py spreed fix_nyc_install \
        --commits 6c5fcf326858 80205d64c66d \
        --reason "Global nyc installation failed in container" \
        --fix "Removed unused global nyc install"

    # Move runs listed in a file:
    python3 archive_fixed_commits.py openneuro overwrite_model_error \
        --commits-file affected_commits.txt \
        --reason "Vitest single-thread mode caused Mongoose OverwriteModelError" \
        --fix "Switched to VITEST_MAX_THREADS=1 thread bounding"
"""

import argparse
import csv
import datetime
import os
import re
import shutil
import sys
from collections import defaultdict

PREFIX_RE = re.compile(r"^(\d{1,13}_[0-9a-fA-F]{40})")


def snake_case(text: str) -> str:
    name = re.sub(r"[^0-9a-zA-Z]+", "_", text).strip("_").lower()
    if not name:
        sys.exit("error: archive_name did not produce a valid snake_case directory name")
    return name


def load_prefixes_from_file(file_path: str) -> set:
    if not os.path.isfile(file_path):
        sys.exit(f"error: commits file not found: {file_path}")
    items = set()
    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            # If line is full prefix or contains hash
            match = PREFIX_RE.match(line)
            if match:
                items.add(match.group(1))
            else:
                # Could be a commit hash alone
                items.add(line.split()[0])
    return items


def scan_matching_logs_by_grep(logs_dir: str, regex_pattern: str, suffix_filter: str = None) -> set:
    if not os.path.isdir(logs_dir):
        return set()
    pattern = re.compile(regex_pattern)
    matched_prefixes = set()

    for entry in sorted(os.listdir(logs_dir)):
        if suffix_filter and not entry.endswith(suffix_filter):
            continue
        if not (entry.endswith(".log") or entry.endswith(".error")):
            continue
        match = PREFIX_RE.match(entry)
        if not match:
            continue
        prefix = match.group(1)
        full_path = os.path.join(logs_dir, entry)
        try:
            with open(full_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
                if pattern.search(content):
                    matched_prefixes.add(prefix)
        except OSError as e:
            print(f"warning: could not read {full_path}: {e}", file=sys.stderr)

    return matched_prefixes


def main():
    parser = argparse.ArgumentParser(
        description="Archive logs and outputs for commits affected by a fixed issue."
    )
    parser.add_argument("project", help="Project name under projects/")
    parser.add_argument(
        "archive_name",
        help="Speaking name for what was fixed (e.g. fix_nyc_install, overwrite_model_error)",
    )
    parser.add_argument(
        "--commits",
        nargs="+",
        help="One or more commit hashes or {timestamp}_{hash} prefixes to archive",
    )
    parser.add_argument(
        "--commits-file",
        help="File containing commit hashes or prefixes to archive (one per line)",
    )
    parser.add_argument(
        "--grep-log",
        help="Regex pattern to search inside projects/<project>/logs/ to identify affected runs",
    )
    parser.add_argument(
        "--grep-suffix",
        choices=[".error", ".log"],
        default=None,
        help="Limit log search to .error or .log files only",
    )
    parser.add_argument(
        "--reason",
        default="",
        help="Description of the issue / cause of failure",
    )
    parser.add_argument(
        "--fix",
        default="",
        help="Description of the fix applied",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions without moving any files",
    )
    parser.add_argument(
        "--allow-existing",
        action="store_true",
        help="Allow moving files into an existing archive subfolder",
    )

    args = parser.parse_args()

    project_dir = os.path.join("projects", args.project)
    if not os.path.isdir(project_dir):
        sys.exit(f"error: project directory not found: {project_dir}")

    logs_dir = os.path.join(project_dir, "logs")
    output_dir = os.path.join(project_dir, "output")
    archive_base = os.path.join(project_dir, "archive")
    name = snake_case(args.archive_name)
    target_archive_dir = os.path.join(archive_base, name)

    if os.path.exists(target_archive_dir) and not args.allow_existing:
        sys.exit(f"error: archive directory already exists: {target_archive_dir} (use --allow-existing to append)")

    # Collect target prefixes / hashes
    target_keys = set()
    if args.commits:
        target_keys.update(args.commits)
    if args.commits_file:
        target_keys.update(load_prefixes_from_file(args.commits_file))
    if args.grep_log:
        matched = scan_matching_logs_by_grep(logs_dir, args.grep_log, args.grep_suffix)
        target_keys.update(matched)

    if not target_keys:
        sys.exit("error: no commits specified. Use --commits, --commits-file, or --grep-log.")

    # Match files in logs/
    logs_to_move = []
    if os.path.isdir(logs_dir):
        for entry in sorted(os.listdir(logs_dir)):
            match = PREFIX_RE.match(entry)
            if not match:
                continue
            prefix = match.group(1)
            parts = prefix.split("_", 1)
            commit_hash = parts[1] if len(parts) == 2 else ""

            # Check if prefix or full hash or short hash in target_keys
            is_matched = False
            if prefix in target_keys or commit_hash in target_keys:
                is_matched = True
            else:
                for key in target_keys:
                    if len(key) >= 7 and commit_hash.startswith(key):
                        is_matched = True
                        break

            if is_matched:
                logs_to_move.append(os.path.join(logs_dir, entry))

    # Match entries in output/
    output_to_move = []
    if os.path.isdir(output_dir):
        for entry in sorted(os.listdir(output_dir)):
            match = PREFIX_RE.match(entry)
            if not match:
                continue
            prefix = match.group(1)
            parts = prefix.split("_", 1)
            commit_hash = parts[1] if len(parts) == 2 else ""

            is_matched = False
            if prefix in target_keys or commit_hash in target_keys:
                is_matched = True
            else:
                for key in target_keys:
                    if len(key) >= 7 and commit_hash.startswith(key):
                        is_matched = True
                        break

            if is_matched:
                output_to_move.append(os.path.join(output_dir, entry))

    if not logs_to_move and not output_to_move:
        print(f"No matching logs or output artifacts found for project '{args.project}'.")
        return

    # Extract all distinct run prefixes being moved
    affected_prefixes = set()
    for path in logs_to_move + output_to_move:
        match = PREFIX_RE.match(os.path.basename(path))
        if match:
            affected_prefixes.add(match.group(1))

    sorted_prefixes = sorted(affected_prefixes)
    dest_logs = os.path.join(target_archive_dir, "logs")
    dest_output = os.path.join(target_archive_dir, "output")

    print(f"=== Commit Archiving Summary ===")
    print(f"Project:              {args.project}")
    print(f"Archive subfolder:    {target_archive_dir}" + (" [DRY RUN]" if args.dry_run else ""))
    print(f"Distinct runs/commits:{len(sorted_prefixes)}")
    print(f"Log files to move:    {len(logs_to_move)}")
    print(f"Output files/dirs:    {len(output_to_move)}")
    if args.reason:
        print(f"Reason:               {args.reason}")
    if args.fix:
        print(f"Fix:                  {args.fix}")

    if args.dry_run:
        print("\n[DRY RUN] Sample of items to move (up to 10):")
        for p in (logs_to_move + output_to_move)[:10]:
            print(f"  {p}")
        if len(logs_to_move + output_to_move) > 10:
            print(f"  ... and {len(logs_to_move + output_to_move) - 10} more.")
        print("\nDry-run complete. Re-run without --dry-run to perform the move.")
        return

    # Create destination directories
    os.makedirs(dest_logs, exist_ok=True)
    os.makedirs(dest_output, exist_ok=True)

    moved_records = []

    # Move logs
    for path in logs_to_move:
        basename = os.path.basename(path)
        dest_file = os.path.join(dest_logs, basename)
        shutil.move(path, dest_file)
        moved_records.append(f"logs: {path} -> {dest_file}")

    # Move outputs
    for path in output_to_move:
        basename = os.path.basename(path)
        dest_file = os.path.join(dest_output, basename)
        shutil.move(path, dest_file)
        moved_records.append(f"output: {path} -> {dest_file}")

    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()
    now_date = datetime.date.today().isoformat()

    # Write moved.txt
    moved_txt_path = os.path.join(target_archive_dir, "moved.txt")
    with open(moved_txt_path, "w", encoding="utf-8") as f:
        f.write(f"# Archive: {name}\n")
        f.write(f"# Project: {args.project}\n")
        f.write(f"# Timestamp: {now_iso}\n")
        if args.reason:
            f.write(f"# Reason: {args.reason}\n")
        if args.fix:
            f.write(f"# Fix: {args.fix}\n")
        f.write(f"# Total runs: {len(sorted_prefixes)}\n")
        f.write(f"# Total logs moved: {len(logs_to_move)}\n")
        f.write(f"# Total output artifacts moved: {len(output_to_move)}\n\n")
        f.write("# Distinct run prefixes:\n")
        for p in sorted_prefixes:
            f.write(f"{p}\n")
        f.write("\n# Detailed moved file paths:\n")
        for record in moved_records:
            f.write(f"{record}\n")

    # Write README.md
    readme_path = os.path.join(target_archive_dir, "README.md")
    timespan_str = ""
    if sorted_prefixes:
        timespan_str = f"{sorted_prefixes[0]} .. {sorted_prefixes[-1]}"

    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(f"# Archived Runs: {name}\n\n")
        f.write(f"- **Project:** `{args.project}`\n")
        f.write(f"- **Archived date:** {now_date}\n")
        f.write(f"- **Reason:** {args.reason or 'Affected by issue prior to fix'}\n")
        f.write(f"- **Fix:** {args.fix or 'See commit history / OVERVIEW.md'}\n")
        f.write(f"- **Total runs archived:** {len(sorted_prefixes)}\n")
        f.write(f"- **Logs moved:** {len(logs_to_move)}\n")
        f.write(f"- **Output items moved:** {len(output_to_move)}\n")
        if timespan_str:
            f.write(f"- **Timespan:** `{timespan_str}`\n")
        f.write("\n## Action taken\n\n")
        f.write(
            "The affected logs and outputs were moved from `logs/` and `output/` into this archive directory.\n"
            "This frees the commits so they can be re-run cleanly by `main.py` / `collect_coverage.py`.\n"
        )

    print("\n[SUCCESS] Archive completed.")
    print(f"Manifest written to: {moved_txt_path}")
    print(f"README written to:   {readme_path}")
    print(f"\nNext steps:")
    print(f"1. Update projects/{args.project}/OVERVIEW.md under '## Environment / setup fixes'.")
    print(f"2. Re-run coverage for affected commits:")
    print(f"   python3 main.py -p {args.project} --mode coverage-only")


if __name__ == "__main__":
    main()
