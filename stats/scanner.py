"""Scanning projects/<name>/output/ commit entries."""

import os
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

from tqdm import tqdm

from .lcov import aggregate_suites, parse_lcov


# ── Timestamp helpers ────────────────────────────────────────────────────────


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
    elif entry.suffix == ".not_applicable":
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
            "status": "not_applicable",
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
    workers = max(1, min(15, os.cpu_count() or 4))
    with ProcessPoolExecutor(max_workers=workers) as pool:
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


def find_conflicts(output_dir: Path) -> list[dict]:
    """Return list of conflicting commits with their entry details.

    Each entry: {prefix, files: [{path, type, modified}]}
    """
    if not output_dir.is_dir():
        return []
    entries_by_prefix: dict[str, list[dict]] = defaultdict(list)
    for e in output_dir.iterdir():
        if e.is_dir():
            entries_by_prefix[e.name].append(
                {"path": str(e), "type": "dir", "modified": e.stat().st_mtime}
            )
        elif e.suffix == ".error":
            entries_by_prefix[e.stem].append(
                {"path": str(e), "type": "error", "modified": e.stat().st_mtime}
            )
        elif e.suffix == ".not_applicable":
            entries_by_prefix[e.stem].append(
                {"path": str(e), "type": "not_applicable", "modified": e.stat().st_mtime}
            )
    conflicts = []
    for prefix, files in entries_by_prefix.items():
        if len(files) > 1:
            files.sort(key=lambda f: f["type"])
            conflicts.append({"prefix": prefix, "files": files})
    conflicts.sort(key=lambda c: c["prefix"])
    return conflicts
