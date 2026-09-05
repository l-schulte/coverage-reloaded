#!/usr/bin/env python3
"""Generate CSV statistics and plots for a coverage_reloaded project.

Usage:
    python stats.py <project_name> [--output-dir <dir>]

Reads projects/<name>/output/ and produces:
  CSVs:  commits_detail.csv, monthly_trend.csv, distribution.csv, summary.csv
  Plots: monthly_trend.png, coverage_distribution.png, pass_fail_timeline.png,
         status_pie.png, monthly_commit_volume.png, per_suite_coverage.png,
         lines_scatter.png, cumulative_progress.png
"""

import argparse
import statistics
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd
from tqdm import tqdm

BASE_DIR = Path(__file__).resolve().parent
PROJECTS_DIR = BASE_DIR / "projects"


# ── LCOV parser ──────────────────────────────────────────────────────────────


def parse_lcov(text: str) -> dict:
    lines = lines_hit = 0
    functions = functions_hit = 0
    branches = branches_hit = 0

    for line in text.splitlines():
        if line.startswith("DA:"):
            parts = line.split(",")
            if len(parts) == 2:
                lines += 1
                try:
                    if int(parts[1]) > 0:
                        lines_hit += 1
                except ValueError:
                    pass
        elif line.startswith("FNF:"):
            try:
                functions += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("FNH:"):
            try:
                functions_hit += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("BRF:"):
            try:
                branches += int(line.split(":")[1])
            except ValueError:
                pass
        elif line.startswith("BRH:"):
            try:
                branches_hit += int(line.split(":")[1])
            except ValueError:
                pass

    def pct(hit, total):
        return round(hit / total * 100, 1) if total > 0 else None

    return {
        "lines": {"hit": lines_hit, "total": lines, "pct": pct(lines_hit, lines)},
        "functions": {
            "hit": functions_hit,
            "total": functions,
            "pct": pct(functions_hit, functions),
        },
        "branches": {
            "hit": branches_hit,
            "total": branches,
            "pct": pct(branches_hit, branches),
        },
    }


def aggregate_suites(suites: list) -> dict | None:
    lh = lt = fh = ft = bh = bt = 0
    for s in suites:
        cov = s.get("coverage")
        if not cov:
            continue
        lh += cov["lines"]["hit"]
        lt += cov["lines"]["total"]
        fh += cov["functions"]["hit"]
        ft += cov["functions"]["total"]
        bh += cov["branches"]["hit"]
        bt += cov["branches"]["total"]
    if lt == 0 and ft == 0 and bt == 0:
        return None
    pct = lambda h, t: round(h / t * 100, 1) if t > 0 else None
    return {
        "lines": {"hit": lh, "total": lt, "pct": pct(lh, lt)},
        "functions": {"hit": fh, "total": ft, "pct": pct(fh, ft)},
        "branches": {"hit": bh, "total": bt, "pct": pct(bh, bt)},
    }


def ts_to_date(ts: str) -> str:
    try:
        n = int(ts)
        d = datetime.fromtimestamp(n if n < 1e12 else n / 1000)
        return d.strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return ts


def ts_to_month(ts: str) -> str | None:
    try:
        n = int(ts)
        d = datetime.fromtimestamp(n if n < 1e12 else n / 1000)
        return d.strftime("%Y-%m")
    except (ValueError, OSError):
        return None


# ── Output directory scanner ─────────────────────────────────────────────────


