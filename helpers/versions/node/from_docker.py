import re

from helpers.versions.helper import get_file_content
from helpers.versions.node.parse_version import parse_node_version


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
            version = parse_node_version(version_match[0])
            if version:
                return version
    return None
