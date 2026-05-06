from src.project_metadata.commands.from_package_json import get_commands


def find_commands(
    commit_hash: str, repo_path: str, workspaces: dict[str, list[str]]
) -> dict[str, str]:
    """
    Find test commands for a given commit. Looks for a package.json file in the commit and extracts the test commands from it.
    """

    return get_commands(repo_path, commit_hash, workspaces)
