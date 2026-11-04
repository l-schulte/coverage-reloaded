"""Per-project CSV generation."""

import statistics
from collections import defaultdict
from pathlib import Path

import pandas as pd


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
    monthly_status = defaultdict(
        lambda: {"pass": 0, "fail": 0, "error": 0, "not_applicable": 0}
    )

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
        total = (
            st.get("pass", 0)
            + st.get("fail", 0)
            + st.get("error", 0)
            + st.get("not_applicable", 0)
        )
        rows.append(
            {
                "month": month,
                "total_commits": total,
                "passed": st.get("pass", 0),
                "failed": st.get("fail", 0),
                "errors": st.get("error", 0),
                "not_applicable": st.get("not_applicable", 0),
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
    not_applicable = sum(1 for c in commits if c["status"] == "not_applicable")

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
        "not_applicable": not_applicable,
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
