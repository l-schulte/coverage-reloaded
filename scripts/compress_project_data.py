#!/usr/bin/env python3
"""
scripts/compress_project_data.py

Creates compressed archives of 'output' and 'logs' per project using tar and zstd.
"""

import argparse
import os
import subprocess
import time
from pathlib import Path

def get_dir_size(path: Path) -> int:
    """Recursively calculate directory size in bytes."""
    if not path.exists():
        return 0
    total = 0
    try:
        for entry in os.scandir(path):
            if entry.is_file(follow_symlinks=False):
                total += entry.stat().st_size
            elif entry.is_dir(follow_symlinks=False):
                total += get_dir_size(Path(entry.path))
    except (PermissionError, FileNotFoundError):
        pass
    return total

def format_size(num_bytes: int) -> str:
    """Format bytes into a human-readable string."""
    val = float(num_bytes)
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if val < 1024.0:
            return f"{val:.1f} {unit}"
        val /= 1024.0
    return f"{val:.1f} PB"

def compress_folder(
    source_project_dir: Path,
    targets: list[str],
    out_archive: Path,
    level: int,
    threads: int,
    dry_run: bool = False
) -> tuple[bool, str]:
    """Compress specified subdirectories from source_project_dir into out_archive."""
    existing_targets = [t for t in targets if (source_project_dir / t).exists()]
    if not existing_targets:
        return False, f"None of {targets} exist in {source_project_dir}"

    if dry_run:
        return True, "Dry-run: skipped actual compression."

    out_archive.parent.mkdir(parents=True, exist_ok=True)
    tmp_archive = out_archive.with_suffix(out_archive.suffix + ".tmp")
    if tmp_archive.exists():
        tmp_archive.unlink()

    cmd = [
        "tar",
        "-I", f"zstd -T{threads} -{level}",
        "-cf", str(tmp_archive),
        "-C", str(source_project_dir),
        *existing_targets
    ]

    t0 = time.time()
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    elapsed = time.time() - t0

    if res.returncode != 0:
        if tmp_archive.exists():
            tmp_archive.unlink()
        return False, f"tar failed (code {res.returncode}): {res.stderr.strip()}"

    tmp_archive.rename(out_archive)
    out_size = out_archive.stat().st_size
    return True, f"Done in {elapsed:.1f}s -> {format_size(out_size)}"

def main():
    parser = argparse.ArgumentParser(
        description="Compress 'output' and 'logs' per project with zstd."
    )
    parser.add_argument(
        "--projects-dir",
        type=Path,
        default=Path("projects"),
        help="Path to projects directory (default: projects/)"
    )
    parser.add_argument(
        "--dest-dir",
        type=Path,
        default=Path("compressed_archives"),
        help="Destination directory for archives (default: compressed_archives/)"
    )
    parser.add_argument(
        "--project",
        "-p",
        action="append",
        dest="selected_projects",
        help="Specific project(s) to compress. Can be repeated. Default: all projects."
    )
    parser.add_argument(
        "--level",
        type=int,
        default=9,
        help="zstd compression level (default: 9)"
    )
    parser.add_argument(
        "--threads",
        "-T",
        type=int,
        default=32,
        help="zstd compression threads (default: 32)"
    )
    parser.add_argument(
        "--split",
        action="store_true",
        help="Create separate archives: <project>_output.tar.zst and <project>_logs.tar.zst"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and show sizes without creating archives."
    )

    args = parser.parse_args()

    if not args.projects_dir.is_dir():
        raise SystemExit(f"Error: Projects directory '{args.projects_dir}' does not exist.")

    all_proj_dirs = sorted([d for d in args.projects_dir.iterdir() if d.is_dir()])
    if args.selected_projects:
        proj_dirs = [d for d in all_proj_dirs if d.name in args.selected_projects]
        missing = set(args.selected_projects) - {d.name for d in proj_dirs}
        if missing:
            raise SystemExit(f"Error: Projects not found: {', '.join(sorted(missing))}")
    else:
        proj_dirs = all_proj_dirs

    print("=" * 80)
    print("Project Data Compression (zstd)")
    print(f"  Level:       -{args.level}")
    print(f"  Threads:     {args.threads}")
    print(f"  Layout:      {'Split (output & logs separate)' if args.split else 'Combined'}")
    print(f"  Destination: {args.dest_dir.resolve()}")
    print(f"  Mode:        {'DRY-RUN' if args.dry_run else 'ACTIVE'}")
    print(f"  Projects:    {len(proj_dirs)}")
    print("=" * 80)

    total_orig_bytes = 0
    total_comp_bytes = 0

    for p in proj_dirs:
        pname = p.name
        out_path = p / "output"
        log_path = p / "logs"

        out_sz = get_dir_size(out_path)
        log_sz = get_dir_size(log_path)
        proj_tot = out_sz + log_sz
        total_orig_bytes += proj_tot

        if proj_tot == 0:
            print(f"[{pname}] Skipping (both output/ and logs/ are empty or missing)")
            continue

        print(f"\n[{pname}] Uncompressed: output={format_size(out_sz)}, logs={format_size(log_sz)} (total: {format_size(proj_tot)})")

        tasks = []
        if args.split:
            if out_sz > 0:
                tasks.append((["output"], args.dest_dir / f"{pname}_output.tar.zst"))
            if log_sz > 0:
                tasks.append((["logs"], args.dest_dir / f"{pname}_logs.tar.zst"))
        else:
            targets = []
            if out_sz > 0:
                targets.append("output")
            if log_sz > 0:
                targets.append("logs")
            tasks.append((targets, args.dest_dir / f"{pname}.tar.zst"))

        for targets, arch_path in tasks:
            print(f"  -> Archiving {', '.join(targets)} into {arch_path.name} ... ", end="", flush=True)
            ok, msg = compress_folder(
                p, targets, arch_path, args.level, args.threads, args.dry_run
            )
            print(msg)
            if not ok:
                print(f"     [ERROR] Failed to compress {targets} for {pname}")
                continue

            if not args.dry_run and arch_path.exists():
                arch_sz = arch_path.stat().st_size
                total_comp_bytes += arch_sz

    print("\n" + "=" * 80)
    print("Summary:")
    print(f"  Total uncompressed size: {format_size(total_orig_bytes)}")
    if not args.dry_run and total_comp_bytes > 0:
        ratio = total_orig_bytes / total_comp_bytes
        pct = (1.0 - (total_comp_bytes / total_orig_bytes)) * 100.0
        print(f"  Total compressed size:   {format_size(total_comp_bytes)}")
        print(f"  Space saved:             {pct:.1f}% ({ratio:.1f}x compression ratio)")
    print("=" * 80)

if __name__ == "__main__":
    main()
