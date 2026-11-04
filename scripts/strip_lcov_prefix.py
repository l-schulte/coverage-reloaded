#!/usr/bin/env python3
"""
strip_lcov_prefix.py

Utility script to strip prefixes (e.g. 'bin/', 'dist/', 'build/') from 'SF:' lines in LCOV files.

Usage:
    python3 strip_lcov_prefix.py --project bhima --prefix bin/ [--dry-run]
    python3 strip_lcov_prefix.py --dir path/to/lcovs --prefix dist/ [--suite integration] [--dry-run]
"""

import argparse
import os
import sys
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path


def process_file(file_path: str, prefix: str, dry_run: bool = False) -> tuple[str, int]:
    """
    Check if file contains 'SF:<prefix>' lines. If so, replace with 'SF:'.
    Returns (file_path, count_replaced).
    """
    try:
        target_token = f"SF:{prefix}"
        with open(file_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        if target_token not in content:
            return file_path, 0

        prefix_len = len(prefix)
        count = 0
        lines = content.splitlines(keepends=True)
        out_lines = []
        for line in lines:
            if line.startswith(target_token):
                out_lines.append("SF:" + line[3 + prefix_len:])
                count += 1
            else:
                out_lines.append(line)

        if count > 0 and not dry_run:
            temp_path = file_path + ".tmp"
            with open(temp_path, "w", encoding="utf-8") as f:
                f.writelines(out_lines)
            os.replace(temp_path, file_path)

        return file_path, count
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
        return file_path, -1


def main():
    parser = argparse.ArgumentParser(
        description="Strip path prefixes from SF: lines in LCOV files across projects/suites."
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--project",
        help="Project name under projects/ (e.g. 'bhima'). Targets projects/<project>/output.",
    )
    group.add_argument(
        "--dir",
        help="Explicit directory containing LCOV files (e.g. 'projects/bhima/archive').",
    )
    parser.add_argument(
        "--prefix",
        required=True,
        help="Prefix to strip from SF: paths (e.g. 'bin/', 'dist/', 'build/').",
    )
    parser.add_argument(
        "--suite",
        help="Optional filter to only process files matching a specific suite name (e.g. 'integration').",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report how many files and lines would be modified without editing files.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=os.cpu_count() or 4,
        help="Number of parallel worker processes (default: CPU count)",
    )
    args = parser.parse_args()

    # Determine target directory
    if args.project:
        target_dir = Path("projects") / args.project / "output"
    elif args.dir:
        target_dir = Path(args.dir)
    else:
        # Default to bhima output if neither is provided
        target_dir = Path("projects/bhima/output")

    if not target_dir.exists():
        print(f"Directory not found: {target_dir}", file=sys.stderr)
        sys.exit(1)

    prefix = args.prefix
    # Ensure trailing slash if needed or keep as user supplied
    print(f"Target directory: {target_dir}")
    print(f"Prefix to strip:  '{prefix}' (SF:{prefix}* -> SF:*)")
    if args.suite:
        print(f"Suite filter:     *{args.suite}*")

    print("Scanning for LCOV files...")
    lcov_files = [
        str(p)
        for p in target_dir.rglob("*")
        if p.is_file()
        and (p.name.endswith(".lcov") or p.name.endswith(".lcov.info"))
        and (not args.suite or args.suite in p.name)
    ]
    total_files = len(lcov_files)
    print(f"Found {total_files} matching LCOV files. Processing with {args.workers} workers...")

    if total_files == 0:
        print("No files to process.")
        return

    modified_files = 0
    total_replaced_lines = 0

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        futures = [
            executor.submit(process_file, f, prefix, args.dry_run)
            for f in lcov_files
        ]
        for idx, fut in enumerate(futures, 1):
            f_path, count = fut.result()
            if count > 0:
                modified_files += 1
                total_replaced_lines += count
            if idx % 2000 == 0 or idx == total_files:
                print(f"Progress: {idx}/{total_files} files scanned...")

    action_word = "Would modify" if args.dry_run else "Modified"
    print("\nDone:")
    print(f"  {action_word} {modified_files} files")
    print(f"  Total 'SF:{prefix}' lines replaced: {total_replaced_lines}")


if __name__ == "__main__":
    main()
