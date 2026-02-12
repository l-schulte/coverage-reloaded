import json
from src.helpers.helper import get_file_content
from src.helpers.package_manager.parse_version import (
    parse_package_manager_version,
)

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]


def __get_package_manager_version_from_key(
    pm: str, key: str, package_json: dict
) -> str | None:
    """
    Retrieves the package manager version from a specified key (engines, volta, etc.) in package.json.
    """

    if key in package_json:
        extracted_version = None
        if type(package_json[key]) is str and package_json[key].startswith(f"{pm}@"):
            extracted_version = package_json[key].split("@")[-1]

        if type(package_json[key]) is dict and pm in package_json[key]:
            extracted_version = package_json[key][pm]

        if not extracted_version:
            return None

        version = parse_package_manager_version(extracted_version)
        if version:
            return f"{pm}@{version}"
    return None


def get_package_manager_version(
    pm: str, repo_path: str, revision: str, packagejson_path: str = "package.json"
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
            package_manager_version = __get_package_manager_version_from_key(
                pm, key, package_json
            )

    return package_manager_version
