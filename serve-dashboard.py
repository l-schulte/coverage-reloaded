#!/usr/bin/env python3
"""Tiny HTTP server that serves the dashboard and provides a /api/data endpoint.

The API endpoint scans all projects/*/output/ directories once per request and
returns structured JSON. The dashboard HTML fetches this single endpoint instead
of making hundreds of individual file requests.

Usage:
    python3 serve-dashboard.py          # port 8000
    python3 serve-dashboard.py 8080     # custom port
"""

import json
import os
import re
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
PROJECTS_DIR = BASE_DIR / "projects"
ARCHIVE_DIR = BASE_DIR / "archive"


def parse_lcov(text: str) -> dict:
    """Parse lcov text and return coverage summary."""
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


def scan_output_dir(output_dir: Path, project_name: str = "") -> list:
    """Scan a project's output directory and return commit data."""
    if not output_dir.is_dir():
        return []

    commits = []
    for entry in sorted(output_dir.iterdir(), key=lambda p: p.name, reverse=True):
        if entry.is_dir():
            # Commit directory with suites
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
                        {
                            "name": suite_name,
                            "exitCode": exit_code,
                            "coverage": coverage,
                        }
                    )

            any_fail = any(
                s["exitCode"] is not None and s["exitCode"] != 0 for s in suites
            )
            status = "fail" if any_fail else "pass"

            # Build log URL: projects/<name>/logs/<timestamp>_<hash>.log
            # (or .error if the commit failed)
            ts_hash = entry.name  # e.g. "1612290272_0126ccbcf8..."
            log_path = Path(str(output_dir.parent / "logs")) / f"{ts_hash}.log"
            log_ext = ".log" if log_path.is_file() else ".error"
            log_url = (
                f"projects/{project_name}/logs/{ts_hash}{log_ext}"
                if project_name
                else ""
            )

            # Get log file mtime for sorting by latest run
            log_mtime = log_path.stat().st_mtime if log_path.is_file() else 0

            commits.append(
                {
                    "prefix": entry.name,
                    "hash": entry.name,
                    "date": _ts_to_date(entry.name.split("_")[0]),
                    "status": status,
                    "suites": suites,
                    "logUrl": log_url,
                    "mtime": log_mtime,
                }
            )

        elif entry.suffix == ".error":
            # Error marker
            hash_val = entry.stem
            log_path = Path(str(output_dir.parent / "logs")) / f"{hash_val}.error"
            log_ext = ".error" if log_path.is_file() else ".log"
            log_url = (
                f"projects/{project_name}/logs/{hash_val}{log_ext}"
                if project_name
                else ""
            )
            log_mtime = log_path.stat().st_mtime if log_path.is_file() else 0
            commits.append(
                {
                    "prefix": hash_val,
                    "hash": hash_val,
                    "date": _ts_to_date(hash_val.split("_")[0]),
                    "status": "error",
                    "suites": [],
                    "logUrl": log_url,
                    "mtime": log_mtime,
                }
            )

    return commits


def _ts_to_date(ts: str) -> str:
    try:
        n = int(ts)
        from datetime import datetime

        d = datetime.fromtimestamp(n if n < 1e12 else n / 1000)
        return d.strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return ts


def _load_repo_urls() -> dict:
    """Load repo URLs from config.json, keyed by project name."""
    config_file = BASE_DIR / "config.json"
    if not config_file.is_file():
        return {}
    try:
        with open(config_file) as f:
            cfg = json.load(f)
        return {
            name: data.get("url", "") for name, data in cfg.get("projects", {}).items()
        }
    except (json.JSONDecodeError, KeyError):
        return {}


def scan_all_projects() -> list:
    """Scan all projects and return the full dataset."""
    projects = []
    repo_urls = _load_repo_urls()

    for base_dir in (PROJECTS_DIR,):
        if not base_dir.is_dir():
            continue
        for proj_dir in sorted(base_dir.iterdir()):
            if not proj_dir.is_dir():
                continue
            output_dir = proj_dir / "output"
            if not output_dir.is_dir():
                continue

            commits = scan_output_dir(output_dir, proj_dir.name)
            passed = sum(1 for c in commits if c["status"] == "pass")
            failed = sum(1 for c in commits if c["status"] == "fail")
            errors = sum(1 for c in commits if c["status"] == "error")

            # Latest run = max mtime across all commits' log files
            last_run = max((c["mtime"] for c in commits), default=0)

            projects.append(
                {
                    "name": proj_dir.name,
                    "repoUrl": repo_urls.get(proj_dir.name, ""),
                    "commits": commits,
                    "totalCommits": len(commits),
                    "passed": passed,
                    "failed": failed,
                    "errors": errors,
                    "lastRun": last_run,
                }
            )

    # Sort projects by lastRun descending (most recently run first)
    projects.sort(key=lambda p: p["lastRun"], reverse=True)
    return projects


class DashboardHandler(SimpleHTTPRequestHandler):
    """HTTP handler that serves static files and the API endpoint."""

    def do_GET(self):
        if self.path == "/api/data":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            data = scan_all_projects()
            self.wfile.write(json.dumps(data).encode())
        elif self.path.endswith((".log", ".error")):
            # Serve log and error files as text/plain so they display in the
            # browser instead of being downloaded.
            file_path = BASE_DIR / self.path.lstrip("/")
            if file_path.is_file():
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(file_path.stat().st_size))
                self.end_headers()
                with open(file_path, "rb") as f:
                    self.wfile.write(f.read())
            else:
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"File not found")
        else:
            super().do_GET()

    def log_message(self, format, *args):
        # Quieter logging — skip API calls, log everything else normally
        if self.path == "/api/data":
            return
        super().log_message(format, *args)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = HTTPServer(("0.0.0.0", port), DashboardHandler)
    print(f"CoverageReloaded Dashboard: http://localhost:{port}/dashboard.html")
    print(f"API: http://localhost:{port}/api/data")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
