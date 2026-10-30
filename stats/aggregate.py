"""Cross-project aggregated statistics: run outcomes, coverage levels, trends."""

import statistics
import sys
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
from tqdm import tqdm

from . import gitmeta
from .plots import _setup_plot, _write_empty_plot
from .scanner import scan_output

STATUS_ORDER = ["pass", "fail", "not_applicable", "error"]
STATUS_LABELS = {
    "pass": "Full success",
    "fail": "Soft failure (test failures)",
    "not_applicable": "Not applicable",
    "error": "Hard error",
}
STATUS_COLORS = {
    "pass": "#2ca02c",
    "fail": "#ff7f0e",
    "not_applicable": "#7f7f7f",
    "error": "#d62728",
}


# ── Collection ───────────────────────────────────────────────────────────────


def _derive(commits: list) -> tuple:
    """Status counts and per-commit line coverage from per-commit records."""
    counts = {s: 0 for s in STATUS_ORDER}
    lines_pct = []
    for c in commits:
        counts[c["status"]] += 1
        if c["lines_pct"] is not None:
            lines_pct.append(c["lines_pct"])
    return counts, lines_pct


def collect_project(project: str, projects_dir: Path) -> dict | None:
    """Scan one project's output/ into per-commit records.

    Each record: {sha, status, month, lines_pct, on_mainline}. The mainline flag
    marks commits on the first-parent chain of the default branch (one state of
    the main branch per integration event); it is None when Git metadata is
    unavailable for the project.
    """
    output_dir = projects_dir / project / "output"
    if not output_dir.is_dir():
        return None
    commits = scan_output(output_dir)
    if not commits:
        return None

    repo_dir = projects_dir / project / "repo"
    try:
        mainline = gitmeta.mainline_shas(repo_dir)
    except (RuntimeError, OSError) as exc:
        print(f"  warning: {project}: mainline detection failed ({exc})")
        mainline = None

    records = []
    for c in commits:
        name = c["hash"]
        sha = name.split("_", 1)[1] if "_" in name else ""
        agg = c.get("aggregate")
        records.append(
            {
                "sha": sha,
                "status": c["status"],
                "month": c.get("month"),
                "lines_pct": agg.get("lines", {}).get("pct") if agg else None,
                "on_mainline": (sha in mainline) if mainline is not None else None,
            }
        )

    counts, lines_pct = _derive(records)
    return {
        "project": project,
        "total": len(records),
        "counts": counts,
        "lines_pct": lines_pct,
        "commits": records,
    }


def collect_all(project_names: list, projects_dir: Path) -> list:
    rows = []
    for name in tqdm(project_names, desc="Scanning projects", unit="project"):
        print(f"Scanning {name} ...")
        row = collect_project(name, projects_dir)
        if row is not None:
            rows.append(row)
    return rows


def subset_rows(rows: list, predicate) -> list:
    """Rows reduced to the commits matching predicate, with stats recomputed."""
    out = []
    for r in rows:
        commits = [c for c in r["commits"] if predicate(c)]
        if not commits:
            continue
        counts, lines_pct = _derive(commits)
        out.append(
            {
                "project": r["project"],
                "total": len(commits),
                "counts": counts,
                "lines_pct": lines_pct,
                "commits": commits,
            }
        )
    return out


def order_rows(rows: list) -> list:
    """Order projects by median line coverage (descending), then by name."""

    def key(r):
        med = statistics.median(r["lines_pct"]) if r["lines_pct"] else -1.0
        return (-med, r["project"])

    return sorted(rows, key=key)


# ── Plot 1: Stacked run-outcome distribution ─────────────────────────────────


def plot_status_distribution(
    rows: list,
    out_dir: Path,
    filename: str = "status_distribution.png",
    title: str = "Run Outcomes per Project (share of processed commits)",
) -> Path:
    """Stacked bar chart: share of full successes, soft failures, not-applicables and errors."""
    if not rows:
        return _write_empty_plot(out_dir, filename, f"{title} (no data)")

    fig, ax = plt.subplots(figsize=(max(10, len(rows) * 1.2), 6))
    _setup_plot(fig, ax, title)

    x = np.arange(len(rows))
    bottoms = np.zeros(len(rows))
    for status in STATUS_ORDER:
        vals = np.array([r["counts"][status] / r["total"] * 100 for r in rows])
        ax.bar(
            x,
            vals,
            0.7,
            bottom=bottoms,
            label=STATUS_LABELS[status],
            color=STATUS_COLORS[status],
            alpha=0.85,
            edgecolor="none",
        )
        for xi, (b, v) in enumerate(zip(bottoms, vals)):
            if v >= 4:
                ax.text(
                    xi,
                    b + v / 2,
                    f"{v:.0f}%",
                    ha="center",
                    va="center",
                    fontsize=8,
                    color="white",
                    fontweight="bold",
                )
        bottoms += vals

    ax.set_xticks(x)
    ax.set_xticklabels(
        [f"{r['project']}\n(n={r['total']})" for r in rows],
        rotation=45,
        ha="right",
        fontsize=8,
    )
    ax.set_ylabel("Share of commits (%)", fontsize=10)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=100))
    ax.legend(fontsize=9, loc="upper left", bbox_to_anchor=(1.01, 1))

    fig.tight_layout()
    path = out_dir / filename
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 2: Per-project line coverage boxplots ───────────────────────────────


