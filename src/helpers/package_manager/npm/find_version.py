import pydriller

from src.helpers.package_manager import from_package_json


def get_npm_version(
    commit_hash: str, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    1. Check package.json
    """

    package_manager_version = from_package_json.get_package_manager_version(
        "npm", repo_path, commit_hash
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    return None, None
