from datetime import datetime
import logging

from src.config import ProjectConfig
from src.project_metadata.lock_files.find_lock_files import find_lock_files
from src.project_metadata.node.find_node_version import find_node_version
from src.project_metadata.package_manager.find_package_manager import (
    find_package_manager,
)
from src.project_metadata.commands.find_commands import find_commands
from src.project_metadata.coverage_tools.find_coverage_tools import find_coverage_tools
from src.project_metadata.workspaces.find_workspaces import find_workspaces

logger = logging.getLogger(__name__)

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
    project_config: ProjectConfig,
) -> dict:
    """
    Process a single commit to extract relevant information such as Node.js version, package manager version, test commands, coverage tools, and lock files.

    Args:
        commit_hash (str): The hash of the commit to process.
        committer_date (datetime): The committer date of the commit.
        repo_path (str): The path to the local repository.
        project (str): The name of the project being processed.
        project_config (ProjectConfig): The typed configuration for the project.
    """

    if commit_hash == "30c223874831e0fdb7629498e56b800a8ca6b0da":
        print("DEBUG")

    use_exact_version = project_config.use_exact_node_version
    package_manager_priority = project_config.package_manager_priority
    workspaces = find_workspaces(repo_path, commit_hash)
    workspaces["config"] = project_config.workspaces
    min_node_version = project_config.min_node_version

    node, node_source = find_node_version(
        commit_hash,
        committer_date,
        repo_path,
        node_version_delay_months=project_config.node_version_delay_months,
        disabled_strategies=project_config.disabled_node_strategies,
        use_first=project_config.use_first_node_version,
    )
    if not node:
        raise ValueError(
            f"Could not determine Node.js version for commit {commit_hash} in project {project}. Likely the parsing failed. Please check the commit and the parsing logic."
        )

    if not use_exact_version:
        node = node.split(".")[0]  # Use major version only

    if min_node_version and int(node) < min_node_version:
        logger.warning(
            f"Node.js version {node} from {node_source} for commit {commit_hash} is below the minimum required version {min_node_version}. Setting to minimum version."
        )
        node_source = f"enforced minimum version {min_node_version} (originally {node} from {node_source})"
        node = str(min_node_version)

    # Check if a package manager version override is specified in the config
    if project_config.package_manager_version_overwrite:
        pm_version = project_config.package_manager_version_overwrite
        pm_source = "config override"
    else:
        pm_version, pm_source = find_package_manager(
            commit_hash, repo_path, node, package_manager_priority
        )
        # Fall back to the configured default if auto-detection found nothing
        if not pm_version:
            pm_version = project_config.package_manager_default
            pm_source = f"config default ({project_config.package_manager_default})"

    # Enforce minimum package manager version per manager
    min_pm_version = project_config.min_pm_version
    if min_pm_version and "@" in pm_version:
        pm_name = pm_version.split("@")[0]
        pm_requirement = min_pm_version.get(pm_name)
        if pm_requirement:
            pm_ver_only = pm_version.split("@")[1]
            # Simple major-version comparison (like min_node_version)
            pm_major = int(pm_ver_only.split(".")[0])
            min_major = int(pm_requirement.split(".")[0])
            if pm_major < min_major:
                # Ensure the requirement is a valid semver (e.g. "8" → "8.0.0")
                # so that downstream "npm install -g npm@8.0.0" works.
                parts = pm_requirement.split(".")
                parts += ["0"] * (3 - len(parts))
                pm_requirement_semver = ".".join(parts)
                logger.warning(
                    f"Package manager version {pm_version} for commit {commit_hash} "
                    f"does not satisfy minimum requirement {pm_name}@{pm_requirement}. "
                    f"Setting to minimum version."
                )
                pm_source = (
                    f"enforced minimum version {pm_name}@{pm_requirement_semver} "
                    f"(originally {pm_version} from {pm_source})"
                )
                pm_version = f"{pm_name}@{pm_requirement_semver}"

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
            "pm_version": pm_version,
            "pm_version_source": pm_source,
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
