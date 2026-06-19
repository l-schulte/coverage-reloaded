import logging

import yaml

from src.project_metadata.helper import (
    file_existed_at_commit,
    get_file_content,
    resolve_workspace_globs,
)

logger = logging.getLogger(__name__)

PNPM_WORKSPACE_YAML_FILENAMES = ["pnpm-workspace.yaml", "pnpm-workspace.yml"]


def _find_workspace_file(repo_path: str, revision: str) -> str | None:
    """Returns the first pnpm workspace filename that exists at the given revision."""
    for filename in PNPM_WORKSPACE_YAML_FILENAMES:
        if file_existed_at_commit(repo_path, revision, filename):
            return filename
    return None


def get_workspaces(repo_path: str, revision: str) -> list[str] | None:
    """
    Retrieves the workspaces specified in the pnpm-workspace.yaml (or .yml) file
    at a given revision.
    """

    filename = _find_workspace_file(repo_path, revision)
    if not filename:
        return None

    content = get_file_content(repo_path, revision, filename)
    if not content:
        return None

    try:
        workspace_config = yaml.safe_load(content)
    except yaml.YAMLError as e:
        logger.error(
            f"Failed to parse {filename} at revision {revision} in {repo_path}: {e}"
        )
        return None

    if not isinstance(workspace_config, dict):
        return None

    packages = workspace_config.get("packages", [])
    if not isinstance(packages, list):
        return None

    return resolve_workspace_globs(repo_path, revision, packages)
