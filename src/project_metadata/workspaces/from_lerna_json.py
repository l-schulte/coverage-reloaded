from src.project_metadata import LERNA_JSON
from src.project_metadata.helper import (
    get_file_json_content,
    resolve_wildcard_at_commit,
)


def get_workspaces(repo_path: str, revision: str) -> list[str] | None:
    """
    Retrieves the workspaces specified in the lerna.json file at a given revision.
    """

    lerna_json = get_file_json_content(repo_path, revision, LERNA_JSON) or {}
    workspaces = []
    for lerna_package_path in lerna_json.get("packages", []):
        workspaces += resolve_wildcard_at_commit(
            repo_path, revision, lerna_package_path
        )

    return workspaces
