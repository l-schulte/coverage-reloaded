"""Generate CSV statistics and plots for a coverage_reloaded project.

Usage:
    python stats.py <project_name> [--output-dir <dir>] [--report-only]
    python -m stats <project_name> [--output-dir <dir>] [--report-only]
    python stats.py --aggregate [--output-dir <dir>]

Reads projects/<name>/output/ and produces:
  CSVs:  commits_detail.csv, monthly_trend.csv, distribution.csv, summary.csv
  Plots: monthly_trend.png, coverage_distribution.png, pass_fail_timeline.png,
         status_pie.png, monthly_commit_volume.png, per_suite_coverage.png,
         lines_scatter.png, cumulative_progress.png

The report also contains a per-suite breakdown, so the report-only statistics
are available for each collected test suite (unit, integration, …), not just for
the whole project.

With --report-only, only report.txt is regenerated; existing plots (.png) are
deleted because the underlying data may have changed and stale graphs would be
misleading.

With --aggregate, per-project stats are combined across all projects with
collected output (./stats_output/ unless --output-dir is given):
  status_distribution.png          — stacked run outcomes (full success, soft
                                     failure, not applicable, hard error)
  status_distribution_mainline.png — same, restricted to mainline commits
                                     (one commit per integration event)
  line_coverage_boxplots.png       — per-commit line coverage per project
  monthly_trend_pooled.png         — pooled monthly line coverage, commit-
                                     weighted and per-project unweighted
  coverage_yield.png               — applicable commits producing coverage,
                                     against the 90% criterion
  error_share_heatmap.png          — hard-error share per project and month
  error_share_heatmap_mainline.png — same, restricted to mainline commits

Modules:
  lcov.py      — LCOV parsing and suite aggregation
  scanner.py   — scanning projects/<name>/output/ commit entries
  csvs.py      — per-project CSV generation
  plots.py     — per-project plot generation
  report.py    — report.txt generation (status counts, per-suite, sanity)
  aggregate.py — cross-project aggregated statistics and plots
  cli.py       — command-line interface
"""
