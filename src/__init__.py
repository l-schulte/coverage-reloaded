"""
coverage_reloaded — longitudinal line-based coverage collection for JS/TS projects.

Exports
-------
- :class:`CoverageReloadedConfig` — typed root config
- :class:`ProjectConfig` — typed per-project config
- :func:`load_config` — read & validate ``config.json``
- :func:`get_config` — cached singleton accessor
"""

from src.config import CoverageReloadedConfig, ProjectConfig, get_config, load_config

__all__ = [
    "CoverageReloadedConfig",
    "ProjectConfig",
    "get_config",
    "load_config",
]
