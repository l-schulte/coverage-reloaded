import pydriller

from helpers.versions.pnpm import from_package_json as package_json
from helpers.versions.pnpm import from_releases as pnpm_releases


def get_pnpm_version(
    commit: pydriller.Commit, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    """

    package_manager_version = package_json.get_pnpm_version(
        repo_path, commit.hash, packagejson_path="package.json"
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    package_manager_version = pnpm_releases.get_pnpm_version(node_version)
    if package_manager_version:
        return package_manager_version, "pnpm_releases.json"

    return None, None
