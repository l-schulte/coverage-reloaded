import csv
import json
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

MAX_WORKERS = 4
MAX_COMMITS = None
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

        return success

    except subprocess.TimeoutExpired:
        return False
    except Exception as e:
        print(f"Error occurred while processing commit {commit_hash}: {e}")
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


def main():
    args = parse_args()
    print(f"max_workers: {args.max_workers}")
    print(f"max_commits: {args.max_commits}")
    print(f"project: {args.project}")

    global MAX_COMMITS
    MAX_COMMITS = args.max_commits

    if args.project:
        execute(args.project, args.max_workers)
        return

    projects = CONFIG.get("projects", {}).keys()
    progress = tqdm.tqdm(projects, desc="Processing projects...", position=0)
    for project in progress:
        progress.set_description(f"Processing project: {project['name']}")
        execute(project["name"], args.max_workers)


def execute(project, max_workers):
    global MAX_WORKERS
    MAX_WORKERS = max_workers

    global next_worker_id
    next_worker_id = 1  # Reset worker ID counter

    project_config = CONFIG["projects"].get(project, {})
    if not project_config:
        print(f"No configuration found for project: {project}")
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

                if MAX_COMMITS and len(commits) >= MAX_COMMITS:
                    break

    start = time.time()
    print(
        f"Processing {len(commits)} commits with {MAX_WORKERS} workers - start time: {time.ctime(start)}"
    )

    # Run in parallel
    successful = 0
    completed = 0
    total = len(commits)

    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(run_docker_container, commit) for commit in commits]

        progress = tqdm.tqdm(total=total, desc="Processing commits...", position=1)
        for future in concurrent.futures.as_completed(futures):
            completed += 1
            if future.result():
                successful += 1

            progress.update(1)
            progress.set_postfix(successful=successful)

    end = time.time()
    duration = end - start
    print(f"Total time: {duration:.2f} seconds")
    print(f"Final result: {successful}/{total} successful")


if __name__ == "__main__":
    main()
