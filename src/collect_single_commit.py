import json
import logging
import os
import pydriller

from src.project_metadata.project_metadata import extract_project_metadata
from src.docker.docker_run import docker_run_script

CONFIG = json.load(open("config.json"))
WORKSPACE_PATH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

logger = logging.getLogger(__name__)


def execute(project, commit_hash, base_path=None):
    """Collects data for a single commit."""

    if base_path is None:
        base_path = os.path.join(WORKSPACE_PATH, "projects", project)

    repo_path = os.path.join(base_path, "repo")
    if not os.path.exists(repo_path):
        logger.error(f"Repository for project {project} not found at {repo_path}.")
        return

    logger.info(f"Processing project {project} ({repo_path}).")
    repo = pydriller.Repository(repo_path, single=commit_hash)
    commit_data = next(repo.traverse_commits())

    project_config = CONFIG["projects"][project]
    project_id = project_config.get("projectID", project)

    output_path = os.path.join(base_path, "output")
    os.makedirs(output_path, exist_ok=True)

    logs_path = os.path.join(base_path, "logs")
    os.makedirs(logs_path, exist_ok=True)

    commit_information = extract_project_metadata(
        commit_hash, commit_data.committer_date, repo_path, project, project_config
    )

    commit_information.get("commit", {})
    package_manager = commit_information.get("commit", {}).get("pm_version")
    node_version = commit_information.get("commit", {}).get("node_version")

    if not package_manager or not node_version:
        logger.error(
            f"Missing package manager or node version for commit {commit_hash} in project {project}. "
            + f"Currently got package manager: {package_manager}, node version: {node_version}."
        )
        return

    logger.info(
        f"Extracted metadata for commit {commit_hash} in project {project}:\n"
        + f"\tNode Version: {node_version}\n"
        + f"\tPackage Manager: {package_manager}"
    )

    success = docker_run_script(
        (
            project,
            project_id,
            commit_hash,
            commit_data.committer_date.timestamp(),
            node_version,
            package_manager,
        ),
        WORKSPACE_PATH,
        logs_path,
        output_path,
    )

    logger.info(
        f"Finished processing commit {commit_hash} in project {project} with success: {success}."
    )

    return success
