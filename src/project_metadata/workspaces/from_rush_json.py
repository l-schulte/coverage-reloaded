from src.project_metadata import RUSH_JSON
from src.project_metadata.helper import (
    get_file_json_content,
    resolve_workspace_globs,
)


def get_workspaces(repo_path: str, revision: str) -> list[str] | None:
    """
    Retrieves the workspaces specified in the rush.json file at a given revision.

    Rush (https://rushjs.io/) defines projects in a `projects` array where each
    entry has a `projectFolder` field pointing to the subdirectory of the project.
    These are extracted and resolved as literal workspace paths.
    """

    rush_json = get_file_json_content(repo_path, revision, RUSH_JSON)
    if not rush_json:
        return None

    projects = rush_json.get("projects", [])
    if not isinstance(projects, list):
        return None

    # Each project entry has a "projectFolder" field like "core/backend"
    project_folders = [
        p["projectFolder"]
        for p in projects
        if isinstance(p, dict) and "projectFolder" in p
    ]

    if not project_folders:
        return None

    # Treat the project folders as literal glob patterns so resolve_workspace_globs
    # can find their package.json files.
    return resolve_workspace_globs(repo_path, revision, project_folders)
