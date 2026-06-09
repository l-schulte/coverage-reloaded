"""
Node.js version resolution.

Provides :func:`find_node_version` (strategy-based orchestrator) and
:func:`get_node_releases` (release data lookup).
"""

from src.project_metadata.node.find_node_version import find_node_version
from src.project_metadata.node.releases_data import get_node_releases

__all__ = ["find_node_version", "get_node_releases"]
