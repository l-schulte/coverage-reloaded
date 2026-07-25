#!/usr/bin/env python3
"""HTTP server that serves the dashboard and provides a /api/data endpoint.

The API endpoint scans all projects/*/output/ directories and returns structured
JSON.  Results are cached both on-disk (per-project .dashboard-index.json) and
in-memory so that repeated requests are near-instant.

Usage:
    python3 serve-dashboard.py          # port 8000
    python3 serve-dashboard.py 8080     # custom port
"""

import hashlib
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from http.server import SimpleHTTPRequestHandler
from pathlib import Path
from socketserver import ThreadingMixIn
from http.server import HTTPServer

BASE_DIR = Path(__file__).resolve().parent
PROJECTS_DIR = BASE_DIR / "projects"
ARCHIVE_DIR = BASE_DIR / "archive"
INDEX_FILENAME = ".dashboard-index.json"

# ---------------------------------------------------------------------------
# In-memory cache
# ---------------------------------------------------------------------------
# _cache = { project_name: { "mtime": float, "data": list_of_commits } }
_cache: dict = {}
# _project_mtimes = { project_name: float }  — latest output-dir mtime per project
_project_mtimes: dict = {}
# _full_data_cache = { "data": list, "etag": str, "last_modified": str }
_full_data_cache: dict = {}


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
    """Scan a project's output directory and return commit data.

    When a commit appears both as a directory (retried with suites) and as
    a flat ``.error`` marker (original failure), the directory is preferred
    — the retry produced newer coverage data.
    """
    if not output_dir.is_dir():
        return []

    # Collect all directory prefixes first so we can skip stale error markers.
    dir_prefixes = set()
    for entry in output_dir.iterdir():
        if entry.is_dir():
            dir_prefixes.add(entry.name)

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
            # Error marker — skip if a directory (newer retry) already exists
            # for the same commit prefix.
            hash_val = entry.stem
            prefix = hash_val  # e.g. "1612290272_0126ccbcf8..."
            if prefix in dir_prefixes:
                continue
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


# ---------------------------------------------------------------------------
# Disk-backed index cache
# ---------------------------------------------------------------------------

def _output_dir_mtime(output_dir: Path) -> float:
    """Return the newest mtime across all direct children of output_dir."""
    newest = 0.0
    try:
        for entry in output_dir.iterdir():
            try:
                m = entry.stat().st_mtime
                if m > newest:
                    newest = m
            except OSError:
                pass
    except OSError:
        pass
    return newest


