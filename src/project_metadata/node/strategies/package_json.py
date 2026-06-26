from datetime import datetime
from typing import Optional

from src.project_metadata.helper import get_file_json_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

POTENTIAL_KEYS = ["engines", "volta", "packageManager"]


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
) -> Optional[str]:
    """
    Check ``package.json`` (``engines.node``, ``volta.node``, ``packageManager``)
    at the given commit.
    """
    package_json = get_file_json_content(repo_path, commit_hash, "package.json")
    if not package_json:
        return None

    for key in POTENTIAL_KEYS:
        if key in package_json:
            if "node" in package_json[key]:
                version = find_matching_version_from_version_string(
                    package_json[key]["node"],
                    use_first=use_first,
                    release_cutoff=release_cutoff,
                )
                if version:
                    return version

    return None
