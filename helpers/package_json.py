import json

from helpers.helper import get_file_at_commit, parse_version_string


POTENTIAL_KEYS = ["engines", "volta", "packageManager"]


def __get_packagejson_content(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Reads the content of the package.json file if it exists.
    """

    try:
        content = get_file_at_commit(repo_path, revision, packagejson_path)
        return content.strip() if content else None
    except Exception:
        return None


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


def __get_pnpm_version_from_key(key: str, package_json: dict) -> str | None:
    """
    Retrieves the package manager version from a specified key (engines, volta, etc.) in package.json.
    """

    if key in package_json:
        if type(package_json[key]) is str and package_json[key].startswith("pnpm@"):
            return package_json[key]

        if "pnpm" in package_json[key]:
            try:
                version = parse_version_string(package_json[key]["pnpm"])
                if version:
                    return f"pnpm@{version}"
            except Exception:
                pass
    return None


def get_pnpm_version(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Retrieves the package manager version specified in the package.json file at a given revision.
    """

    content = __get_packagejson_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    package_json = json.loads(content)

    package_manager_version = None

    for key in POTENTIAL_KEYS:
        if not package_manager_version:
            package_manager_version = __get_pnpm_version_from_key(key, package_json)

    return package_manager_version


def get_node_version(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> str | None:
    """
    Retrieves the Node.js version specified in the package.json file at a given revision.
    """

    content = __get_packagejson_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    package_json = json.loads(content)

    node_version = None

    for key in POTENTIAL_KEYS:
        if not node_version:
            node_version = __get_node_version_from_key(key, package_json)

    return node_version
