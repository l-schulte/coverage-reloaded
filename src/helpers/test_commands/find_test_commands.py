import pydriller

from src.helpers.test_commands.from_package_json import get_test_commands


def find_test_commands(
    commit: pydriller.Commit,
    repo_path: str,
) -> dict[str, str]:
    """
    Find test commands for a given commit. Looks for a package.json file in the commit and extracts the test commands from it.
    """

    test_commands = get_test_commands(repo_path, commit.hash)

    return test_commands if test_commands else {}
