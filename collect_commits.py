import argparse
from datetime import datetime, timezone
import pydriller
import json
import tqdm
import pandas as pd
import os
import subprocess

from helpers import (
    nvmrc,
    package_json,
    preinstall,
    tool_version,
    node_releases,
    docker,
    docker_container,
    pnpm_releases,
)

from helpers.helper import file_exists_in_commit

CONFIG = json.load(open("config.json"))
START_DATE = datetime.fromisoformat(CONFIG["startdate"]).replace(tzinfo=timezone.utc)
END_DATE = datetime.fromisoformat(CONFIG["enddate"]).replace(tzinfo=timezone.utc)


def get_or(value, default) -> str | None:
    return value if value is not None else default


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--project", type=str, required=True, help="Project name or path."
    )
    return parser.parse_args()


def get_node_version(commit: pydriller.Commit) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the Node.js version for a given commit hash.
    1. Check .nvmrc
    2. Check package.json
    3. Check dockerfiles
    """

    # 1. Check .nvmrc
    node_version = nvmrc.get_node_version(REPO_PATH, commit.hash, nvmrc_path=".nvmrc")
    if node_version:
        return node_version, ".nvmrc"

    # 2. Check package.json
    node_version = package_json.get_node_version(
        REPO_PATH, commit.hash, packagejson_path="package.json"
    )
    if node_version:
        return node_version, "package.json"

    # 3. Check .tool-version
    node_version = tool_version.get_node_version(
        REPO_PATH, commit.hash, tool_version_path=".tool-version"
    )
    if node_version:
        return node_version, ".tool-version"

    # 4. Check dockerfiles
    node_version = docker.get_node_version(
        REPO_PATH, commit.hash, dockerfile_paths=["Dockerfile", "docker/Dockerfile"]
    )
    if node_version:
        return node_version, "Dockerfile"

    # 5. Check build/npm/preinstall.js
    node_version = preinstall.get_node_version(
        REPO_PATH, commit.hash, preinstall_path="build/npm/preinstall.js"
    )
    if node_version:
        return node_version, "build/npm/preinstall.js"

    return None, None


def get_pnpm_version(
    commit: pydriller.Commit, node_version: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    """

    package_manager_version = package_json.get_pnpm_version(
        REPO_PATH, commit.hash, packagejson_path="package.json"
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    package_manager_version = pnpm_releases.get_pnpm_version(node_version)
    if package_manager_version:
        return package_manager_version, "pnpm_releases.json"

    return None, None


def main():
    args = parse_args()
    print(f"project: {args.project}")

    global PROJECT, PROJECT_PATH, REPO_PATH, PROJECT_COMMITS_FILE
    PROJECT = args.project
    PROJECT_PATH = f"projects/{PROJECT}"
    REPO_PATH = f"{PROJECT_PATH}/repo"
    os.makedirs(REPO_PATH, exist_ok=True)
    PROJECT_COMMITS_FILE = f"{PROJECT_PATH}/commits.csv"
    project_url = CONFIG["projects"].get(PROJECT, {}).get("url", None)

    package_manager_priority = (
        CONFIG["projects"]
        .get(PROJECT, {})
        .get("package_manager_priority", ["pnpm", "npm", "yarn"])
    )
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

    commits = []
    container = None

    if project_url:
        if not os.path.exists(os.path.join(REPO_PATH, ".git")):
            subprocess.run(["git", "clone", project_url, REPO_PATH], check=True)
        else:
            subprocess.run(["git", "-C", REPO_PATH, "fetch", "--all"], check=True)
    else:
        raise ValueError(f"Project URL not found for project: {PROJECT}")

    repo = pydriller.Repository(REPO_PATH)
    for commit in tqdm.tqdm(repo.traverse_commits(), desc="Processing commits"):

        if commit.committer_date >= END_DATE or commit.committer_date < START_DATE:
            continue

        node, node_source = get_node_version(commit)
        if not node:
            # Check node_releases.json based on commit date
            timestamp = int(commit.committer_date.timestamp())
            node = node_releases.get_node_version(timestamp, major_only=True)
            node_source = "node_releases.json (major_only)"

        pm_version = None
        pm_source = None
        for pm in package_manager_priority:
            pm_info = package_manager_runnables.get(pm)
            if not pm_info:
                continue

            for file in pm_info["files"]:
                if file_exists_in_commit(REPO_PATH, commit.hash, file):
                    if pm_info["runnable"]:
                        pm_version, pm_source = pm_info["runnable"](commit, node)
                    else:
                        pm_version = pm
                        pm_source = file
                    break
            if pm_version:
                break

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

    pd.DataFrame(commits).to_csv(PROJECT_COMMITS_FILE, index=False)
    print(f"Saved commits to {PROJECT_COMMITS_FILE}")


if __name__ == "__main__":
    main()
