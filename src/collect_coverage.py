import csv
import logging
import concurrent.futures
import threading
import time
import os
import random
import tqdm
import argparse

from src.config import get_config
from src.docker.docker_run import docker_run_script, pre_build_images

logger = logging.getLogger(__name__)

COMMITS_CSV_FILE = "commits.csv"
WORKSPACE_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class LaunchThrottle:
    """Thread-safe rate-limiter that paces container launches.

    Ensures that at least ``interval`` seconds elapse between any two
    consecutive container starts, preventing CPU and I/O thundering herds
    when launching parallel workers.
    """

    def __init__(self, interval: float = 10.0):
        self.interval = max(0.0, float(interval))
        self.lock = threading.Lock()
        self.last_launch = 0.0

    def wait(self):
        """Wait until at least ``self.interval`` seconds have passed since the last launch."""
        if self.interval <= 0:
            return
        sleep_time = 0.0
        with self.lock:
            now = time.time()
            if self.last_launch == 0.0:
                # The very first container launch starts immediately without delay.
                self.last_launch = now
            else:
                target_time = max(now, self.last_launch + self.interval)
                sleep_time = target_time - now
                self.last_launch = target_time

        if sleep_time > 0:
            logger.debug(
                f"Pacing container launch: waiting {sleep_time:.1f}s (launch_delay={self.interval}s)..."
            )
            time.sleep(sleep_time)


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--max-workers",
        type=int,
        required=False,
        help="Maximum number of workers to use. Defaults to config.json max_workers.",
        default=None,
    )
    parser.add_argument(
        "--max-commits",
        type=int,
        required=False,
        help="Maximum number of commits to process.",
    )
    parser.add_argument(
        "--project", type=str, required=False, help="Project name or path."
    )
    parser.add_argument(
        "--launch-delay",
        type=float,
        required=False,
        help="Minimum delay in seconds between consecutive container starts. Defaults to config.json launch_delay (10.0s).",
        default=None,
    )
    return parser.parse_args()


def _setup_project(project):
    """Resolve project config and create output/log dirs.

    Returns ``(project_id, output_path, logs_path)`` or ``None`` on error.
    """
    output_path = os.path.join(WORKSPACE_PATH, "projects", project, "output")
    logs_path = os.path.join(WORKSPACE_PATH, "projects", project, "logs")
    os.makedirs(logs_path, exist_ok=True)
    os.makedirs(output_path, exist_ok=True)

    cfg = get_config()
    project_config = cfg.projects.get(project)
    if not project_config:
        logger.error(f"No configuration found for project: {project}")
        return None

    return project_config.projectID or project, output_path, logs_path


def _run_commits(commits, max_workers, output_path, logs_path, desc, launch_delay=None):
    """Run *commits* through the docker pipeline in a thread pool.

    Returns the number of successful commits.
    """
    if not commits:
        return 0

    cfg = get_config()
    if launch_delay is None:
        launch_delay = cfg.launch_delay

    # Pre-build Docker images once so docker-run.sh can skip redundant builds.
    project = commits[0][0]  # project is index 0 in the commit tuple
    pre_build_images(commits, project, WORKSPACE_PATH)

    start = time.time()
    logger.info(
        f"Processing {len(commits)} commits with {max_workers} workers "
        f"(launch delay: {launch_delay}s) - start time: {time.ctime(start)}"
    )

    successful = 0
    completed = 0
    total = len(commits)

    throttle = LaunchThrottle(interval=launch_delay)

    def _run_with_throttle(commit):
        throttle.wait()
        return docker_run_script(commit, WORKSPACE_PATH, logs_path, output_path)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [executor.submit(_run_with_throttle, commit) for commit in commits]

        progress = tqdm.tqdm(total=total, desc=desc)
        for future in concurrent.futures.as_completed(futures):
            completed += 1
            if future.result():
                successful += 1
            progress.update(1)
            progress.set_postfix(successful=successful)

    duration = time.time() - start
    logger.info(f"Total time: {duration:.2f} seconds")
    logger.info(f"Final result: {successful}/{total} successful")
    return successful


