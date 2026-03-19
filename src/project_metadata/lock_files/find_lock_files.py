import pydriller

from src.project_metadata.lock_files.from_directory import get_lock_files


def find_lock_files(
    commit_hash: str,
    repo_path: str,
) -> dict[str, str]:
    """
    Find lock files for a given commit. Looks for a lock file in the commit and extracts the lock file path from it.
    """

    lock_files = get_lock_files(repo_path, commit_hash)

    return lock_files if lock_files else {}
