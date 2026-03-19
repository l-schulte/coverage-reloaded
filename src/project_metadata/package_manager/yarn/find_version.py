import pydriller

from src.project_metadata.package_manager import from_package_json


def get_yarn_version(
    commit_hash: str, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    1. Check package.json
    """

    package_manager_version = from_package_json.get_package_manager_version(
        "yarn", repo_path, commit_hash
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    return None, None