def execute(project, max_workers, max_commits=None, launch_delay=None):
    setup = _setup_project(project)
    if setup is None:
        return
    project_id, output_path, logs_path = setup

    commits_csv = f"projects/{project}/" + COMMITS_CSV_FILE

    # Read existing logs to skip commits that already succeeded
    # Logs are named {timestamp}_{commit_hash}.log (success) or .error (failure)
    # Error markers are named {timestamp}_{commit_hash}.error
    # Not-applicable markers are named {timestamp}_{commit_hash}.not_applicable
    # Coverage files live in per-commit directories: {timestamp}_{commit_hash}/
    #   {test_type}__{subdir}.lcov
    #   {test_type}__{subdir}.exit_code
    # We use logs instead of .lcov output files so we can support multiple
    # coverage artifacts per commit (e.g. separate Jest and Cypress lcov files).
    logger.info("Checking for already completed commits and cleaning up errors...")
    completed_commits = set()
    if os.path.exists(logs_path):
        for filename in os.listdir(logs_path):
            # if filename.endswith(".log"):
            if filename.endswith(".log") or filename.endswith(".error"):
                # Parse: {timestamp}_{commit_hash}.log
                parts = filename.rsplit("_", 1)
                if len(parts) == 2:
                    commit_hash = parts[1].split(".")[0]
                    completed_commits.add(commit_hash)
    # Keep existing .error files — they represent historical failed attempts
    # and should not be deleted to preserve statistics.

    # Read valid commits
    commits = []
    with open(commits_csv, "r") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        random.shuffle(rows)
        for row in rows:
            node = row.get("node_version", "").strip()
            pm = row.get("pm_version", "").strip()
            if row["commit_hash"] not in completed_commits:
                commits.append(
                    (
                        project,
                        project_id,
                        row["commit_hash"],
                        row["timestamp"],
                        node,
                        pm,
                    )
                )

                if max_commits and len(commits) >= max_commits:
                    break

    _run_commits(
        commits,
        max_workers,
        output_path,
        logs_path,
        "Processing commits...",
        launch_delay=launch_delay,
    )


def execute_failed(project, max_workers, max_commits=None, launch_delay=None):
    """Retry all previously failed commits for a project.

    Scans the project's ``logs/`` directory for ``.error`` files and
    re-processes only those commits.

    This is useful after fixing infrastructure issues (missing WayPack
    overrides, missing system deps in the Dockerfile, etc.) to re-run
    only the commits that previously failed, rather than re-processing
    the entire history.
    """
    setup = _setup_project(project)
    if setup is None:
        return
    project_id, output_path, logs_path = setup

    commits_csv = f"projects/{project}/" + COMMITS_CSV_FILE

    # Load all commits from CSV for metadata lookup
    commits_data = {}
    if os.path.exists(commits_csv):
        with open(commits_csv, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                commits_data[row["commit_hash"]] = row
    else:
        logger.error(f"Commits CSV not found: {commits_csv}")
        return

    # Find failed commits from error logs, skipping any that already have
    # a corresponding .log (meaning a previous retry succeeded).
    failed_commits = []
    if os.path.exists(logs_path):
        for filename in os.listdir(logs_path):
            if filename.endswith(".error"):
                # Parse: {timestamp}_{commit_hash}.error
                parts = filename.rsplit("_", 1)
                if len(parts) == 2:
                    timestamp = parts[0]
                    commit_hash = parts[1].split(".")[0]

                    # If a .log already exists for this commit, skip —
                    # it was already successfully retried.
                    log_file = os.path.join(logs_path, f"{timestamp}_{commit_hash}.log")
                    if os.path.exists(log_file):
                        continue

                    if commit_hash in commits_data:
                        row = commits_data[commit_hash]
                        node = row.get("node_version", "").strip()
                        pm = row.get("pm_version", "").strip()
                        failed_commits.append(
                            (
                                project,
                                project_id,
                                commit_hash,
                                timestamp,
                                node,
                                pm,
                            )
                        )

    if max_commits and len(failed_commits) > max_commits:
        failed_commits = failed_commits[:max_commits]

    if not failed_commits:
        logger.info("No failed commits found to retry.")
        return

    logger.info(
        f"Found {len(failed_commits)} failed commits to retry "
        f"(max_commits={max_commits or 'unlimited'})."
    )

    _run_commits(
        failed_commits,
        max_workers,
        output_path,
        logs_path,
        "Retrying failed commits...",
        launch_delay=launch_delay,
    )

    # delete the .error files for successfully retried commits
    for commit in failed_commits:
        commit_hash = commit[2]
        timestamp = commit[3]
        error_file = os.path.join(logs_path, f"{timestamp}_{commit_hash}.error")
        log_file = os.path.join(logs_path, f"{timestamp}_{commit_hash}.log")
        if os.path.exists(log_file) and os.path.exists(error_file):
            os.remove(error_file)
            logger.info(
                f"Removed .error file for successfully retried commit: {commit_hash}"
            )


def main():
    args = parse_args()
    execute(
        args.project,
        args.max_workers,
        args.max_commits,
        launch_delay=args.launch_delay,
    )


if __name__ == "__main__":
    main()