def _process_entry(entry: Path, dir_prefixes: set) -> dict | None:
    if entry.is_dir():
        suites = []
        for f in sorted(entry.iterdir()):
            if f.suffix == ".lcov":
                suite_name = f.stem
                exit_code_file = entry / f"{suite_name}.exit_code"
                exit_code = None
                if exit_code_file.is_file():
                    try:
                        exit_code = int(exit_code_file.read_text().strip())
                    except ValueError:
                        pass
                coverage = None
                try:
                    coverage = parse_lcov(f.read_text())
                except Exception:
                    pass
                suites.append(
                    {"name": suite_name, "exitCode": exit_code, "coverage": coverage}
                )

        any_fail = any(s["exitCode"] is not None and s["exitCode"] != 0 for s in suites)
        status = "fail" if any_fail else "pass"
        ts_hash = entry.name
        ts_str = ts_hash.split("_")[0]

        return {
            "prefix": ts_hash,
            "hash": ts_hash,
            "date": ts_to_date(ts_str),
            "month": ts_to_month(ts_str),
            "timestamp": int(ts_str) if ts_str.isdigit() else 0,
            "status": status,
            "suites": suites,
            "aggregate": aggregate_suites(suites),
        }
    elif entry.suffix == ".error":
        hash_val = entry.stem
        if hash_val in dir_prefixes:
            return None
        ts_str = hash_val.split("_")[0]
        return {
            "prefix": hash_val,
            "hash": hash_val,
            "date": ts_to_date(ts_str),
            "month": ts_to_month(ts_str),
            "timestamp": int(ts_str) if ts_str.isdigit() else 0,
            "status": "error",
            "suites": [],
            "aggregate": None,
        }
    return None


def scan_output(output_dir: Path) -> list[dict]:
    if not output_dir.is_dir():
        return []

    entries = list(output_dir.iterdir())
    dir_prefixes = {e.name for e in entries if e.is_dir()}
    sorted_entries = sorted(entries, key=lambda p: p.name, reverse=True)

    commits = []
    with ThreadPoolExecutor(max_workers=15) as pool:
        futures = {
            pool.submit(_process_entry, e, dir_prefixes): e for e in sorted_entries
        }
        for future in tqdm(
            as_completed(futures),
            total=len(futures),
            desc="Scanning output",
            unit="entry",
        ):
            result = future.result()
            if result is not None:
                commits.append(result)

    commits.sort(key=lambda c: c["prefix"], reverse=True)
    return commits


# ── CSV generation ───────────────────────────────────────────────────────────


def write_commits_detail_csv(commits: list[dict], out_dir: Path) -> Path:
    rows = []
    for c in commits:
        if c["status"] == "error" or not c["suites"]:
            rows.append(
                {
                    "timestamp": c["timestamp"],
                    "date": c["date"],
                    "hash": c["hash"],
                    "status": c["status"],
                    "suite": "",
                    "exit_code": "",
                    "lines_pct": "",
                    "lines_hit": "",
                    "lines_total": "",
                    "functions_pct": "",
                    "functions_hit": "",
                    "functions_total": "",
                    "branches_pct": "",
                    "branches_hit": "",
                    "branches_total": "",
                }
            )
        else:
            for s in c["suites"]:
                cov = s.get("coverage") or {}
                lp = cov.get("lines", {})
                fp = cov.get("functions", {})
                bp = cov.get("branches", {})
                rows.append(
                    {
                        "timestamp": c["timestamp"],
                        "date": c["date"],
                        "hash": c["hash"],
                        "status": c["status"],
                        "suite": s["name"],
                        "exit_code": s["exitCode"] if s["exitCode"] is not None else "",
                        "lines_pct": lp.get("pct", ""),
                        "lines_hit": lp.get("hit", ""),
                        "lines_total": lp.get("total", ""),
                        "functions_pct": fp.get("pct", ""),
                        "functions_hit": fp.get("hit", ""),
                        "functions_total": fp.get("total", ""),
                        "branches_pct": bp.get("pct", ""),
                        "branches_hit": bp.get("hit", ""),
                        "branches_total": bp.get("total", ""),
                    }
                )
    df = pd.DataFrame(rows)
    path = out_dir / "commits_detail.csv"
    df.to_csv(path, index=False)
    return path


