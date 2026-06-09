"""
Configuration model for coverage_reloaded.

Provides typed dataclasses that mirror the structure of ``config.json``,
with full documentation of every option.  Use :func:`load_config` to read
and validate a JSON file at runtime.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# ──────────────────────────────────────────────────────────────────────────────
# Per-project options
# ──────────────────────────────────────────────────────────────────────────────


@dataclass
class ProjectConfig:
    """Settings for a single project in ``config.json → projects → <name>``.

    All keys are optional; defaults are applied by the Python code when a key
    is absent.
    """

    #: Git remote URL used to clone the repository.
    #: Example: ``"https://github.com/getsentry/sentry-javascript"``
    url: Optional[str] = None

    #: Override the project identifier used inside containers and for
    #: reporting.  Falls back to the project key name in ``config.json``.
    #: Example: ``"sentry-js"``
    projectID: Optional[str] = None

    #: If ``True``, the full Node.js version (e.g. ``"18.12.1"``) is used
    #: instead of just the major version (``"18"``).  Default: ``False``.
    use_exact_node_version: bool = False

    #: Ordered list of package managers to try when detecting the package
    #: manager for a commit.  Each entry is a name like ``"yarn"``, ``"pnpm"``,
    #: or ``"npm"``.  When set, the first manager whose lock file is found
    #: wins.  When ``None`` (default), the auto-detection order is used.
    #: Example: ``["pnpm", "yarn", "npm"]``
    package_manager_priority: Optional[List[str]] = None

    #: List of workspace glob patterns to merge into the auto-detected
    #: workspace list.  Useful when the project's workspace config is not
    #: discoverable from the root ``package.json`` or ``pnpm-workspace.yaml``.
    #: Example: ``["packages/*", "libs/*"]``
    workspaces: List[str] = field(default_factory=list)

    #: Minimum number of months a Node.js release must have been available
    #: before a commit's date to be considered a valid match.  This acts as
    #: a stabilisation delay — projects rarely adopt a Node version on the
    #: day it ships.  Used when resolving version constraints from
    #: ``package.json`` (``engines.node``) or ``pnpm-lock.yaml``.
    #: Default: ``3``.
    node_version_delay_months: int = 3

    #: Minimum Node.js major version to enforce.  If the detected version is
    #: lower, it is bumped to this value.  Default: ``0`` (no minimum).
    #: Example: ``16``
    min_node_version: int = 0


# ──────────────────────────────────────────────────────────────────────────────
# Top-level config
# ──────────────────────────────────────────────────────────────────────────────


@dataclass
class CoverageReloadedConfig:
    """Root configuration matching the top-level keys of ``config.json``."""

    #: Start date for commit collection (ISO-8601, ``YYYY-MM-DD``).
    #: Only commits on or after this date are collected.
    #: Default: ``"1970-01-01"``
    start_date: str = "1970-01-01"

    #: End date for commit collection (ISO-8601, ``YYYY-MM-DD``).
    #: Only commits on or before this date are collected.
    #: Default: ``"2100-01-01"``
    end_date: str = "2100-01-01"

    #: Maximum number of parallel worker threads/processes for coverage
    #: collection.  Default: ``4`` (or CPU count minus one when set via CLI).
    max_workers: int = 4

    #: Per-project configuration.  Keys are project names (used as directory
    #: names under ``projects/``), values are :class:`ProjectConfig`.
    projects: Dict[str, ProjectConfig] = field(default_factory=dict)


# ──────────────────────────────────────────────────────────────────────────────
# Loader
# ──────────────────────────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────────────────────
# Cached singleton
# ──────────────────────────────────────────────────────────────────────────────

_CONFIG: CoverageReloadedConfig | None = None


def get_config() -> CoverageReloadedConfig:
    """Return the cached global config, loading it on first call."""
    global _CONFIG
    if _CONFIG is None:
        _CONFIG = load_config()
    return _CONFIG


def load_config(path: str = "config.json") -> CoverageReloadedConfig:
    """Read *path* (a JSON file) and return a validated
    :class:`CoverageReloadedConfig`.

    The function handles the two spellings that exist in the codebase
    (``start_date`` / ``startdate``, ``end_date`` / ``enddate``) by
    normalising them.
    """
    if not os.path.isabs(path):
        # Resolve relative to the caller's working directory (typically the
        # project root).
        path = os.path.join(os.getcwd(), path)

    with open(path, "r") as fh:
        raw: Dict[str, Any] = json.load(fh)

    # Normalise legacy key names
    if "startdate" in raw and "start_date" not in raw:
        raw["start_date"] = raw.pop("startdate")
    if "enddate" in raw and "end_date" not in raw:
        raw["end_date"] = raw.pop("enddate")

    projects_raw: Dict[str, Any] = raw.pop("projects", {})
    projects: Dict[str, ProjectConfig] = {}
    for name, pconf in projects_raw.items():
        if isinstance(pconf, dict):
            projects[name] = ProjectConfig(**pconf)
        else:
            projects[name] = ProjectConfig()

    return CoverageReloadedConfig(
        start_date=raw.get("start_date", "1970-01-01"),
        end_date=raw.get("end_date", "2100-01-01"),
        max_workers=raw.get("max_workers", 4),
        projects=projects,
    )
