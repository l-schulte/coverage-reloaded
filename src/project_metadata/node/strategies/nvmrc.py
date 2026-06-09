from datetime import datetime
from typing import Optional

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
) -> Optional[str]:
    """
    Check ``.nvmrc`` at the given commit.
    """
    content = get_file_content(repo_path, commit_hash, ".nvmrc")
    if content:
        version = find_matching_version_from_version_string(
            str(content), use_artificial_minor_version=True
        )
        if version:
            return version
    return None
