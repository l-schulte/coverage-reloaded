import re

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)


def get_node_version(
    repo_path: str,
    revision: str,
    dockerfile_paths: list[str] = ["Dockerfile", "docker/Dockerfile"],
) -> str | None:
    """
    Retrieves the Node.js version specified in the Dockerfile at a given revision.
    """

    for dockerfile_path in dockerfile_paths:
        content = get_file_content(repo_path, revision, dockerfile_path)
        if content:
            break
    else:
        return None

    if content:
        re_from_node = re.compile(r"node:(?:v|>=|<=|\^)?([\.(\d+)]+)-")
        version_match = re.findall(re_from_node, content)
        if version_match:
            version = find_matching_version_from_version_string(version_match[0])
            if version:
                return version
    return None
