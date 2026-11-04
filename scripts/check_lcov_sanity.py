#!/usr/bin/env python3
"""
check_lcov_sanity.py

Sanity-check LCOV files against their Git repository state across the project's
commit history (as listed in commits.csv).

Detects coverage collection flaws using only the Git repository and LCOV files:
  1. Missing file extensions (e.g. TypeScript files present in git but 0 in LCOV).
  2. Missing directories/packages (e.g. backend covered, frontend completely absent).
  3. Artifact leaks (coverage recorded on dist/, build/, bundle files instead of sources).
  4. Ghost files (LCOV SF: records pointing to paths that do not exist in Git).
  5. Longitudinal anomalies (drops in covered-to-source ratio over time).

Usage:
    python3 check_lcov_sanity.py flowfuse
    python3 check_lcov_sanity.py --project openneuro --sample 10
    python3 check_lcov_sanity.py --all --sample 20
    python3 check_lcov_sanity.py flowfuse --only-with-coverage --verbose
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

BASE_DIR = Path(__file__).resolve().parent.parent
PROJECTS_DIR = BASE_DIR / "projects"

SOURCE_EXTENSIONS = {
    ".js", ".jsx", ".ts", ".tsx", ".vue", ".svelte", ".mjs", ".cjs", ".mts", ".cts"
}

# Standard exclusions for non-production code in Git tree
NON_SOURCE_DIR_PATTERNS = [
    r"^test(/|$)", r"^tests(/|$)", r"^__tests__(/|$)", r"^spec(/|$)",
    r"^specs(/|$)", r"^__mocks__(/|$)", r"^cypress(/|$)", r"^e2e(/|$)",
    r"^e2e-tests(/|$)", r"^integration-tests?(/|$)", r"^starters(/|$)",
    r"^deprecated-packages(/|$)", r"^docs(/|$)", r"^doc(/|$)",
    r"^examples(/|$)", r"^fixtures(/|$)", r"^fixture(/|$)",
    r"^scripts(/|$)", r"^config(/|$)", r"^benchmark(/|$)", r"^benchmarks(/|$)",
    r"^schemas(/|$)", r"^declarations(/|$)", r"^assembly(/|$)",
    r"(^|/)\.github(/|$)", r"(^|/)\.husky(/|$)", r"(^|/)node_modules(/|$)",
    r"(^|/)\.yarn(/|$)", r"(^|/)\.vscode(/|$)", r"(^|/)vendor(/|$)",
    r"(^|/)eslint-rules(/|$)", r"(^|/)lint(/|$)",
    # Nested test folders
    r"/[tT]ests?/", r"/__tests__/", r"/e2e/", r"/e2e-tests?/", r"/cypress/", r"/fixtures?/"
]

NON_SOURCE_FILE_PATTERNS = [
    r"\.test\.[^.]+$", r"\.spec\.[^.]+$", r"\.mock\.[^.]+$",
    r"\.config\.[^.]+$", r"^\.[^.]*rc", r"^tsconfig.*\.json$",
    r"^webpack\.", r"^vite\.config\.", r"^vitest\.config\.", r"^babel\.config\.", r"^rollup\.config\."
]

COMPILED_DIR_PREFIXES = (
    "dist/", "build/", ".cache/", "out/", "output/", "bundle/", ".next/", ".nuxt/"
)

RE_NON_SOURCE_DIR = re.compile("|".join(NON_SOURCE_DIR_PATTERNS))
RE_NON_SOURCE_FILE = re.compile("|".join(NON_SOURCE_FILE_PATTERNS))


def is_candidate_source_file(path: str) -> bool:
    """Determine if a git-tracked file is likely source code (not a test/config/fixture)."""
    if path.endswith((".d.ts", ".d.mts", ".d.cts")):
        return False
    _, ext = os.path.splitext(path)
    if ext not in SOURCE_EXTENSIONS:
        return False
    if RE_NON_SOURCE_DIR.search(path):
        return False
    filename = os.path.basename(path)
    if RE_NON_SOURCE_FILE.search(filename):
        return False
    return True


def normalize_lcov_path(path: str) -> str:
    """Normalize SF: path from LCOV to be relative to the repository root."""
    path = path.strip()
    if path.startswith("./"):
        path = path[2:]
    
    # Strip well-known container-mount prefixes
    container_prefixes = [
        "/coverage_reloaded/repo/",
        "/repo/",
        "/workspace/"
    ]
    for pfx in container_prefixes:
        if path.startswith(pfx):
            path = path[len(pfx):]
            break

    # Strip leading slash if any
    return path.lstrip("/")


def get_top_level_subsystem(path: str) -> str:
    """Get the primary directory/package prefix of a file path."""
    parts = path.split("/")
    if len(parts) >= 2 and parts[0] in ("packages", "apps", "services", "modules"):
        return f"{parts[0]}/{parts[1]}"
    return parts[0] if len(parts) > 1 else "."


def parse_commit_lcovs(commit_dir: Path) -> Tuple[Set[str], List[str]]:
    """
    Parse all *.lcov files in a commit output directory.
    Returns: (set of normalized SF paths, list of artifact leak paths).
    """
    lcov_files: Set[str] = set()
    artifact_leaks: List[str] = []

    for lcov_path in commit_dir.glob("*.lcov"):
        try:
            with open(lcov_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith("SF:"):
                        raw_sf = line[3:].strip()
                        norm_sf = normalize_lcov_path(raw_sf)
                        if norm_sf.startswith(COMPILED_DIR_PREFIXES):
                            artifact_leaks.append(norm_sf)
                        else:
                            lcov_files.add(norm_sf)
        except Exception:
            continue

    return lcov_files, artifact_leaks


def query_git_tree(repo_dir: str, commit_hash: str) -> Tuple[Set[str], Set[str]]:
    """
    Query git ls-tree for candidate source files and all tracked files at commit_hash.
    Returns (candidate_source_files, all_tracked_files).
    """
    try:
        raw = subprocess.check_output(
            ["git", "-C", repo_dir, "ls-tree", "-r", "--name-only", commit_hash],
            text=True,
            stderr=subprocess.DEVNULL
        )
        all_tracked = set(line.strip() for line in raw.splitlines() if line.strip())
        candidate_sources = {f for f in all_tracked if is_candidate_source_file(f)}
        return candidate_sources, all_tracked
    except Exception:
        return set(), set()


@dataclass
class CommitSanityResult:
    commit_hash: str
    timestamp: str
    status: str  # OK, CRITICAL_ANOMALY, WARNING, NOT_APPLICABLE, ERROR, NO_OUTPUT, NO_LCOV
    git_src_count: int
    lcov_src_count: int
    matched_count: int
    coverage_ratio: float
    git_ts_count: int
    lcov_ts_count: int
    git_js_count: int
    lcov_js_count: int
    git_vue_count: int
    lcov_vue_count: int
    ghost_count: int
    leak_count: int
    missing_exts: str
    missing_dirs: str
    flags: str


def evaluate_commit(
    commit_hash: str,
    timestamp: str,
    repo_dir: str,
    output_dir: Path
) -> CommitSanityResult:
    """Evaluate a single commit against its LCOV output and Git tree."""
    dir_name = f"{timestamp}_{commit_hash}"
    commit_out_dir = output_dir / dir_name
    na_marker = output_dir / f"{dir_name}.not_applicable"
    err_marker = output_dir / f"{dir_name}.error"

    if na_marker.exists():
        return CommitSanityResult(
            commit_hash=commit_hash, timestamp=timestamp, status="NOT_APPLICABLE",
            git_src_count=0, lcov_src_count=0, matched_count=0, coverage_ratio=0.0,
            git_ts_count=0, lcov_ts_count=0, git_js_count=0, lcov_js_count=0,
            git_vue_count=0, lcov_vue_count=0, ghost_count=0, leak_count=0,
            missing_exts="", missing_dirs="", flags=""
        )

    if err_marker.exists():
        return CommitSanityResult(
            commit_hash=commit_hash, timestamp=timestamp, status="ERROR",
            git_src_count=0, lcov_src_count=0, matched_count=0, coverage_ratio=0.0,
            git_ts_count=0, lcov_ts_count=0, git_js_count=0, lcov_js_count=0,
            git_vue_count=0, lcov_vue_count=0, ghost_count=0, leak_count=0,
            missing_exts="", missing_dirs="", flags=""
        )

    if not commit_out_dir.exists() or not commit_out_dir.is_dir():
        return CommitSanityResult(
            commit_hash=commit_hash, timestamp=timestamp, status="NO_OUTPUT",
            git_src_count=0, lcov_src_count=0, matched_count=0, coverage_ratio=0.0,
            git_ts_count=0, lcov_ts_count=0, git_js_count=0, lcov_js_count=0,
            git_vue_count=0, lcov_vue_count=0, ghost_count=0, leak_count=0,
            missing_exts="", missing_dirs="", flags=""
        )

    # Parse LCOV files
    lcov_files, leaks = parse_commit_lcovs(commit_out_dir)
    if not lcov_files:
        return CommitSanityResult(
            commit_hash=commit_hash, timestamp=timestamp, status="NO_LCOV",
            git_src_count=0, lcov_src_count=0, matched_count=0, coverage_ratio=0.0,
            git_ts_count=0, lcov_ts_count=0, git_js_count=0, lcov_js_count=0,
            git_vue_count=0, lcov_vue_count=0, ghost_count=0, leak_count=len(leaks),
            missing_exts="", missing_dirs="", flags="NO_LCOV_RECORDS"
        )

    # Query Git tree
    git_sources, all_tracked = query_git_tree(repo_dir, commit_hash)

    # Matching & Ghost files
    matched = lcov_files & git_sources
    ghost_files = [f for f in lcov_files if f not in all_tracked]
    
    # Counts by extension
    def count_exts(files: Set[str], exts: Tuple[str, ...]) -> int:
        return sum(1 for f in files if any(f.endswith(e) for e in exts))

    git_ts = count_exts(git_sources, (".ts", ".tsx", ".mts", ".cts"))
    lcov_ts = count_exts(lcov_files, (".ts", ".tsx", ".mts", ".cts"))

    git_js = count_exts(git_sources, (".js", ".jsx", ".mjs", ".cjs"))
    lcov_js = count_exts(lcov_files, (".js", ".jsx", ".mjs", ".cjs"))

    git_vue = count_exts(git_sources, (".vue", ".svelte"))
    lcov_vue = count_exts(lcov_files, (".vue", ".svelte"))

    # Extension breakdown check
    missing_ext_list = []
    minor_missing_ext_list = []
    underrepresented_ext_list = []
    
    total_src = len(git_sources)
    for label, g_cnt, l_cnt in [("ts", git_ts, lcov_ts), ("js", git_js, lcov_js), ("vue", git_vue, lcov_vue)]:
        if g_cnt == 0:
            continue
        share = g_cnt / total_src if total_src else 0.0
        if l_cnt == 0:
            if g_cnt >= 20 or share >= 0.10:
                missing_ext_list.append(f"{label}(git={g_cnt},share={share:.1%},lcov=0)")
            elif g_cnt >= 5:
                minor_missing_ext_list.append(f"{label}(git={g_cnt})")
        elif g_cnt >= 15 and (l_cnt / g_cnt) < 0.15 and share >= 0.10:
            # Check if another major extension has solid coverage (>40%)
            other_ratios = [
                lc / gc for gc, lc in [(git_ts, lcov_ts), (git_js, lcov_js), (git_vue, lcov_vue)]
                if gc >= 10 and (gc, lc) != (g_cnt, l_cnt)
            ]
            if any(r >= 0.40 for r in other_ratios):
                underrepresented_ext_list.append(f"{label}({l_cnt}/{g_cnt}={l_cnt/g_cnt:.1%})")

    # Directory / Subsystem breakdown check
    git_dirs: Dict[str, int] = {}
    for f in git_sources:
        d = get_top_level_subsystem(f)
        git_dirs[d] = git_dirs.get(d, 0) + 1

    lcov_dirs: Dict[str, int] = {}
    for f in lcov_files:
        d = get_top_level_subsystem(f)
        lcov_dirs[d] = lcov_dirs.get(d, 0) + 1

    missing_dir_list = []
    for d, g_cnt in git_dirs.items():
        if g_cnt >= 15 and lcov_dirs.get(d, 0) == 0:
            missing_dir_list.append(f"{d}(git={g_cnt})")

    # Determine status & flags
    flags = []
    if missing_ext_list:
        flags.append("MISSING_EXT:" + ",".join(missing_ext_list))
    if minor_missing_ext_list:
        flags.append("MINOR_UNCOVERED_EXT:" + ",".join(minor_missing_ext_list))
    if underrepresented_ext_list:
        flags.append("UNDERREPRESENTED_EXT:" + ",".join(underrepresented_ext_list))
    if missing_dir_list:
        flags.append("MISSING_DIR:" + ",".join(missing_dir_list))
    if leaks:
        flags.append(f"ARTIFACT_LEAKS({len(leaks)})")
    if len(ghost_files) > max(10, int(0.20 * len(lcov_files))):
        flags.append(f"GHOST_FILES({len(ghost_files)})")

    cov_ratio = len(matched) / len(git_sources) if git_sources else 0.0

    if missing_ext_list or missing_dir_list:
        status = "CRITICAL_ANOMALY"
    elif minor_missing_ext_list or underrepresented_ext_list or leaks or any("GHOST_FILES" in fl for fl in flags):
        status = "WARNING"
    else:
        status = "OK"

    return CommitSanityResult(
        commit_hash=commit_hash,
        timestamp=timestamp,
        status=status,
        git_src_count=len(git_sources),
        lcov_src_count=len(lcov_files),
        matched_count=len(matched),
        coverage_ratio=round(cov_ratio, 4),
        git_ts_count=git_ts,
        lcov_ts_count=lcov_ts,
        git_js_count=git_js,
        lcov_js_count=lcov_js,
        git_vue_count=git_vue,
        lcov_vue_count=lcov_vue,
        ghost_count=len(ghost_files),
        leak_count=len(leaks),
        missing_exts=";".join(missing_ext_list + underrepresented_ext_list),
        missing_dirs=";".join(missing_dir_list),
        flags=" ".join(flags)
    )


def _eval_worker(args: Tuple[str, str, str, Path]) -> CommitSanityResult:
    ch, ts, repo, out_dir = args
    return evaluate_commit(ch, ts, repo, out_dir)


def analyze_project(
    project_name: str,
    sample_rate: int = 1,
    max_commits: Optional[int] = None,
    workers: int = 8,
    output_csv_path: Optional[Path] = None,
    only_with_coverage: bool = False,
    verbose: bool = False
) -> List[CommitSanityResult]:
    """Run sanity check across a project's commits.csv."""
    proj_dir = PROJECTS_DIR / project_name
    commits_csv = proj_dir / "commits.csv"
    repo_dir = proj_dir / "repo"
    out_dir = proj_dir / "output"

    if not commits_csv.exists():
        print(f"Error: {commits_csv} does not exist", file=sys.stderr)
        return []
    if not repo_dir.exists():
        print(f"Error: {repo_dir} does not exist", file=sys.stderr)
        return []

    print(f"\n========================================================")
    print(f"  Sanity-Checking Project: {project_name}")
    print(f"========================================================")

    # Read commits.csv
    commits: List[Tuple[str, str]] = []
    with open(commits_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if sample_rate > 1 and (i % sample_rate != 0):
                continue
            commits.append((row["commit_hash"], row["timestamp"]))
            if max_commits and len(commits) >= max_commits:
                break

    total = len(commits)
    print(f"Loaded {total} commits to inspect (sample_rate={sample_rate}, workers={workers})")

    tasks = [(ch, ts, str(repo_dir), out_dir) for ch, ts in commits]

    t0 = time.time()
    results: List[CommitSanityResult] = []
    
    # Process tasks with progress indicator
    with ProcessPoolExecutor(max_workers=workers) as executor:
        for i, res in enumerate(executor.map(_eval_worker, tasks), 1):
            results.append(res)
            if i % 500 == 0 or i == total:
                elapsed = time.time() - t0
                rate = i / elapsed if elapsed > 0 else 0
                print(f"  Progress: {i}/{total} ({i/total*100:.1f}%) — {rate:.1f} commits/sec", end="\r", flush=True)

    print()
    elapsed = time.time() - t0
    print(f"Completed analysis of {total} commits in {elapsed:.2f}s ({total/elapsed:.1f} commits/sec)")

    # Filter if only_with_coverage
    reported_results = results
    if only_with_coverage:
        reported_results = [r for r in results if r.status in ("OK", "CRITICAL_ANOMALY", "WARNING")]

    # Write output CSV (with graceful fallback for read-only mounts)
    if not output_csv_path:
        output_csv_path = proj_dir / "lcov_sanity_report.csv"

    fieldnames = list(asdict(results[0]).keys()) if results else []
    try:
        with open(output_csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for r in reported_results:
                writer.writerow(asdict(r))
        print(f"Report written to: {output_csv_path}")
    except OSError as e:
        if e.errno == 30:  # Read-only file system
            fallback_path = Path(f"/tmp/lcov_sanity_{project_name}.csv")
            with open(fallback_path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                for r in reported_results:
                    writer.writerow(asdict(r))
            print(f"Warning: {output_csv_path.parent} is read-only. Report written to fallback: {fallback_path}")
        else:
            raise

    # Summary Statistics
    status_counts: Dict[str, int] = {}
    for r in results:
        status_counts[r.status] = status_counts.get(r.status, 0) + 1

    covered_commits = [r for r in results if r.status in ("OK", "CRITICAL_ANOMALY", "WARNING")]
    critical_commits = [r for r in results if r.status == "CRITICAL_ANOMALY"]
    warning_commits = [r for r in results if r.status == "WARNING"]

    print("\n--- Summary Breakdown ---")
    for st, count in sorted(status_counts.items()):
        print(f"  {st:20s}: {count:6d} ({count/total*100:.1f}%)")

    if covered_commits:
        print(f"\nOf {len(covered_commits)} commits with collected coverage:")
        print(f"  OK                    : {len(covered_commits) - len(critical_commits) - len(warning_commits)}")
        print(f"  WARNING               : {len(warning_commits)}")
        print(f"  CRITICAL_ANOMALY      : {len(critical_commits)}")

    if critical_commits:
        print("\n[!] Top Flagged Issues Detected:")
        seen_flags: Dict[str, int] = {}
        for r in critical_commits:
            for fl in r.flags.split():
                seen_flags[fl] = seen_flags.get(fl, 0) + 1
        for fl, count in sorted(seen_flags.items(), key=lambda x: x[1], reverse=True)[:10]:
            print(f"    {fl:50s} ({count} commits affected)")

        first_crit = critical_commits[0]
        last_crit = critical_commits[-1]
        print(f"\n  First affected commit : {first_crit.commit_hash[:10]} (ts: {first_crit.timestamp}) -> {first_crit.flags}")
        print(f"  Last affected commit  : {last_crit.commit_hash[:10]} (ts: {last_crit.timestamp}) -> {last_crit.flags}")

        if verbose:
            print("\n  Sample Critical Commits:")
            for r in critical_commits[:5]:
                print(f"    {r.commit_hash[:10]} | TS: git={r.git_ts_count}, lcov={r.lcov_ts_count} | JS: git={r.git_js_count}, lcov={r.lcov_js_count} | {r.flags}")

    return results


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sanity-check LCOV files against Git repository source files across history."
    )
    parser.add_argument("project", nargs="?", help="Project name (under projects/)")
    parser.add_argument("--project", dest="project_opt", help="Project name")
    parser.add_argument("--all", action="store_true", help="Run sanity check on all projects")
    parser.add_argument("--sample", type=int, default=1, help="Check 1 out of every N commits (default: 1)")
    parser.add_argument("--max-commits", type=int, default=None, help="Stop after N commits")
    parser.add_argument("--workers", type=int, default=8, help="Number of parallel worker processes")
    parser.add_argument("--output-csv", type=str, default=None, help="Custom path for output CSV report")
    parser.add_argument("--only-with-coverage", action="store_true", help="Only write commits with coverage to CSV")
    parser.add_argument("--verbose", action="store_true", help="Print sample flagged commits")

    args = parser.parse_args()

    proj = args.project or args.project_opt
    if args.all:
        projects = [
            p.name for p in sorted(PROJECTS_DIR.iterdir())
            if p.is_dir() and (p / "commits.csv").exists() and (p / "repo").exists()
        ]
        print(f"Running sanity check on all {len(projects)} projects...")
        for p in projects:
            analyze_project(
                p,
                sample_rate=args.sample,
                max_commits=args.max_commits,
                workers=args.workers,
                only_with_coverage=args.only_with_coverage,
                verbose=args.verbose
            )
        return 0

    if not proj:
        parser.print_help()
        return 2

    csv_path = Path(args.output_csv) if args.output_csv else None
    results = analyze_project(
        proj,
        sample_rate=args.sample,
        max_commits=args.max_commits,
        workers=args.workers,
        output_csv_path=csv_path,
        only_with_coverage=args.only_with_coverage,
        verbose=args.verbose
    )

    any_critical = any(r.status == "CRITICAL_ANOMALY" for r in results)
    return 1 if any_critical else 0


if __name__ == "__main__":
    sys.exit(main())
