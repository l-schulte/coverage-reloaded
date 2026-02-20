import argparse
from datetime import datetime, timezone
import logging
import os
import subprocess
import pydriller
import json
import tqdm
import pandas as pd

from src.helpers.lock_files.find_lock_files import find_lock_files
from src.helpers.node.find_node_version import find_node_version
from src.helpers.package_manager.find_package_manager import find_package_manager
from src.helpers.test_commands.find_test_commands import find_test_commands
from src.helpers.coverage_tools.find_coverage_tools import find_coverage_tools

CONFIG = json.load(open("config.json"))

logger = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--project",
        type=str,
        required=False,
        help="Project name. Must be in config.json",
    )
    parser.add_argument(
        "--start-date",
        type=str,
        default=CONFIG.get("startdate", "1970-01-01"),
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=CONFIG.get("enddate", "2100-01-01"),
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    return parser.parse_args()


def execute(project: str, start_date: datetime, end_date: datetime):
    """
    Collects commit data for a given project within a specified date range.

    Args:
        project (str): The name of the project.
        start_date (datetime): The start date for commit collection.
        end_date (datetime): The end date for commit collection.
    """

    logger.info(f"Collecting commits for {project} from {start_date} to {end_date}.")

    project_path = f"projects/{project}"
    project_url = CONFIG["projects"].get(project, {}).get("url", None)
    repo_path = f"{project_path}/repo"
    use_exact_version = (
        CONFIG["projects"].get(project, {}).get("use_exact_node_version", False)
    )

    os.makedirs(project_path, exist_ok=True)

    if project_url and not os.path.exists(repo_path):
        logger.info(f"Cloning repository for project {project} from {project_url}.")
        subprocess.run(["git", "clone", project_url, repo_path], check=True)

    project_commits_file = f"{project_path}/commits.csv"

    package_manager_priority = (
        CONFIG["projects"].get(project, {}).get("package_manager_priority", None)
    )

    commits = []
    additional_information = []

    # Suppress pydriller logging on info level
    logging.getLogger("pydriller").setLevel(logging.WARNING)
    repo = pydriller.Repository(repo_path)
    for commit in tqdm.tqdm(repo.traverse_commits(), desc="Processing commits"):

        if commit.committer_date >= end_date or commit.committer_date < start_date:
            continue

        node, node_source = find_node_version(commit, repo_path)
        if not node:
            raise ValueError(
                f"Could not determine Node.js version for commit {commit.hash} in project {project}. Likely the parsing failed. Please check the commit and the parsing logic."
            )

        if not use_exact_version:
            node = node.split(".")[0]  # Use major version only

        pm_version, pm_source = find_package_manager(
            commit, repo_path, node, package_manager_priority
        )

        test_commands = find_test_commands(commit, repo_path)
        coverage_tools = find_coverage_tools(commit, repo_path)
        lock_files = find_lock_files(commit, repo_path)

        commits.append(
            {
                "commit_hash": commit.hash,
                "timestamp": str(commit.committer_date.timestamp()).split(".")[0],
                "node_version": node,
                "node_version_source": node_source,
                "pm_version": pm_version if pm_version else "npm",
                "pm_version_source": pm_source if pm_source else "default (npm)",
                "coverage_tools": coverage_tools,
            }
        )

        additional_information.append(
            {
                "commit_hash": commit.hash,
            }
            | test_commands
            | lock_files
        )

    pd.DataFrame(commits).to_csv(project_commits_file, index=False)
    if os.path.exists(os.path.join(project_path, "commits_postprocess.py")):
        subprocess.run(
            ["python3", "commits_postprocess.py"], cwd=project_path, check=True
        )
    logger.info(f"Collected {len(commits)} commits for project {project}.")
    logger.debug(f"Saved commits to {project_commits_file}")
    pd.DataFrame(additional_information).to_csv(
        f"{project_path}/additional_information.csv", index=False
    )


def __main():
    """
    Main entry point if executed as a script. For testing purposes.
    For production use main.py / call execute() directly.
    """

    args = parse_args()

    start_date = datetime.fromisoformat(args.start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(args.end_date).replace(tzinfo=timezone.utc)

    if args.project:
        execute(args.project, start_date, end_date)
    else:
        for project in CONFIG.get("projects", {}).keys():
            execute(project, start_date, end_date)


if __name__ == "__main__":
    __main()
