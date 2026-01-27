import argparse
from datetime import datetime, timezone
import pydriller
import json
import tqdm
import pandas as pd
import os

from helpers.versions.helper import file_exists_in_commit
from helpers.versions.node.find_version import get_node_version
from helpers.versions.pnpm.find_version import get_pnpm_version

CONFIG = json.load(open("config.json"))


def get_or(value, default) -> str | None:
    return value if value is not None else default


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


def determine_package_manager(
    commit: pydriller.Commit, repo_path: str, priority: list[str]
) -> tuple[str | None, str | None]:
    package_manager_runnables = {
        "pnpm": {
            "files": ["pnpm-lock.yaml"],
            "runnable": get_pnpm_version,
        },
        "npm": {
            "files": ["package-lock.json"],
            "runnable": None,
        },
        "yarn": {
            "files": ["yarn.lock"],
            "runnable": None,
        },
    }

    for pm in priority:
        pm_info = package_manager_runnables.get(pm)
        if not pm_info:
            continue

        for file in pm_info["files"]:
            if file_exists_in_commit(repo_path, commit.hash, file):
                if pm_info["runnable"]:
                    pm_version, pm_source = pm_info["runnable"](commit, repo_path)
                else:
                    pm_version = pm
                    pm_source = file
                return pm_version, pm_source

    return None, None


def execute(project: str, start_date: datetime, end_date: datetime):
    project_path = f"projects/{project}"
    repo_path = f"{project_path}/repo"
    project_commits_file = f"{project_path}/commits.csv"

    package_manager_priority = (
        CONFIG["projects"]
        .get(project, {})
        .get("package_manager_priority", ["pnpm", "npm", "yarn"])
    )

    commits = []

    repo = pydriller.Repository(repo_path)
    for commit in tqdm.tqdm(repo.traverse_commits(), desc="Processing commits"):

        if commit.committer_date >= end_date or commit.committer_date < start_date:
            continue

        node, node_source = get_node_version(commit, repo_path)
        node = node.split(".")[0]  # Use major version only

        pm_version, pm_source = determine_package_manager(
            commit, repo_path, package_manager_priority
        )

        commits.append(
            {
                "commit_hash": commit.hash,
                "timestamp": str(commit.committer_date.timestamp()).split(".")[0],
                "node_version": node,
                "node_version_source": node_source,
                "pm_version": pm_version if pm_version else "npm",
                "pm_version_source": pm_source if pm_source else "default (npm)",
            }
        )

    pd.DataFrame(commits).to_csv(project_commits_file, index=False)
    print(f"Saved commits to {project_commits_file}")


def main():
    args = parse_args()

    start_date = datetime.fromisoformat(args.start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(args.end_date).replace(tzinfo=timezone.utc)

    if args.project:
        execute(args.project, start_date, end_date)
    else:
        for project in CONFIG.get("projects", {}).keys():
            execute(project, start_date, end_date)


if __name__ == "__main__":
    main()
