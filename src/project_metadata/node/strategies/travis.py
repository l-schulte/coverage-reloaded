"""
Travis CI strategy for Node.js version resolution.

Extracts the Node.js version from ``.travis.yml`` by inspecting the
``node_js`` key, which is a list of Node.js versions used in the build
matrix (e.g. ``node_js: [14, 16]``).

Reference: https://docs.travis-ci.com/user/languages/javascript-with-nodejs/
"""

from datetime import datetime
from typing import Optional

import yaml

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

TRAVIS_CONFIG_PATHS = [
    ".travis.yml",
    ".travis.yaml",
]


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
    **kwargs,
) -> Optional[str]:
    """
    Check ``.travis.yml`` at the given commit for Node.js version hints.

    Travis CI defines the Node.js version(s) under the ``node_js`` key as a
    list. We return the first valid version found.
    """
    for config_path in TRAVIS_CONFIG_PATHS:
        content = get_file_content(repo_path, commit_hash, config_path)
        if not content:
            continue

        try:
            config = yaml.safe_load(str(content))
        except yaml.YAMLError:
            continue

        if not isinstance(config, dict):
            continue

        # The node_js key can be a list or a single string
        node_js = config.get("node_js")
        if node_js is None:
            continue

        # Normalize to a list
        if isinstance(node_js, str):
            node_js = [node_js]

        if not isinstance(node_js, list):
            continue

        for version_val in node_js:
            # YAML parses unquoted numbers like "14" as int, not str
            if isinstance(version_val, (int, float)):
                version_str = str(int(version_val))
            elif isinstance(version_val, str):
                version_str = version_val
            else:
                continue
            version = find_matching_version_from_version_string(
                version_str, use_first=use_first
            )
            if version:
                return version

    return None
