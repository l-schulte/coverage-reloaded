import pydriller

from src.helpers.versions.yarn import from_package_json as package_json


def get_yarn_version(
    commit: pydriller.Commit, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    """

    package_manager_version = package_json.get_yarn_version(
        repo_path, commit.hash, packagejson_path="package.json"
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    return None, None
