import logging
from src.project_metadata.helper import get_file_at_commit

logger = logging.getLogger(__name__)


def get_coverage_tools(repo_path: str, revision: str) -> set[str]:
    """
    Determines which coverage tool (nyc, c8, or None) is configured for the project.
    """
    coverage_tools = set()

    config_files = {
        "nyc": [".nycrc", ".nycrc.json", ".nycrc.yml", ".nycrc.yaml"],
        "c8": [".c8rc", ".c8rc.json"],
    }

    for tool, files in config_files.items():
        for config_file in files:
            # Check if config file exists at this revision
            if get_file_at_commit(repo_path, revision, config_file):
                coverage_tools.add(tool)

    return coverage_tools
