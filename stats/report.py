"""report.txt generation (status counts, per-suite breakdown, sanity check)."""

import statistics
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from .scanner import find_conflicts


# ── Report ───────────────────────────────────────────────────────────────────


def collect_suite_stats(commits: list[dict]) -> dict:
    """Aggregate per-suite run counts and coverage across all commits.

    A suite "run" is a commit that produced that suite's lcov file. Suite
    outcomes come from the suite's own exit code, so a commit is counted as a
    failure for a suite only when *that* suite failed (not another one).
    """
    stats = defaultdict(
        lambda: {
            "runs": 0,
            "passed": 0,
            "failed": 0,
            "no_exit": 0,
            "with_coverage": 0,
            "lines_pct": [],
        }
    )
    for c in commits:
        for s in c.get("suites", []):
            st = stats[s["name"]]
            st["runs"] += 1
            exit_code = s.get("exitCode")
            if exit_code == 0:
                st["passed"] += 1
            elif exit_code is None:
                st["no_exit"] += 1
            else:
                st["failed"] += 1
            cov = s.get("coverage")
            if cov:
                st["with_coverage"] += 1
                lines_pct = cov.get("lines", {}).get("pct")
                if lines_pct is not None:
                    st["lines_pct"].append(lines_pct)
    return stats


def suite_report_lines(commits: list[dict]) -> list[str]:
    """Build the per-suite breakdown section of report.txt."""
    stats = collect_suite_stats(commits)
    lines = ["── Per-suite breakdown ───────────────────────────────"]
    if not stats:
        lines.append("No test suites found.")
        return lines

    for name in sorted(stats, key=lambda n: (-stats[n]["runs"], n)):
        st = stats[name]
        runs = st["runs"]
        pct_cov = round(st["with_coverage"] / runs * 100, 1) if runs else 0.0
        lines.append(f"{name}")
        lines.append(f"  {runs} runs")
        lines.append(f"  {st['passed']} without test failures")
        lines.append(f"  {st['failed']} with test failures")
        if st["no_exit"]:
            lines.append(f"  {st['no_exit']} without exit code")
        lines.append(f"  {st['with_coverage']} runs with coverage")
        lines.append(f"  {pct_cov}% of runs produced coverage")
        lines_pct = st["lines_pct"]
        if lines_pct:
            lines.append(
                f"  lines coverage: mean {round(statistics.mean(lines_pct), 1)}%, "
                f"median {round(statistics.median(lines_pct), 1)}%, "
                f"min {round(min(lines_pct), 1)}%, max {round(max(lines_pct), 1)}%"
            )
    return lines


def write_report(commits: list[dict], output_dir: Path, proj_dir: Path) -> Path:
    """Write report.txt (status counts + per-suite breakdown + sanity check)."""
    passed = sum(1 for c in commits if c["status"] == "pass")
    failed = sum(1 for c in commits if c["status"] == "fail")
    errors = sum(1 for c in commits if c["status"] == "error")
    not_applicable = sum(1 for c in commits if c["status"] == "not_applicable")

    commits_csv = proj_dir / "commits.csv"
    if commits_csv.is_file():
        with open(commits_csv) as f:
            total_expected = sum(1 for _ in f) - 1  # subtract header
        not_processed = max(0, total_expected - len(commits))
    else:
        not_processed = None

    total = len(commits)
    applicable = passed + failed + errors
    coverage_produced = passed + failed
    pct_cov = round(coverage_produced / applicable * 100, 1) if applicable else 0.0

    report_lines = [
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        f"{total} commits processed",
        f"{passed} without test failures",
        f"{failed} with test failures",
        f"{not_applicable} not applicable",
        f"{errors} hard errors",
        f"{pct_cov}% of applicable commits produced coverage",
    ]
    if not_processed is not None:
        report_lines.append(f"{not_processed} commits not yet processed")

    report = "\n".join(report_lines)
    print(f"\n── Coverage Collection Report ─────────────────────────\n{report}\n────────────────────────────────────────────────────────")

    suites = "\n".join(suite_report_lines(commits))
    print(f"\n{suites}\n────────────────────────────────────────────────────────")

    # Sanity check: commits with multiple conflicting output entry types
    out = proj_dir / "output"
    conflicts = find_conflicts(out)
    sanity_lines = []
    if conflicts:
        sanity_lines.append(f"{len(conflicts)} conflicting entries found:")
        for c in conflicts:
            prefix = c["prefix"]
            types = "+".join(f["type"] for f in c["files"])
            sanity_lines.append(f"  {prefix} ({types}):")
            for f in c["files"]:
                mtime = datetime.fromtimestamp(f["modified"]).strftime("%Y-%m-%d %H:%M:%S")
                sanity_lines.append(f"    {f['type']:15s} {mtime}  {f['path']}")
    else:
        sanity_lines.append(
            "No conflicting entries found (each commit has exactly one entry type)."
        )

    sanity = "\n".join(sanity_lines)
    print(f"\n── Sanity Check ──────────────────────────────────────\n{sanity}\n────────────────────────────────────────────────────────")

    full_report = report + "\n\n" + suites + "\n\n" + sanity
    report_path = output_dir / "report.txt"
    report_path.write_text(full_report + "\n")
    return report_path