def write_monthly_trend_csv(commits: list[dict], out_dir: Path) -> Path:
    monthly_lines = defaultdict(list)
    monthly_functions = defaultdict(list)
    monthly_branches = defaultdict(list)
    monthly_status = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0})

    for c in commits:
        month = c.get("month")
        if not month:
            continue
        agg = c.get("aggregate")
        if agg:
            lp = agg.get("lines", {}).get("pct")
            fp = agg.get("functions", {}).get("pct")
            bp = agg.get("branches", {}).get("pct")
            if lp is not None:
                monthly_lines[month].append(lp)
            if fp is not None:
                monthly_functions[month].append(fp)
            if bp is not None:
                monthly_branches[month].append(bp)
        monthly_status[month][c["status"]] += 1

    def _stats(values):
        if not values:
            return {
                "mean": "",
                "median": "",
                "stdev": "",
                "min": "",
                "max": "",
                "count": 0,
            }
        return {
            "mean": round(statistics.mean(values), 1),
            "median": round(statistics.median(values), 1),
            "stdev": round(statistics.stdev(values), 1) if len(values) > 1 else 0,
            "min": round(min(values), 1),
            "max": round(max(values), 1),
            "count": len(values),
        }

    rows = []
    for month in sorted(
        set(
            list(monthly_lines.keys())
            + list(monthly_functions.keys())
            + list(monthly_branches.keys())
        )
    ):
        ls = _stats(monthly_lines.get(month, []))
        fs = _stats(monthly_functions.get(month, []))
        bs = _stats(monthly_branches.get(month, []))
        st = monthly_status.get(month, {})
        total = st.get("pass", 0) + st.get("fail", 0) + st.get("error", 0)
        rows.append(
            {
                "month": month,
                "total_commits": total,
                "passed": st.get("pass", 0),
                "failed": st.get("fail", 0),
                "errors": st.get("error", 0),
                "lines_mean": ls["mean"],
                "lines_median": ls["median"],
                "lines_stdev": ls["stdev"],
                "lines_min": ls["min"],
                "lines_max": ls["max"],
                "lines_count": ls["count"],
                "functions_mean": fs["mean"],
                "branches_mean": bs["mean"],
            }
        )
    df = pd.DataFrame(rows)
    path = out_dir / "monthly_trend.csv"
    df.to_csv(path, index=False)
    return path