def _load_index(index_path: Path) -> list | None:
    """Load a .dashboard-index.json if it exists and is valid."""
    try:
        return json.loads(index_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def _write_index(index_path: Path, commits: list) -> None:
    """Write commits list to .dashboard-index.json."""
    try:
        index_path.write_text(json.dumps(commits))
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Project scanning with caching
# ---------------------------------------------------------------------------

def _scan_project(proj_dir: Path, repo_urls: dict) -> dict | None:
    """Scan a single project, using disk+memory caches when possible."""
    output_dir = proj_dir / "output"
    if not output_dir.is_dir():
        return None

    proj_name = proj_dir.name
    current_mtime = _output_dir_mtime(output_dir)

    # Check in-memory cache
    cached = _cache.get(proj_name)
    if cached and cached["mtime"] == current_mtime:
        commits = cached["data"]
    else:
        # Try disk index
        index_path = output_dir / INDEX_FILENAME
        disk_index_mtime = 0.0
        try:
            disk_index_mtime = index_path.stat().st_mtime
        except OSError:
            pass

        if disk_index_mtime >= current_mtime and current_mtime > 0:
            # Disk index is up to date
            commits = _load_index(index_path)
            if commits is None:
                # Corrupt index — full rescan
                commits = scan_output_dir(output_dir, proj_name)
                _write_index(index_path, commits)
        else:
            # Full scan needed
            commits = scan_output_dir(output_dir, proj_name)
            _write_index(index_path, commits)

        # Update in-memory cache
        _cache[proj_name] = {"mtime": current_mtime, "data": commits}

    _project_mtimes[proj_name] = current_mtime

    passed = sum(1 for c in commits if c["status"] == "pass")
    failed = sum(1 for c in commits if c["status"] == "fail")
    errors = sum(1 for c in commits if c["status"] == "error")
    last_run = max((c["mtime"] for c in commits), default=0)

    return {
        "name": proj_name,
        "repoUrl": repo_urls.get(proj_name, ""),
        "commits": commits,
        "totalCommits": len(commits),
        "passed": passed,
        "failed": failed,
        "errors": errors,
        "lastRun": last_run,
    }


def scan_all_projects(full: bool = True) -> list:
    """Scan all projects and return the full dataset.

    When *full* is False, return project summaries without commit details
    (for the /api/projects endpoint).
    """
    projects = []
    repo_urls = _load_repo_urls()

    if not PROJECTS_DIR.is_dir():
        return projects

    for proj_dir in sorted(PROJECTS_DIR.iterdir()):
        if not proj_dir.is_dir():
            continue
        result = _scan_project(proj_dir, repo_urls)
        if result is None:
            continue

        if not full:
            # Strip commit details for the lightweight summary endpoint
            result = {
                "name": result["name"],
                "repoUrl": result["repoUrl"],
                "totalCommits": result["totalCommits"],
                "passed": result["passed"],
                "failed": result["failed"],
                "errors": result["errors"],
                "lastRun": result["lastRun"],
            }

        projects.append(result)

    projects.sort(key=lambda p: p["lastRun"], reverse=True)
    return projects


def _compute_etag() -> str:
    """Compute an ETag from project mtimes."""
    parts = []
    for name in sorted(_project_mtimes):
        parts.append(f"{name}:{_project_mtimes[name]}")
    return hashlib.md5("|".join(parts).encode()).hexdigest()


def _http_date(ts: float) -> str:
    """Convert a UNIX timestamp to an HTTP-date string."""
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime(
        "%a, %d %b %Y %H:%M:%S GMT"
    )


# ---------------------------------------------------------------------------
# HTTP handler
# ---------------------------------------------------------------------------

class DashboardHandler(SimpleHTTPRequestHandler):
    """HTTP handler that serves static files and the API endpoint."""

    def do_GET(self):
        if self.path == "/api/data":
            self._serve_api_data(full=True)
        elif self.path == "/api/projects":
            self._serve_api_data(full=False)
        elif self.path.startswith("/api/project/"):
            # /api/project/<name> — single project detail
            proj_name = self.path[len("/api/project/") :].rstrip("/")
            self._serve_project_detail(proj_name)
        elif self.path.endswith((".log", ".error")):
            self._serve_log_file()
        else:
            super().do_GET()

    def _serve_api_data(self, full: bool = True) -> None:
        global _full_data_cache
        data = scan_all_projects(full=full)
        body = json.dumps(data).encode()
        etag = _compute_etag()

        # Check If-None-Match
        client_etag = self.headers.get("If-None-Match", "")
        if client_etag and client_etag == etag:
            self.send_response(304)
            self.end_headers()
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("ETag", etag)
        self.send_header("Cache-Control", "public, max-age=5")
        self.end_headers()
        self.wfile.write(body)

    def _serve_project_detail(self, proj_name: str) -> None:
        """Return full commit data for a single project."""
        repo_urls = _load_repo_urls()
        proj_dir = PROJECTS_DIR / proj_name
        result = _scan_project(proj_dir, repo_urls)
        if result is None:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'{"error": "project not found"}')
            return
        body = json.dumps(result).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "public, max-age=5")
        self.end_headers()
        self.wfile.write(body)

    def _serve_log_file(self) -> None:
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

    def log_message(self, format, *args):
        if self.path.startswith("/api/"):
            return
        super().log_message(format, *args)


# ---------------------------------------------------------------------------
# Threading server
# ---------------------------------------------------------------------------

class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = ThreadingHTTPServer(("0.0.0.0", port), DashboardHandler)
    print(f"CoverageReloaded Dashboard: http://localhost:{port}/dashboard.html")
    print(f"API: http://localhost:{port}/api/data")
    print(f"API (summaries): http://localhost:{port}/api/projects")
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()
