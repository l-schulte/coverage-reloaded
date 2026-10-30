#!/usr/bin/env python3
"""Thin launcher kept for CLI compatibility — the implementation lives in stats/.

Usage:
    python stats.py <project_name> [--output-dir <dir>] [--report-only]
    python stats.py --aggregate [--output-dir <dir>]

Equivalent to `python -m stats [...]`. See stats/__init__.py for details.
"""

from stats.cli import main

if __name__ == "__main__":
    main()