def write_distribution_csv(commits: list[dict], out_dir: Path) -> Path:
    dist_buckets = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0})
    for c in commits:
        agg = c.get("aggregate")
        if not agg:
            continue
        lp = agg.get("lines", {}).get("pct")
        if lp is None:
            continue
        bucket = int(lp // 10) * 10
        if 0 <= bucket <= 100:
            dist_buckets[bucket][c["status"]] += 1

    rows = []
    for bucket in range(0, 101, 10):
        b = dist_buckets.get(bucket, {"pass": 0, "fail": 0, "error": 0})
        total = b["pass"] + b["fail"] + b["error"]
        rows.append(
            {
                "range": f"{bucket}-{bucket + 9}%",
                "low": bucket,
                "high": bucket + 9,
                "pass": b["pass"],
                "fail": b["fail"],
                "error": b["error"],
                "total": total,
            }
        )
    df = pd.DataFrame(rows)
    path = out_dir / "distribution.csv"
    df.to_csv(path, index=False)
    return path


def write_summary_csv(commits: list[dict], out_dir: Path) -> Path:
    passed = sum(1 for c in commits if c["status"] == "pass")
    failed = sum(1 for c in commits if c["status"] == "fail")
    errors = sum(1 for c in commits if c["status"] == "error")

    all_lines = []
    all_functions = []
    all_branches = []
    for c in commits:
        agg = c.get("aggregate")
        if not agg:
            continue
        for metric, store in [
            ("lines", all_lines),
            ("functions", all_functions),
            ("branches", all_branches),
        ]:
            v = agg.get(metric, {}).get("pct")
            if v is not None:
                store.append(v)

    def _row(values):
        if not values:
            return {"mean": "", "median": "", "stdev": "", "min": "", "max": ""}
        return {
            "mean": round(statistics.mean(values), 1),
            "median": round(statistics.median(values), 1),
            "stdev": round(statistics.stdev(values), 1) if len(values) > 1 else 0,
            "min": round(min(values), 1),
            "max": round(max(values), 1),
        }

    ls = _row(all_lines)
    fs = _row(all_functions)
    bs = _row(all_branches)
    row = {
        "total_commits": len(commits),
        "passed": passed,
        "failed": failed,
        "errors": errors,
        "lines_mean": ls["mean"],
        "lines_median": ls["median"],
        "lines_stdev": ls["stdev"],
        "lines_min": ls["min"],
        "lines_max": ls["max"],
        "functions_mean": fs["mean"],
        "branches_mean": bs["mean"],
    }
    df = pd.DataFrame([row])
    path = out_dir / "summary.csv"
    df.to_csv(path, index=False)
    return path


# ── Plot helpers ─────────────────────────────────────────────────────────────


def _setup_plot(fig, ax, title: str):
    ax.set_title(title, fontsize=12, fontweight="bold", pad=10)
    ax.tick_params(labelsize=9)
    ax.grid(True, alpha=0.3, linewidth=0.5)


# ── Plot 1: Monthly coverage trend ──────────────────────────────────────────


def plot_monthly_trend(commits: list[dict], out_dir: Path) -> Path:
    monthly_data = defaultdict(lambda: {"lines": [], "functions": [], "branches": []})
    for c in commits:
        month = c.get("month")
        agg = c.get("aggregate")
        if not month or not agg:
            continue
        for metric in ("lines", "functions", "branches"):
            v = agg.get(metric, {}).get("pct")
            if v is not None:
                monthly_data[month][metric].append(v)

    months = sorted(monthly_data.keys())
    if not months:
        return _write_empty_plot(
            out_dir, "monthly_trend.png", "Monthly Coverage Trend (no data)"
        )

    lines_mean = [
        statistics.mean(monthly_data[m]["lines"]) if monthly_data[m]["lines"] else None
        for m in months
    ]
    lines_upper = []
    lines_lower = []
    for m in months:
        vals = monthly_data[m]["lines"]
        if len(vals) > 1:
            mean = statistics.mean(vals)
            sd = statistics.stdev(vals)
            lines_upper.append(mean + sd)
            lines_lower.append(max(0, mean - sd))
        elif vals:
            lines_upper.append(vals[0])
            lines_lower.append(vals[0])
        else:
            lines_upper.append(None)
            lines_lower.append(None)

    func_mean = [
        (
            statistics.mean(monthly_data[m]["functions"])
            if monthly_data[m]["functions"]
            else None
        )
        for m in months
    ]
    bran_mean = [
        (
            statistics.mean(monthly_data[m]["branches"])
            if monthly_data[m]["branches"]
            else None
        )
        for m in months
    ]

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Monthly Coverage Trend (mean ± 1σ)")

    x = np.arange(len(months))
    lm = np.array([v if v is not None else np.nan for v in lines_mean])
    lu = np.array([v if v is not None else np.nan for v in lines_upper])
    ll = np.array([v if v is not None else np.nan for v in lines_lower])
    fm = np.array([v if v is not None else np.nan for v in func_mean])
    bm = np.array([v if v is not None else np.nan for v in bran_mean])

    ax.fill_between(x, ll, lu, color="#2ca02c", alpha=0.1, label="_nolegend_")
    ax.plot(
        x,
        lm,
        color="#2ca02c",
        linewidth=2,
        label="Lines % (mean)",
        marker="o",
        markersize=3,
    )
    ax.plot(
        x, lu, color="#2ca02c", linewidth=0.7, alpha=0.4, linestyle="--", label="+1σ"
    )
    ax.plot(
        x, ll, color="#2ca02c", linewidth=0.7, alpha=0.4, linestyle="--", label="-1σ"
    )
    ax.plot(
        x,
        fm,
        color="#1f77b4",
        linewidth=1.5,
        linestyle="--",
        label="Functions %",
        marker="^",
        markersize=3,
    )
    ax.plot(
        x,
        bm,
        color="#ff7f0e",
        linewidth=1.5,
        linestyle="--",
        label="Branches %",
        marker="s",
        markersize=3,
    )

    ax.set_xticks(x)
    ax.set_xticklabels(months, rotation=45, ha="right", fontsize=8)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter())
    ax.legend(loc="lower left", fontsize=9)

    fig.tight_layout()
    path = out_dir / "monthly_trend.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 2: Coverage distribution ───────────────────────────────────────────