def plot_coverage_boxplots(rows: list, out_dir: Path) -> Path:
    """One boxplot per project over per-commit aggregate line coverage."""
    rows = [r for r in rows if r["lines_pct"]]
    if not rows:
        return _write_empty_plot(
            out_dir, "line_coverage_boxplots.png", "Line Coverage per Project (no data)"
        )

    fig, ax = plt.subplots(figsize=(max(8, len(rows) * 1.2), 6))
    _setup_plot(fig, ax, "Line Coverage per Project (per-commit, all suites aggregated)")

    data = [r["lines_pct"] for r in rows]
    bp = ax.boxplot(
        data,
        patch_artist=True,
        widths=0.6,
        showmeans=True,
        meanprops={
            "marker": "D",
            "markersize": 4,
            "markerfacecolor": "#1f77b4",
            "markeredgecolor": "#1f77b4",
        },
    )
    for box in bp["boxes"]:
        box.set(facecolor="#2ca02c", alpha=0.5, edgecolor="#2ca02c")
    for whisker in bp["whiskers"]:
        whisker.set(color="#2ca02c")
    for cap in bp["caps"]:
        cap.set(color="#2ca02c")
    for median in bp["medians"]:
        median.set(color="#1a6b1a", linewidth=1.5)

    ax.set_xticks(range(1, len(rows) + 1))
    ax.set_xticklabels(
        [f"{r['project']}\n(n={len(r['lines_pct'])})" for r in rows],
        rotation=45,
        ha="right",
        fontsize=8,
    )
    ax.set_ylabel("Line coverage (%)", fontsize=10)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=100))

    fig.tight_layout()
    path = out_dir / "line_coverage_boxplots.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 3: Pooled monthly line coverage trend ───────────────────────────────


def plot_monthly_trend_pooled(rows: list, out_dir: Path) -> Path:
    """Pooled monthly line coverage across all projects.

    Commit-weighted: mean over every collected commit in the month.
    Unweighted: mean of the per-project monthly means (each project counts once).
    """
    pooled = defaultdict(list)  # month -> lines_pct of every commit
    per_project_month = defaultdict(lambda: defaultdict(list))  # month -> project -> pcts
    for r in rows:
        for c in r["commits"]:
            if c["month"] and c["lines_pct"] is not None:
                pooled[c["month"]].append(c["lines_pct"])
                per_project_month[c["month"]][r["project"]].append(c["lines_pct"])

    months = sorted(pooled)
    if not months:
        return _write_empty_plot(
            out_dir, "monthly_trend_pooled.png", "Pooled Monthly Coverage (no data)"
        )

    weighted = [statistics.mean(pooled[m]) for m in months]
    unweighted = [
        statistics.mean(
            [statistics.mean(v) for v in per_project_month[m].values()]
        )
        for m in months
    ]

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Pooled Monthly Line Coverage (all projects)")

    x = np.arange(len(months))
    ax.plot(
        x, weighted, color="#2ca02c", linewidth=2, marker="o", markersize=3,
        label="Commit-weighted mean",
    )
    ax.plot(
        x, unweighted, color="#1f77b4", linewidth=1.5, linestyle="--", marker="^",
        markersize=3, label="Per-project mean (unweighted)",
    )

    ax.set_xticks(x)
    ax.set_xticklabels(months, rotation=45, ha="right", fontsize=8)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=100))
    ax.legend(fontsize=9, loc="lower left")

    fig.tight_layout()
    path = out_dir / "monthly_trend_pooled.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 4: Coverage yield per project ───────────────────────────────────────


