import src.project_metadata.workspaces.from_package_json as package
import src.project_metadata.workspaces.from_lerna_json as lerna


def find_workspaces(repo_path: str, revision: str) -> dict[str, list[str]]:
    """
    Retrieves the workspaces specified at a given revision.
    """

    workspaces = {"root": ["."]}
    workspaces["workspaces_package"] = package.get_workspaces(repo_path, revision) or []
    workspaces["workspaces_lerna"] = lerna.get_workspaces(repo_path, revision) or []

    return workspaces
