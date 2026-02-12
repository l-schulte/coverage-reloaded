import pydriller

from src.helpers.test_commands.from_package_json import get_test_commands


def find_test_commands(
    commit: pydriller.Commit,
    repo_path: str,
) -> list[str] | None:
    """
    Find test commands for a given commit. Looks for a package.json file in the commit and extracts the test commands from it.
    """

    return get_test_commands(repo_path, commit.hash)
