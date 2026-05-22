import logging
import os

from src.project_metadata import PACKAGE_JSON
from src.project_metadata.helper import (
    get_file_json_content,
)
from src.project_metadata.workspaces.find_workspaces import find_workspaces

logger = logging.getLogger(__name__)


def get_commands(
    repo_path: str, revision: str, workspaces: dict[str, list[str]]
) -> dict[str, str]:
    """
    Retrieves the test commands specified in the package.json file at a given revision.
    """

    scripts = {}
    for workspace_source, workspace_paths in workspaces.items():
        for workspace_path in workspace_paths:
            workspace_package_json = (
                get_file_json_content(
                    repo_path, revision, os.path.join(workspace_path, PACKAGE_JSON)
                )
                or {}
            )
            workspace_scripts = workspace_package_json.get("scripts", {})
            workspace_scripts = {
                f"{workspace_source}:{workspace_path}: {key}": value
                for key, value in workspace_scripts.items()
            }

            scripts = scripts | workspace_scripts

    return scripts