def plot_distribution(commits: list[dict], out_dir: Path) -> Path:
    dist = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0})
    for c in commits:
        agg = c.get("aggregate")
        lp = agg.get("lines", {}).get("pct") if agg else None
        if lp is None:
            continue
        bucket = int(lp // 10) * 10
        if 0 <= bucket <= 100:
            dist[bucket][c["status"]] += 1

    buckets = list(range(0, 101, 10))
    labels = [f"{b}-{b+9}%" for b in buckets]
    pass_vals = [dist[b]["pass"] for b in buckets]
    fail_vals = [dist[b]["fail"] for b in buckets]
    error_vals = [dist[b]["error"] for b in buckets]

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Coverage Distribution (all commits)")

    x = np.arange(len(buckets))
    w = 0.7
    ax.bar(
        x, pass_vals, w, label="Passed", color="#2ca02c", alpha=0.7, edgecolor="none"
    )
    ax.bar(
        x,
        fail_vals,
        w,
        bottom=pass_vals,
        label="Failed tests",
        color="#ff7f0e",
        alpha=0.7,
        edgecolor="none",
    )
    bottom2 = [p + f for p, f in zip(pass_vals, fail_vals)]
    ax.bar(
        x,
        error_vals,
        w,
        bottom=bottom2,
        label="Error",
        color="#d62728",
        alpha=0.5,
        edgecolor="none",
    )

    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.set_ylabel("Commits", fontsize=10)
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "coverage_distribution.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 3: Pass/fail timeline ──────────────────────────────────────────────


def plot_pass_fail_timeline(commits: list[dict], out_dir: Path) -> Path:
    monthly = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0})
    for c in commits:
        month = c.get("month")
        if month:
            monthly[month][c["status"]] += 1

    months = sorted(monthly.keys())
    if not months:
        return _write_empty_plot(
            out_dir, "pass_fail_timeline.png", "Pass/Fail Timeline (no data)"
        )

    pass_vals = [monthly[m]["pass"] for m in months]
    fail_vals = [monthly[m]["fail"] for m in months]
    error_vals = [monthly[m]["error"] for m in months]

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Monthly Pass / Fail / Error")

    x = np.arange(len(months))
    ax.bar(x, pass_vals, 0.7, label="Passed", color="#2ca02c", alpha=0.7)
    ax.bar(
        x,
        fail_vals,
        0.7,
        bottom=pass_vals,
        label="Failed tests",
        color="#ff7f0e",
        alpha=0.7,
    )
    bottom2 = [p + f for p, f in zip(pass_vals, fail_vals)]
    ax.bar(
        x, error_vals, 0.7, bottom=bottom2, label="Error", color="#d62728", alpha=0.5
    )

    ax.set_xticks(x)
    ax.set_xticklabels(months, rotation=45, ha="right", fontsize=8)
    ax.set_ylabel("Commits", fontsize=10)
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "pass_fail_timeline.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 4: Status pie ──────────────────────────────────────────────────────


def plot_status_pie(commits: list[dict], out_dir: Path) -> Path:
    passed = sum(1 for c in commits if c["status"] == "pass")
    failed = sum(1 for c in commits if c["status"] == "fail")
    errors = sum(1 for c in commits if c["status"] == "error")
    total = passed + failed + errors

    fig, ax = plt.subplots(figsize=(6, 6))

    if total == 0:
        ax.text(0.5, 0.5, "No data", ha="center", va="center", fontsize=14)
        ax.set_axis_off()
    else:
        labels = []
        sizes = []
        colors = []
        if passed:
            labels.append(f"Passed ({passed})")
            sizes.append(passed)
            colors.append("#2ca02c")
        if failed:
            labels.append(f"Failed tests ({failed})")
            sizes.append(failed)
            colors.append("#ff7f0e")
        if errors:
            labels.append(f"Error ({errors})")
            sizes.append(errors)
            colors.append("#d62728")

        wedges, texts, autotexts = ax.pie(
            sizes,
            labels=labels,
            colors=colors,
            autopct="%1.1f%%",
            startangle=90,
            textprops={"fontsize": 11},
            pctdistance=0.75,
            wedgeprops={"linewidth": 2},
        )
        for t in autotexts:
            t.set_fontsize(10)

    ax.set_title("Commit Status Breakdown", fontsize=12, fontweight="bold", pad=15)

    fig.tight_layout()
    path = out_dir / "status_pie.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 5: Monthly commit volume ───────────────────────────────────────────


