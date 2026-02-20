import logging
from src.helpers.helper import get_file_at_commit

logger = logging.getLogger(__name__)


def get_lock_files(repo_path: str, revision: str) -> dict[str, str] | None:
    """
    Retrieves the lock files specified in the package.json file at a given revision.
    """

    lock_file_names = ["package-lock.json", "yarn.lock", "pnpm-lock.yaml"]
    lock_files = {}

    for lock_file_name in lock_file_names:
        lock_file_content = get_file_at_commit(repo_path, revision, lock_file_name)
        if lock_file_content:
            lock_files[lock_file_name] = True

    return lock_files
