import json
from src.helpers.versions.helper import get_file_content, parse_version_string

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]


def __get_yarn_version_from_key(key: str, package_json: dict) -> str | None:
    """
    Retrieves the package manager version from a specified key (engines, volta, etc.) in package.json.
    """

    if key in package_json:
        content = package_json[key]
        if type(content) is str and content.startswith("yarn@"):
            return content
        elif type(content) is dict and "yarn" in content:
            try:
                version_string = content["yarn"]
                version_string = version_string.split("@")[-1]
                version = parse_version_string(version_string)
                if version:
                    return f"yarn@{version}"
            except Exception:
                pass
    return None


def get_yarn_version(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Retrieves the package manager version specified in the package.json file at a given revision.
    """

    content = get_file_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    package_json = json.loads(content)

    package_manager_version = None

    for key in POTENTIAL_KEYS:
        if not package_manager_version:
            package_manager_version = __get_yarn_version_from_key(key, package_json)

    return package_manager_version