def plot_coverage_yield(rows: list, out_dir: Path) -> Path:
    """Share of applicable commits that produced valid coverage, with the 90% criterion."""
    yields = []
    for r in rows:
        c = r["counts"]
        applicable = c["pass"] + c["fail"] + c["error"]
        produced = c["pass"] + c["fail"]
        if applicable:
            yields.append((r["project"], produced / applicable * 100, applicable))
    if not yields:
        return _write_empty_plot(
            out_dir, "coverage_yield.png", "Coverage Yield per Project (no data)"
        )

    yields.sort(key=lambda t: (t[1], t[0]))

    fig, ax = plt.subplots(figsize=(10, max(6, len(yields) * 0.45)))
    _setup_plot(fig, ax, "Coverage Yield per Project (applicable commits with coverage)")

    y = np.arange(len(yields))
    colors = ["#2ca02c" if v >= 90 else "#ff7f0e" for _, v, _ in yields]
    ax.barh(y, [v for _, v, _ in yields], 0.7, color=colors, alpha=0.85, edgecolor="none")
    ax.axvline(90, color="#d62728", linestyle="--", linewidth=1, label="90% criterion")

    for yi, (_, v, n) in enumerate(yields):
        ax.text(v + 0.5, yi, f"{v:.1f}% (n={n})", va="center", fontsize=8)

    ax.set_yticks(y)
    ax.set_yticklabels([name for name, _, _ in yields], fontsize=9)
    ax.set_xlim(0, 112)
    ax.set_xlabel("Applicable commits producing coverage (%)", fontsize=10)
    ax.xaxis.set_major_formatter(mticker.PercentFormatter(xmax=100))
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "coverage_yield.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 5: Error-share heatmap ──────────────────────────────────────────────


def plot_error_share_heatmap(
    rows: list,
    out_dir: Path,
    filename: str = "error_share_heatmap.png",
    title: str = "Hard-Error Share per Project and Month",
) -> Path:
    """Project × month heatmap of the share of hard errors."""
    months = sorted({c["month"] for r in rows for c in r["commits"] if c["month"]})
    if not rows or not months:
        return _write_empty_plot(out_dir, filename, f"{title} (no data)")

    month_index = {m: i for i, m in enumerate(months)}
    matrix = np.full((len(rows), len(months)), np.nan)
    for i, r in enumerate(rows):
        totals = defaultdict(int)
        errors = defaultdict(int)
        for c in r["commits"]:
            if not c["month"]:
                continue
            totals[c["month"]] += 1
            if c["status"] == "error":
                errors[c["month"]] += 1
        for m, n in totals.items():
            matrix[i, month_index[m]] = errors[m] / n * 100

    fig, ax = plt.subplots(figsize=(max(10, len(months) * 0.28), max(5, len(rows) * 0.4)))
    _setup_plot(fig, ax, title)

    cmap = plt.cm.Reds.copy()
    cmap.set_bad("#f0f0f0")
    im = ax.imshow(matrix, aspect="auto", cmap=cmap, vmin=0, vmax=100)

    ax.set_xticks(range(len(months)))
    stride = max(1, len(months) // 20)
    ax.set_xticklabels(
        [m if i % stride == 0 else "" for i, m in enumerate(months)],
        rotation=45, ha="right", fontsize=8,
    )
    ax.set_yticks(range(len(rows)))
    ax.set_yticklabels([r["project"] for r in rows], fontsize=9)

    cbar = fig.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("Hard errors (% of commits)", fontsize=9)

    fig.tight_layout()
    path = out_dir / filename
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Entry point ──────────────────────────────────────────────────────────────


def run_aggregate(project_names: list, projects_dir: Path, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = collect_all(project_names, projects_dir)
    if not rows:
        print("No projects with collected output found.", file=sys.stderr)
        sys.exit(1)

    mainline_rows = subset_rows(rows, lambda c: c["on_mainline"])
    mainline_by_project = {r["project"]: r["total"] for r in mainline_rows}

    for r in rows:
        c = r["counts"]
        ml = mainline_by_project.get(r["project"], 0)
        print(
            f"  {r['project']}: {r['total']} commits "
            f"({c['pass']} pass, {c['fail']} fail, {c['not_applicable']} n/a, {c['error']} error); "
            f"{ml} on mainline"
        )

    rows = order_rows(rows)
    mainline_rows = order_rows(mainline_rows)

    print("Generating aggregate plots...")
    for fn, args in [
        (plot_status_distribution, (rows, out_dir)),
        (
            plot_status_distribution,
            (
                mainline_rows,
                out_dir,
                "status_distribution_mainline.png",
                "Run Outcomes on the Mainline (one commit per integration event)",
            ),
        ),
        (plot_coverage_boxplots, (rows, out_dir)),
        (plot_monthly_trend_pooled, (rows, out_dir)),
        (plot_coverage_yield, (rows, out_dir)),
        (plot_error_share_heatmap, (rows, out_dir)),
        (
            plot_error_share_heatmap,
            (
                mainline_rows,
                out_dir,
                "error_share_heatmap_mainline.png",
                "Hard-Error Share on the Mainline (one commit per integration event)",
            ),
        ),
    ]:
        p = fn(*args)
        print(f"  {p.name}")
    print(f"Done. Output in {out_dir}")