def plot_monthly_volume(commits: list[dict], out_dir: Path) -> Path:
    monthly = defaultdict(lambda: {"pass": 0, "fail": 0, "error": 0})
    for c in commits:
        month = c.get("month")
        if month:
            monthly[month][c["status"]] += 1

    months = sorted(monthly.keys())
    if not months:
        return _write_empty_plot(
            out_dir, "monthly_commit_volume.png", "Monthly Commit Volume (no data)"
        )

    pass_vals = [monthly[m]["pass"] for m in months]
    fail_vals = [monthly[m]["fail"] for m in months]
    error_vals = [monthly[m]["error"] for m in months]
    totals = [p + f + e for p, f, e in zip(pass_vals, fail_vals, error_vals)]

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Monthly Commit Volume")

    x = np.arange(len(months))
    ax.bar(x, pass_vals, 0.7, label="Passed", color="#2ca02c", alpha=0.7)
    ax.bar(
        x,
        fail_vals,
        0.7,
        bottom=pass_vals,
        label="Failed tests",
        color="#ff7f0e",
        alpha=0.7,
    )
    bottom2 = [p + f for p, f in zip(pass_vals, fail_vals)]
    ax.bar(
        x, error_vals, 0.7, bottom=bottom2, label="Error", color="#d62728", alpha=0.5
    )

    for i, t in enumerate(totals):
        if t > 0:
            ax.text(i, t + 0.5, str(t), ha="center", va="bottom", fontsize=8)

    ax.set_xticks(x)
    ax.set_xticklabels(months, rotation=45, ha="right", fontsize=8)
    ax.set_ylabel("Commits", fontsize=10)
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "monthly_commit_volume.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 6: Per-suite coverage ──────────────────────────────────────────────


def plot_per_suite(commits: list[dict], out_dir: Path) -> Path:
    suite_metrics = defaultdict(lambda: {"lines": [], "functions": [], "branches": []})
    for c in commits:
        for s in c.get("suites", []):
            cov = s.get("coverage")
            if not cov:
                continue
            for metric in ("lines", "functions", "branches"):
                v = cov.get(metric, {}).get("pct")
                if v is not None:
                    suite_metrics[s["name"]][metric].append(v)

    if not suite_metrics:
        return _write_empty_plot(
            out_dir, "per_suite_coverage.png", "Per-Suite Coverage (no data)"
        )

    suite_names = sorted(suite_metrics.keys())
    short_names = []
    for sn in suite_names:
        parts = sn.replace("\\", "/").split("/")
        short_names.append(parts[-1] if len(parts) > 1 else sn)

    fig, ax = plt.subplots(figsize=(max(8, len(suite_names) * 1.5), 5))
    _setup_plot(fig, ax, "Coverage by Test Suite")

    x = np.arange(len(suite_names))
    w = 0.25
    lines_vals = [
        statistics.mean(suite_metrics[s]["lines"]) if suite_metrics[s]["lines"] else 0
        for s in suite_names
    ]
    func_vals = [
        (
            statistics.mean(suite_metrics[s]["functions"])
            if suite_metrics[s]["functions"]
            else 0
        )
        for s in suite_names
    ]
    bran_vals = [
        (
            statistics.mean(suite_metrics[s]["branches"])
            if suite_metrics[s]["branches"]
            else 0
        )
        for s in suite_names
    ]

    ax.bar(x - w, lines_vals, w, label="Lines %", color="#2ca02c", alpha=0.8)
    ax.bar(x, func_vals, w, label="Functions %", color="#1f77b4", alpha=0.8)
    ax.bar(x + w, bran_vals, w, label="Branches %", color="#ff7f0e", alpha=0.8)

    ax.set_xticks(x)
    ax.set_xticklabels(short_names, rotation=30, ha="right", fontsize=9)
    ax.set_ylim(0, 100)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter())
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "per_suite_coverage.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 7: Monthly trend per suite ─────────────────────────────────────────


