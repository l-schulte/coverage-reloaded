from datetime import datetime
import json
import yaml

from src.project_metadata.helper import get_file_content, version_satisfies
from src.project_metadata.node import get_node_releases
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)


def __get_unique_node_version_strings(content: str) -> set[str]:
    """
    Extracts the node version strings from the engine fields of packages in the pnpm-lock.yaml content, e.g.:
    >    engines: {node: '>= 10.13'}
    Returns a unique set of these version strings.
    """

    # parse the yaml to dict
    try:
        pnpm_lock_data = yaml.safe_load(content)
    except yaml.YAMLError as e:
        return set()

    node_version_strings = set()
    for package_name, package_info in pnpm_lock_data.get("packages", {}).items():
        engines = package_info.get("engines", {})
        node_version = engines.get("node")
        if node_version:
            node_version_strings.add(node_version)
    return node_version_strings


def __get_first_compatible_node_version(
    node_version_strings: set[str],
    release_cutoff: datetime | None = None,
    lts_only: bool = True,
) -> str | None:
    """
    Given a set of node version strings, finds the first compatible Node.js version from the NODE_RELEASES.
    """

    potential_node_versions = set(
        [
            (key.removeprefix("v"), datetime.strptime(value["start"], "%Y-%m-%d"))
            for (key, value) in get_node_releases(lts_only=lts_only).items()
            if (not lts_only or value.get("lts"))
        ]
    )

    for potential_node_version, release_date in potential_node_versions:
        if release_cutoff and release_date.timestamp() >= release_cutoff.timestamp():
            continue

        compatible = False
        for node_version_string in node_version_strings:
            if version_satisfies(potential_node_version, node_version_string):
                compatible = True
                break
        if compatible:
            return potential_node_version

    return None


def get_node_version(
    repo_path: str,
    revision: str,
    pnpm_lock_path: str = "pnpm-lock.yaml",
    release_cutoff: datetime | None = None,
    lts_only: bool = True,
) -> str | None:
    """
    Retrieves the Node.js version specified in the pnpm-lock.yaml file at a given revision.
    """

    content = get_file_content(repo_path, revision, pnpm_lock_path)
    if content:
        node_version_strings = __get_unique_node_version_strings(str(content))

        return __get_first_compatible_node_version(node_version_strings, release_cutoff)
    return None
