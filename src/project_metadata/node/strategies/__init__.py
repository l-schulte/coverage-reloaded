"""
Strategy registry for Node.js version resolution.

Each strategy module exposes a ``get_node_version`` function with the signature::

    def get_node_version(
        repo_path: str,
        commit_hash: str,
        release_cutoff: datetime | None = None,
    ) -> str | None: ...

The registry ``STRATEGIES`` is an ordered list of ``(source_name, callable)``
pairs tried in sequence by :func:`find_node_version`.
"""

from datetime import datetime
from typing import Callable, Optional

# Common protocol for all strategies
NodeVersionStrategy = Callable[[str, str, Optional[datetime]], Optional[str]]

from src.project_metadata.node.strategies import (
    nvmrc,
    package_json,
    pnpm_lock,
    tool_version,
    docker,
    preinstall,
    angular,
    releases,
)

STRATEGIES: list[tuple[str, NodeVersionStrategy]] = [
    (".nvmrc", nvmrc.get_node_version),
    ("package.json", package_json.get_node_version),
    ("pnpm-lock.yaml", pnpm_lock.get_node_version),
    (".tool-version", tool_version.get_node_version),
    ("Dockerfile", docker.get_node_version),
    ("build/npm/preinstall.js", preinstall.get_node_version),
    ("Angular compatibility", angular.get_node_version),
    ("node_releases.json (LTS, 12 months offset)", releases.get_node_version),
]

__all__ = ["STRATEGIES", "NodeVersionStrategy"]
