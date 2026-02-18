import logging
from src.helpers.helper import get_file_json_content

logger = logging.getLogger(__name__)


def get_coverage_tools(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> set[str]:
    """
    Determines which coverage tool (nyc, c8, or None) is configured for the project.json
    """
    coverage_tools = set()

    package_json = get_file_json_content(repo_path, revision, packagejson_path)
    if not package_json:
        return coverage_tools

    # Check for nyc configuration in package.json
    if "nyc" in package_json:
        coverage_tools.add("nyc")

    # Check for c8 configuration in package.json
    if "c8" in package_json:
        coverage_tools.add("c8")

    return coverage_tools
