from src.project_metadata import PACKAGE_JSON
from src.project_metadata.helper import (
    get_file_json_content,
    resolve_wildcard_at_commit,
)


def get_workspaces(repo_path: str, revision: str) -> list[str] | None:
    """
    Retrieves the workspaces specified in the package.json file at a given revision.
    """

    package_json = get_file_json_content(repo_path, revision, PACKAGE_JSON)
    if not package_json:
        return None

    workspaces = []
    for workspace_package_path in package_json.get("workspaces", []):
        workspaces += resolve_wildcard_at_commit(
            repo_path, revision, workspace_package_path
        )

    return workspaces
