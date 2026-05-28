import logging

import yaml

from src.project_metadata.helper import (
    get_file_content,
    resolve_wildcard_at_commit,
)

logger = logging.getLogger(__name__)

PNPM_WORKSPACE_YAML = "pnpm-workspace.yaml"


def get_workspaces(repo_path: str, revision: str) -> list[str] | None:
    """
    Retrieves the workspaces specified in the pnpm-workspace.yaml file at a given revision.
    """

    content = get_file_content(repo_path, revision, PNPM_WORKSPACE_YAML)
    if not content:
        return None

    try:
        workspace_config = yaml.safe_load(content)
    except yaml.YAMLError as e:
        logger.error(
            f"Failed to parse {PNPM_WORKSPACE_YAML} at revision {revision} in {repo_path}: {e}"
        )
        return None

    if not isinstance(workspace_config, dict):
        return None

    packages = workspace_config.get("packages", [])
    if not isinstance(packages, list):
        return None

    workspaces = []
    for workspace_package_path in packages:
        if not isinstance(workspace_package_path, str):
            continue
        workspaces += resolve_wildcard_at_commit(
            repo_path, revision, workspace_package_path
        )

    return workspaces
