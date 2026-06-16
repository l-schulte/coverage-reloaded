import pydriller

from src.project_metadata.package_manager import from_package_json
from src.project_metadata.helper import get_file_content

YARN_LOCKFILE_V1_HEADER = "# yarn lockfile v1"


def get_yarn_version(
    commit_hash: str, node_version: str, repo_path: str
) -> tuple[str | None, str | None]:
    """
    Attempts to retrieve the package manager version for a given commit hash.
    1. Check package.json (engines, volta, packageManager fields)
    2. Check yarn.lock header for Yarn v1 ("# yarn lockfile v1")
    """

    # 1. Check package.json
    package_manager_version = from_package_json.get_package_manager_version(
        "yarn", repo_path, commit_hash
    )
    if package_manager_version:
        return package_manager_version, "package.json"

    # 2. Check yarn.lock header for Yarn v1
    # The "# yarn lockfile v1" marker may not be on the very first line
    # (e.g. preceded by a comment), so search within the first 10 lines.
    yarn_lock = get_file_content(repo_path, commit_hash, "yarn.lock")
    if yarn_lock:
        first_lines = "\n".join(yarn_lock.split("\n")[:10])
        if YARN_LOCKFILE_V1_HEADER in first_lines:
            return "yarn@1", "yarn.lock"

    return None, None
