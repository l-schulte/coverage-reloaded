import logging

from src.helpers.helper import get_file_json_content
from src.helpers.node.parse_version import parse_node_version

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]

logger = logging.getLogger(__name__)


def __get_node_version_from_key(key: str, package_json: dict) -> str | None:
    """
    Retrieves the Node.js version from a specified key (engines, volta, etc.) in package.json.
    Package.json specified versions are often open-ended ranges, so we use the first match, not the last (use_first=True).
    """

    if key in package_json:
        if "node" in package_json[key]:
            version = parse_node_version(package_json[key]["node"], use_first=True)
            if version:
                return version
    return None


def get_node_version(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Retrieves the Node.js version specified in the package.json file at a given revision.
    """
    package_json = get_file_json_content(repo_path, revision, packagejson_path)
    if not package_json:
        return None

    node_version = None

    for key in POTENTIAL_KEYS:
        if not node_version:
            node_version = __get_node_version_from_key(key, package_json)

    return node_version
