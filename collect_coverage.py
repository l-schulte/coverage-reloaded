import csv
import json
import logging
import subprocess
import concurrent.futures
import sys
import time
import threading
import os
import random
import tqdm
import argparse

CONFIG = json.load(open("config.json"))

logger = logging.getLogger(__name__)

COMMITS_CSV_FILE = "commits.csv"
WORKSPACE_PATH = os.path.dirname(os.path.abspath(__file__))
DOCKER_RUN_SCRIPT = os.path.join(WORKSPACE_PATH, "docker-run.sh")

# Thread-local storage to assign worker IDs
worker_ids = threading.local()
worker_id_counter = threading.Lock()
next_worker_id = 1


def parse_filename(filename) -> tuple[str, str, str, str]:
    """Parse log filename to extract node, timestamp, commit hash, and job ID."""
    parts = filename.rsplit("_", 3)
    node = parts[0].replace("node", "")
    timestamp = parts[1]
    commit_hash = parts[2]
    job_id = parts[3].split(".")[0]  # Remove file extension
    return node, timestamp, commit_hash, job_id


def get_filename(node, timestamp, commit_hash, job_id, success=True):
    """Generate log filename based on parameters."""
    ext = "log" if success else "error"
    return f"logs/node{node}_{timestamp}_{commit_hash}_{job_id}.{ext}"


def get_worker_id():
    """Get or assign a worker ID for the current thread."""
    global next_worker_id

    if not hasattr(worker_ids, "id"):
        with worker_id_counter:
            worker_ids.id = next_worker_id
            next_worker_id += 1

    return worker_ids.id


def run_docker_container(commit):
    """Run docker container for a single commit."""
    project, project_id, commit_hash, timestamp, node, pm = commit
    job = get_worker_id()

    command = [
        "/bin/sh",
        DOCKER_RUN_SCRIPT,
        project,
        "exec",
        commit_hash,
        str(timestamp),
        pm,
        node,
        project_id,
    ]

    try:
        result = subprocess.run(command, capture_output=True, text=True)
        success = result.returncode == 0

        log_filename = f"projects/{project}/{get_filename(node, timestamp, commit_hash, str(job), success)}"
        with open(log_filename, "w") as f:
            f.write(
                result.stdout
                + "\n----\n\n----\n"
                + (result.stderr if not success else "Success!")
            )

        if not success:
            logger.error(f"Commit {commit_hash} failed. See log: {log_filename}")
            error_lcov = f"projects/{project}/output/{commit_hash}.error"
            with open(error_lcov, "w") as f:
                f.write(f"Execution failed. See log for details.\n{log_filename}\n")

        return success

    except subprocess.TimeoutExpired:
        return False
    except Exception as e:
        logger.error(f"Error occurred while processing commit {commit_hash}: {e}")
        return False


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--max-workers",
        type=int,
        required=True,
        help="Maximum number of workers to use.",
        default=4,
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

    global next_worker_id
    next_worker_id = 1  # Reset worker ID counter

    project_config = CONFIG["projects"].get(project, {})
    if not project_config:
        logger.error(f"No configuration found for project: {project}")
        return

    project_id = project_config.get("projectID", project)

    logs_path = f"projects/{project}/logs"
    commits_csv = f"projects/{project}/" + COMMITS_CSV_FILE

    os.makedirs(logs_path, exist_ok=True)

    # Read existing logs to skip commits that already succeeded
    completed_commits = set()
    if os.path.exists(logs_path):
        for filename in os.listdir(logs_path):
            if filename.endswith(".log") or filename.endswith(".error"):
                _, _, commit_hash, _ = parse_filename(filename)
                completed_commits.add(commit_hash)

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
        futures = [executor.submit(run_docker_container, commit) for commit in commits]

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
