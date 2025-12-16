import re

from helpers.helper import get_file_at_commit, parse_version_string


def __get_dockerfile_content(
    repo_path: str,
    revision: str,
    dockerfile_paths: list[str] = ["Dockerfile", "docker/Dockerfile"],
) -> str | None:
    """
    Reads the content of the Dockerfile if it exists.
    """

    try:
        for dockerfile_path in dockerfile_paths:
            content = get_file_at_commit(repo_path, revision, dockerfile_path)
            if content:
                return content.strip()
        return None
    except Exception:
        return None


def get_node_version(
    repo_path: str,
    revision: str,
    dockerfile_paths: list[str] = ["Dockerfile", "docker/Dockerfile"],
) -> str | None:
    """
    Retrieves the Node.js version specified in the Dockerfile at a given revision.
    """

    content = __get_dockerfile_content(repo_path, revision, dockerfile_paths)
    if content:
        re_from_node = re.compile(r"node:(?:v|>=|<=|\^)?([\.(\d+)]+)-")
        version_match = re.findall(re_from_node, content)
        if version_match:
            version = parse_version_string(version_match[0])
            if version:
                return version
    return None
