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
    use_first: bool = False,
) -> Optional[str]:
    """
    Check ``.tool-version`` at the given commit.
    """
    content = get_file_content(repo_path, commit_hash, ".tool-version")
    if content:
        node_line = [line for line in content.splitlines() if line.startswith("node")]
        if not node_line:
            return None
        version_str = node_line[0].split(maxsplit=1)[1]
        version = find_matching_version_from_version_string(
            version_str, use_first=use_first
        )
        if version:
            return version
    return None
