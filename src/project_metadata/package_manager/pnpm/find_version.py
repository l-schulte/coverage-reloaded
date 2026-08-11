import pydriller

from src.project_metadata.package_manager import from_package_json
from src.project_metadata.package_manager.pnpm import from_releases


def get_pnpm_version(
    commit_hash: str, node_version: str, repo_path: str,
    skip_engines: bool = False,
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash from package.json.
    1. Check package.json
    2. Check pnpm releases based on commit date
    """

    package_manager_version = from_package_json.get_package_manager_version(
        "pnpm", repo_path, commit_hash, skip_engines=skip_engines
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    package_manager_version = from_releases.get_pnpm_version(node_version)
    if package_manager_version:
        return package_manager_version, "pnpm_releases.json"

    return None, None
