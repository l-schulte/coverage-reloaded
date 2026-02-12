import pydriller

from src.helpers.helper import file_exists_in_commit
from src.helpers.package_manager.pnpm.find_version import get_pnpm_version
from src.helpers.package_manager.yarn.find_version import get_yarn_version


def find_package_manager(
    commit: pydriller.Commit,
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
            "runnable": None,
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
            if file_exists_in_commit(repo_path, commit.hash, file):
                if pm_info["runnable"]:
                    pm_version, pm_source = pm_info["runnable"](
                        commit, node_version, repo_path
                    )
                else:
                    pm_version = pm
                    pm_source = file
                return pm_version, pm_source

    return None, None
