from datetime import datetime
from typing import Optional
import yaml

from src.project_metadata.helper import get_file_content, version_satisfies
from src.project_metadata.node.releases_data import get_node_releases


def _get_unique_node_version_strings(content: str) -> set[str]:
    """Extract unique ``engines.node`` version strings from pnpm-lock.yaml."""
    try:
        pnpm_lock_data = yaml.safe_load(content)
    except yaml.YAMLError:
        return set()

    node_version_strings: set[str] = set()
    for package_info in pnpm_lock_data.get("packages", {}).values():
        engines = package_info.get("engines", {})
        node_version = engines.get("node")
        if node_version:
            node_version_strings.add(node_version)
    return node_version_strings


def _get_first_compatible_node_version(
    node_version_strings: set[str],
    release_cutoff: Optional[datetime] = None,
    lts_only: bool = True,
) -> Optional[str]:
    """Find the first Node release that satisfies all version strings."""
    potential = [
        (key.removeprefix("v"), datetime.strptime(value["start"], "%Y-%m-%d"))
        for key, value in get_node_releases(lts_only=lts_only).items()
    ]

    for potential_version, release_date in potential:
        if release_cutoff and release_date.timestamp() >= release_cutoff.timestamp():
            continue

        if all(version_satisfies(potential_version, vs) for vs in node_version_strings):
            return potential_version

    return None


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
) -> Optional[str]:
    """
    Check ``pnpm-lock.yaml`` at the given commit.
    """
    content = get_file_content(repo_path, commit_hash, "pnpm-lock.yaml")
    if content:
        version_strings = _get_unique_node_version_strings(str(content))
        return _get_first_compatible_node_version(version_strings, release_cutoff)
    return None
