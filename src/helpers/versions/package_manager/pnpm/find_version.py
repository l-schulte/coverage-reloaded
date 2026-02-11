import pydriller

from src.helpers.versions.package_manager import from_package_json
from src.helpers.versions.package_manager.pnpm import from_releases


def get_pnpm_version(
    commit: pydriller.Commit, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    1. Check package.json
    2. Check pnpm releases based on commit date
    """

    package_manager_version = from_package_json.get_package_manager_version(
        "pnpm", repo_path, commit.hash, packagejson_path="package.json"
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    package_manager_version = from_releases.get_pnpm_version(node_version)
    if package_manager_version:
        return package_manager_version, "pnpm_releases.json"

    return None, None
