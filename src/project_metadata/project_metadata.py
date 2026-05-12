from datetime import datetime

from src.project_metadata.lock_files.find_lock_files import find_lock_files
from src.project_metadata.node.find_node_version import find_node_version
from src.project_metadata.package_manager.find_package_manager import (
    find_package_manager,
)
from src.project_metadata.commands.find_commands import find_commands
from src.project_metadata.coverage_tools.find_coverage_tools import find_coverage_tools
from src.project_metadata.workspaces.find_workspaces import find_workspaces

TEST_KEYWORDS = [
    "test",
    "jest",
    "mocha",
    "ava",
    "tap",
    "ci",
    "coverage",
    "unit",
    "integration",
    "e2e",
    "browser",
]


def extract_project_metadata(
    commit_hash: str,
    committer_date: datetime,
    repo_path: str,
    project: str,
    project_config: dict,
) -> dict:
    """
    Process a single commit to extract relevant information such as Node.js version, package manager version, test commands, coverage tools, and lock files.

    Args:
        commit_hash (str): The hash of the commit to process.
        committer_date (datetime): The committer date of the commit.
        repo_path (str): The path to the local repository.
        project (str): The name of the project being processed.
        project_config (dict): The configuration dictionary for the project.
    """

    use_exact_version = project_config.get("use_exact_node_version", False)
    package_manager_priority = project_config.get("package_manager_priority", None)
    workspaces = find_workspaces(repo_path, commit_hash)

    node, node_source = find_node_version(commit_hash, committer_date, repo_path)
    if not node:
        raise ValueError(
            f"Could not determine Node.js version for commit {commit_hash} in project {project}. Likely the parsing failed. Please check the commit and the parsing logic."
        )

    if not use_exact_version:
        node = node.split(".")[0]  # Use major version only

    pm_version, pm_source = find_package_manager(
        commit_hash, repo_path, node, package_manager_priority
    )

    commands = find_commands(commit_hash, repo_path, workspaces)
    coverage_tools = find_coverage_tools(commit_hash, repo_path)
    lock_files = find_lock_files(commit_hash, repo_path)

    timestamp = int(committer_date.timestamp())

    return {
        "commit": {
            "commit_hash": commit_hash,
            "timestamp": timestamp,
            "node_version": node,
            "node_version_source": node_source,
            "pm_version": pm_version if pm_version else "npm",
            "pm_version_source": pm_source if pm_source else "default (npm)",
            "coverage_tools": coverage_tools,
            "repo_root": repo_path,
        },
        "additional": (
            {
                "commit_hash": commit_hash,
                "timestamp": timestamp,
            }
            | commands
            | lock_files
        ),
    }
