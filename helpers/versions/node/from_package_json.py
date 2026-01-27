import json

from helpers.versions.helper import (
    get_file_content,
    parse_version_string,
)

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]


def __get_node_version_from_key(key: str, package_json: dict) -> str | None:
    """
    Retrieves the Node.js version from a specified key (engines, volta, etc.) in package.json.
    """

    if key in package_json:
        if "node" in package_json[key]:
            version = parse_version_string(package_json[key]["node"])
            if version:
                return version
    return None


def get_node_version(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Retrieves the Node.js version specified in the package.json file at a given revision.
    """

    content = get_file_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    try:
        package_json = json.loads(content)
    except json.JSONDecodeError:
        print(f"\nError decoding package.json at revision {revision}")
        return None

    node_version = None

    for key in POTENTIAL_KEYS:
        if not node_version:
            node_version = __get_node_version_from_key(key, package_json)

    return node_version
