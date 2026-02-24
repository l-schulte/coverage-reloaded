import pydriller

import src.helpers.coverage_tools.from_package_json as package_json
import src.helpers.coverage_tools.from_config_files as config_files


def find_coverage_tools(
    commit_hash: str,
    repo_path: str,
) -> list[str]:
    """
    Find test commands for a given commit. Looks for a package.json file in the commit and extracts the test commands from it.
    """

    coverage_tools = set()

    coverage_tools.update(package_json.get_coverage_tools(repo_path, commit_hash))

    if "nyc" not in coverage_tools or "c8" not in coverage_tools:
        coverage_tools.update(config_files.get_coverage_tools(repo_path, commit_hash))

    return list(coverage_tools)
