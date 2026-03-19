import pydriller

from src.project_metadata.helper import file_existed_at_commit
from src.project_metadata.package_manager.pnpm.find_version import get_pnpm_version
from src.project_metadata.package_manager.yarn.find_version import get_yarn_version
from src.project_metadata.package_manager.npm.find_version import get_npm_version


def find_package_manager(
    commit_hash: str,
    repo_path: str,
    node_version: str,
    priority: list[str] | None,
) -> tuple[str | None, str | None]:
    """
    Attempts to identify the package manager used in a given commit by checking for the presence of lock files.
    Extracts the package manager version with package manager-specific logic (pnpm and yarn).
    """

    package_manager_runnables = {
        "pnpm": {
            "files": ["pnpm-lock.yaml"],
            "runnable": get_pnpm_version,
        },
        "npm": {
            "files": ["package-lock.json"],
            "runnable": get_npm_version,
        },
        "yarn": {
            "files": ["yarn.lock"],
            "runnable": get_yarn_version,
        },
    }

    if not priority:
        priority = ["pnpm", "yarn", "npm"]

    for pm in priority:
        pm_info = package_manager_runnables.get(pm)
        if not pm_info:
            continue

        for file in pm_info["files"]:
            if file_existed_at_commit(repo_path, commit_hash, file):
                pm_version = None
                pm_source = None
                # If the package manager has a specific function to extract the version, try to use it
                if pm_info["runnable"]:
                    pm_version, pm_source = pm_info["runnable"](
                        commit_hash, node_version, repo_path
                    )
                # If we couldn't extract a version but found the lock file, we can at least return the package manager name
                if not pm_version:
                    pm_version = pm
                    pm_source = file

                return pm_version, pm_source

    return None, None
