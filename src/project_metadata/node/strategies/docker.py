import re
from datetime import datetime
from typing import Optional

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

DOCKERFILE_PATHS = [
    "Dockerfile",
    "docker/Dockerfile",
    "Dockerfile.dev",
    "docker/Dockerfile.dev",
]


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
    **kwargs,
) -> Optional[str]:
    """
    Check ``Dockerfile`` / ``docker/Dockerfile`` at the given commit.
    """
    content: Optional[str] = None
    for dockerfile_path in DOCKERFILE_PATHS:
        content = get_file_content(repo_path, commit_hash, dockerfile_path)

        if not content:
            continue

        re_from_node = re.compile(r"node:(?:v|>=|<=|\^)?([\.(\d+)]+)-")
        version_match = re.findall(re_from_node, content)
        if version_match:
            version = find_matching_version_from_version_string(
                version_match[0], use_first=use_first
            )
            if version:
                return version

    return None
