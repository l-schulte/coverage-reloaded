"""Command-line interface for per-project statistics."""

import argparse
import sys
from pathlib import Path

from tqdm import tqdm

from .csvs import (
    write_commits_detail_csv,
    write_distribution_csv,
    write_monthly_trend_csv,
    write_summary_csv,
)
from .plots import (
    plot_cumulative_progress,
    plot_distribution,
    plot_lines_scatter,
    plot_monthly_trend,
    plot_monthly_trend_per_suite,
    plot_monthly_volume,
    plot_pass_fail_timeline,
    plot_per_suite,
    plot_status_pie,
)
from .report import write_report
from .scanner import scan_output

BASE_DIR = Path(__file__).resolve().parent.parent
PROJECTS_DIR = BASE_DIR / "projects"


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Generate CSV stats and plots for a coverage_reloaded project."
    )
    parser.add_argument(
        "project",
        nargs="?",
        help="Project name (must exist under projects/<name>/)",
    )
    parser.add_argument(
        "--output-dir", help="Output directory (default: projects/<name>/stats_output/)"
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Regenerate report.txt only and delete existing plots (they may be stale).",
    )
    parser.add_argument(
        "--aggregate",
        action="store_true",
        help="Aggregate stats across projects (project arg is ignored; "
        "output goes to ./stats_output/).",
    )
    args = parser.parse_args()

    if args.aggregate:
        output_dir = Path(args.output_dir) if args.output_dir else BASE_DIR / "stats_output"
        output_dir.mkdir(parents=True, exist_ok=True)
        from .aggregate import run_aggregate

        project_names = sorted(
            p.name for p in PROJECTS_DIR.iterdir() if (p / "output").is_dir()
        )
        print(f"Aggregating {len(project_names)} projects ...")
        run_aggregate(project_names, PROJECTS_DIR, output_dir)
        return

    if not args.project:
        parser.error("project name required (or use --aggregate)")

    proj_dir = PROJECTS_DIR / args.project
    if not proj_dir.is_dir():
        print(
            f"Error: project '{args.project}' not found at {proj_dir}", file=sys.stderr
        )
        sys.exit(1)

    output_dir = Path(args.output_dir) if args.output_dir else proj_dir / "stats_output"
    output_dir.mkdir(parents=True, exist_ok=True)

    out = proj_dir / "output"
    if not out.is_dir():
        print(f"Error: no output directory at {out}", file=sys.stderr)
        sys.exit(1)

    print(f"Scanning {out} ...")
    commits = scan_output(out)
    if not commits:
        print("No commits found in output directory.", file=sys.stderr)
        sys.exit(1)

    passed = sum(1 for c in commits if c["status"] == "pass")
    failed = sum(1 for c in commits if c["status"] == "fail")
    errors = sum(1 for c in commits if c["status"] == "error")
    not_applicable = sum(1 for c in commits if c["status"] == "not_applicable")
    print(
        f"Found {len(commits)} commits: {passed} passed, {failed} failed, "
        f"{errors} errors, {not_applicable} not applicable"
    )

    if args.report_only:
        plots = sorted(output_dir.glob("*.png"))
        for p in plots:
            p.unlink()
        print(f"Report-only: deleted {len(plots)} stale plot file(s).")
        write_report(commits, output_dir, proj_dir)
        print(f"Done. Output in {output_dir}")
        return

    print("Generating CSVs...")
    for fn in [
        write_commits_detail_csv,
        write_monthly_trend_csv,
        write_distribution_csv,
        write_summary_csv,
    ]:
        p = fn(commits, output_dir)
        print(f"  {p.name}")

    print("Generating plots...")
    plot_fns = [
        plot_monthly_trend,
        plot_distribution,
        plot_pass_fail_timeline,
        plot_status_pie,
        plot_monthly_volume,
        plot_per_suite,
        plot_monthly_trend_per_suite,
        plot_lines_scatter,
        plot_cumulative_progress,
    ]
    for fn in tqdm(plot_fns, desc="Generating plots", unit="plot"):
        p = fn(commits, output_dir)
        print(f"  {p.name}")

    write_report(commits, output_dir, proj_dir)
    print(f"Done. Output in {output_dir}")
