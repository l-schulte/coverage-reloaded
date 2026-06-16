import csv
import logging
import concurrent.futures
import time
import threading
import os
import random
import tqdm
import argparse

from src.config import get_config
from src.docker.docker_run import docker_run_script

logger = logging.getLogger(__name__)

COMMITS_CSV_FILE = "commits.csv"
WORKSPACE_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Thread-local storage to assign worker IDs
worker_ids = threading.local()
worker_id_counter = threading.Lock()
next_worker_id = 1


def get_worker_id():
    """Get or assign a worker ID for the current thread."""
    global next_worker_id

    if not hasattr(worker_ids, "id"):
        with worker_id_counter:
            worker_ids.id = next_worker_id
            next_worker_id += 1

    return worker_ids.id


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--max-workers",
        type=int,
        required=False,
        help="Maximum number of workers to use.",
        default=(os.cpu_count() or 2) - 1,
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
    return parser.parse_args()


def execute(project, max_workers, max_commits=None):
    output_path = os.path.join(WORKSPACE_PATH, "projects", project, "output")
    logs_path = os.path.join(WORKSPACE_PATH, "projects", project, "logs")
    os.makedirs(logs_path, exist_ok=True)
    os.makedirs(output_path, exist_ok=True)

    global next_worker_id
    next_worker_id = 1  # Reset worker ID counter

    cfg = get_config()
    project_config = cfg.projects.get(project)
    if not project_config:
        logger.error(f"No configuration found for project: {project}")
        return

    project_id = project_config.projectID or project

    commits_csv = f"projects/{project}/" + COMMITS_CSV_FILE

    os.makedirs(output_path, exist_ok=True)

    # Read existing logs to skip commits that already succeeded
    # Logs are named {timestamp}_{commit_hash}.log (success) or .error (failure)
    # Error markers are named {timestamp}_{commit_hash}.error
    # Not-applicable markers are named {timestamp}_{commit_hash}.not_applicable
    # Coverage files are named {timestamp}_{commit_hash}__{test_type}__{subdir}.lcov
    # Exit code files are named {timestamp}_{commit_hash}__{test_type}__{subdir}__exit{code}.exit_code
    # We use logs instead of .lcov output files so we can support multiple
    # coverage artifacts per commit (e.g. separate Jest and Cypress lcov files).
    logger.info("Checking for already completed commits and cleaning up errors...")
    completed_commits = set()
    if os.path.exists(logs_path):
        for filename in os.listdir(logs_path):
            if filename.endswith(".log"):
                # Parse: {timestamp}_{commit_hash}.log
                parts = filename.rsplit("_", 1)
                if len(parts) == 2:
                    commit_hash = parts[1].split(".")[0]
                    completed_commits.add(commit_hash)
    if os.path.exists(output_path):
        for filename in os.listdir(output_path):
            if filename.endswith(".error"):
                os.remove(os.path.join(output_path, filename))

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

    start = time.time()
    logger.info(
        f"Processing {len(commits)} commits with {max_workers} workers - start time: {time.ctime(start)}"
    )

    # Run in parallel
    successful = 0
    completed = 0
    stopwatch = time.time()
    total = len(commits)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = [
            executor.submit(
                docker_run_script, commit, WORKSPACE_PATH, logs_path, output_path
            )
            for commit in commits
        ]

        progress = tqdm.tqdm(total=total, desc="Processing commits...")
        for future in concurrent.futures.as_completed(futures):
            completed += 1
            if future.result():
                successful += 1

            progress.update(1)
            progress.set_postfix(successful=successful)

            # if completed % 10 == 0 or completed < 10:
            #     elapsed = (time.time() - stopwatch) / 3600  # in hours
            #     logger.info(f"Completed {completed}/{total} commits")
            #     logger.info(f"\tSuccessful: {successful}")
            #     logger.info(f"\tFailed: {completed - successful}")
            #     logger.info(f"\tElapsed time: {elapsed:.2f} hours")
            #     logger.info(
            #         f"\tTime remaining: ~{(elapsed / completed) * (total - completed):.2f} hours"
            #     )

    end = time.time()
    duration = end - start
    logger.info(f"Total time: {duration:.2f} seconds")
    logger.info(f"Final result: {successful}/{total} successful")


def main():
    args = parse_args()
    execute(args.project, args.max_workers, args.max_commits)


if __name__ == "__main__":
    main()
