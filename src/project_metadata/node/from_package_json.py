from datetime import datetime
import logging

from src.project_metadata.helper import get_file_json_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]

logger = logging.getLogger(__name__)


def get_node_version(
    repo_path: str,
    revision: str,
    packagejson_path: str = "package.json",
    before_date: datetime | None = None,
) -> str | None:
    """
    Retrieves the Node.js version specified in the package.json file at a given revision.
    """
    package_json = get_file_json_content(repo_path, revision, packagejson_path)
    if not package_json:
        return None

    if revision == "02aada4ae9578896ea3be75cf78298d7959ef2de":
        print("debug")

    for key in POTENTIAL_KEYS:
        if key in package_json:
            if "node" in package_json[key]:
                version = find_matching_version_from_version_string(
                    package_json[key]["node"], before_date=before_date
                )
                if version:
                    return version

    return None