def plot_monthly_trend_per_suite(commits: list[dict], out_dir: Path) -> Path:
    suite_monthly = defaultdict(
        lambda: defaultdict(lambda: {"lines_pct": [], "lines_total": []})
    )
    for c in commits:
        month = c.get("month")
        if not month:
            continue
        for s in c.get("suites", []):
            cov = s.get("coverage")
            if not cov:
                continue
            lp = cov.get("lines", {})
            pct = lp.get("pct")
            total = lp.get("total")
            if pct is not None:
                suite_monthly[s["name"]][month]["lines_pct"].append(pct)
            if total is not None:
                suite_monthly[s["name"]][month]["lines_total"].append(total)

    if not suite_monthly:
        return _write_empty_plot(
            out_dir, "monthly_trend_per_suite.png", "Monthly Trend per Suite (no data)"
        )

    suite_names = sorted(suite_monthly.keys())
    all_months = sorted({m for sm in suite_monthly.values() for m in sm})
    if not all_months:
        return _write_empty_plot(
            out_dir, "monthly_trend_per_suite.png", "Monthly Trend per Suite (no data)"
        )

    n_suites = len(suite_names)
    fig, axes = plt.subplots(
        n_suites, 2, figsize=(16, 4 * n_suites), gridspec_kw={"width_ratios": [3, 1]}
    )
    if n_suites == 1:
        axes = [axes]

    colors_pct = plt.cm.Set2(np.linspace(0, 1, n_suites))

    for i, sn in enumerate(suite_names):
        short_name = sn.replace("\\", "/").split("/")[-1]
        monthly_data = suite_monthly[sn]

        x = np.arange(len(all_months))
        pct_vals = []
        count_vals = []
        for m in all_months:
            d = monthly_data.get(m, {})
            p = d.get("lines_pct", [])
            t = d.get("lines_total", [])
            pct_vals.append(statistics.mean(p) if p else None)
            count_vals.append(statistics.mean(t) if t else None)

        pct_arr = np.array([v if v is not None else np.nan for v in pct_vals])
        count_arr = np.array([v if v is not None else np.nan for v in count_vals])

        ax_pct = axes[i][0]
        ax_cnt = axes[i][1]

        _setup_plot(fig, ax_pct, "")
        _setup_plot(fig, ax_cnt, "")

        ax_pct.plot(
            x,
            pct_arr,
            color=colors_pct[i],
            linewidth=1.5,
            marker="o",
            markersize=2,
            label=short_name,
        )
        ax_pct.fill_between(x, pct_arr, alpha=0.1, color=colors_pct[i])
        ax_pct.set_ylim(0, 100)
        ax_pct.yaxis.set_major_formatter(mticker.PercentFormatter())
        ax_pct.set_ylabel("Lines %", fontsize=9)
        ax_pct.set_xticks(x)
        ax_pct.set_xticklabels(all_months, rotation=45, ha="right", fontsize=7)
        if i == 0:
            ax_pct.set_title("Line Coverage %", fontsize=11, fontweight="bold")
        ax_pct.legend(fontsize=8, loc="upper left")

        ax_cnt.bar(x, count_arr, color=colors_pct[i], alpha=0.6, width=0.7)
        ax_cnt.set_ylabel("Lines", fontsize=9)
        ax_cnt.set_xticks(x)
        ax_cnt.set_xticklabels(all_months, rotation=45, ha="right", fontsize=7)
        if i == 0:
            ax_cnt.set_title("Instrumented Lines", fontsize=11, fontweight="bold")

    fig.suptitle(
        "Monthly Coverage Trend per Suite", fontsize=13, fontweight="bold", y=1.01
    )
    fig.tight_layout()
    path = out_dir / "monthly_trend_per_suite.png"
    fig.savefig(path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return path


# ── Plot 8: Lines scatter ───────────────────────────────────────────────────


def plot_lines_scatter(commits: list[dict], out_dir: Path) -> Path:
    data_pass = []
    data_fail = []
    data_error = []

    for c in commits:
        ts = c.get("timestamp", 0)
        agg = c.get("aggregate")
        hit = agg.get("lines", {}).get("hit") if agg else None
        if ts == 0:
            continue
        if c["status"] == "pass" and hit is not None:
            data_pass.append((ts, hit))
        elif c["status"] == "fail" and hit is not None:
            data_fail.append((ts, hit))
        elif c["status"] == "error":
            data_error.append((ts, 0))

    if not data_pass and not data_fail and not data_error:
        return _write_empty_plot(
            out_dir, "lines_scatter.png", "Lines Covered Scatter (no data)"
        )

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Lines Covered Over Time")

    for data, color, label in [
        (data_pass, "#2ca02c", "Passed"),
        (data_fail, "#ff7f0e", "Failed tests"),
        (data_error, "#d62728", "Error (no coverage)"),
    ]:
        if data:
            ts_arr = np.array([d[0] for d in data])
            vals = np.array([d[1] for d in data])
            dates = [datetime.fromtimestamp(t).strftime("%Y-%m") for t in ts_arr]
            unique_dates = sorted(set(dates))
            x_map = {d: i for i, d in enumerate(unique_dates)}
            x = np.array([x_map[d] for d in dates])
            ax.scatter(
                x, vals, c=color, alpha=0.5, s=12, label=label, edgecolors="none"
            )

    ax.set_ylabel("Lines Hit", fontsize=10)
    ax.set_xlabel("Month", fontsize=10)
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "lines_scatter.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Plot 8: Cumulative progress ─────────────────────────────────────────────


def plot_cumulative_progress(commits: list[dict], out_dir: Path) -> Path:
    monthly = defaultdict(lambda: {"pass": 0, "total": 0})
    for c in commits:
        month = c.get("month")
        if month:
            monthly[month]["total"] += 1
            if c["status"] == "pass":
                monthly[month]["pass"] += 1

    months = sorted(monthly.keys())
    if not months:
        return _write_empty_plot(
            out_dir, "cumulative_progress.png", "Cumulative Progress (no data)"
        )

    cum_total = []
    cum_pass = []
    t = 0
    p = 0
    for m in months:
        t += monthly[m]["total"]
        p += monthly[m]["pass"]
        cum_total.append(t)
        cum_pass.append(p)

    fig, ax = plt.subplots(figsize=(14, 5))
    _setup_plot(fig, ax, "Cumulative Progress")

    x = np.arange(len(months))
    ax.fill_between(x, cum_total, alpha=0.15, color="#7f7f7f")
    ax.plot(x, cum_total, color="#7f7f7f", linewidth=1.5, label="Total processed")
    ax.fill_between(x, cum_pass, alpha=0.15, color="#2ca02c")
    ax.plot(x, cum_pass, color="#2ca02c", linewidth=2, label="Successfully collected")

    if cum_total[-1] > 0:
        success_pct = cum_pass[-1] / cum_total[-1] * 100
        ax.text(
            x[-1],
            cum_pass[-1],
            f" {success_pct:.1f}%",
            color="#2ca02c",
            fontsize=10,
            fontweight="bold",
            va="bottom",
        )

    ax.set_xticks(x)
    ax.set_xticklabels(months, rotation=45, ha="right", fontsize=8)
    ax.set_ylabel("Commits", fontsize=10)
    ax.legend(fontsize=9)

    fig.tight_layout()
    path = out_dir / "cumulative_progress.png"
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Empty plot fallback ──────────────────────────────────────────────────────


def _write_empty_plot(out_dir: Path, filename: str, title: str) -> Path:
    fig, ax = plt.subplots(figsize=(14, 5))
    ax.set_title(title, fontsize=12)
    ax.set_axis_off()
    path = out_dir / filename
    fig.savefig(path, dpi=150)
    plt.close(fig)
    return path


# ── Main ─────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Generate CSV stats and plots for a coverage_reloaded project."
    )
    parser.add_argument(
        "project", help="Project name (must exist under projects/<name>/)"
    )
    parser.add_argument(
        "--output-dir", help="Output directory (default: projects/<name>/stats_output/)"
    )
    args = parser.parse_args()

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
    print(
        f"Found {len(commits)} commits: {passed} passed, {failed} failed, {errors} errors"
    )

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

    print(f"Done. Output in {output_dir}")


if __name__ == "__main__":
    main()
