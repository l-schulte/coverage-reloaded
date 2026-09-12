"""
GitHub Actions strategy for Node.js version resolution.

Extracts the Node.js version used by the project's own GitHub Actions CI at a
given commit.  This is the most faithful source for projects whose CI runs a
specific Node major that ``engines.node`` ranges (``>=``) do not pin down
(e.g. n8n runs the *lowest* supported major while ``>=20.15`` would resolve to
the highest available LTS).

Sources (tried in priority order):
1. ``.github/workflows/units-tests-reusable.yml`` — the reusable test
   workflow's ``on.workflow_call.inputs.nodeVersion.default`` (e.g. ``20.x``).
2. ``.github/workflows/ci-pull-requests.yml`` / ``.github/workflows/ci-master.yml``
   — the matrix row flagged with ``collectCoverage``
   (``matrix.node-version == 'X'``), or a single unambiguous literal
   ``node-version:`` value on setup-node steps.

The strategy is deliberately conservative: ambiguous multi-version matrices
without a coverage flag return ``None`` so the caller falls through to the next
strategy, preserving legacy behaviour for early-era repos.
"""

import re
from datetime import datetime
from typing import Optional

import yaml

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

REUSABLE_WORKFLOW_PATHS = [
    ".github/workflows/units-tests-reusable.yml",
]

PR_WORKFLOW_PATHS = [
    ".github/workflows/ci-pull-requests.yml",
    ".github/workflows/ci-master.yml",
]

# Captures a literal node-version value, e.g.:
#   node-version: 16.x
#   node-version: '22.x'
#   node-version: [16.x]
#   node-version: [14.x, 16.x]
#   node-version: ${{ matrix.node-version }}   (expression -> skipped)
RE_NODE_VERSION_VALUE = re.compile(r"node-version:\s*(\[[^\]]*\]|[^\s#]+)")

# Captures the version singled out by a collectCoverage guard:
#   collectCoverage: ${{ matrix.node-version == '20.x' }}
RE_COVERAGE_GUARD = re.compile(r"node-version\s*==\s*['\"]?([\d.]+x?)['\"]?")

# Matches plain CI version tokens: 16, 16.x, 22.4, '22.x' — group(1) is the major.
RE_VERSION_TOKEN = re.compile(r"^\s*['\"]?(\d+)(?:\.(?:x|\d+))?['\"]?\s*$")


def _extract_workflow_call_default(content: str) -> Optional[str]:
    """Read ``on.workflow_call.inputs.nodeVersion.default`` from a reusable workflow."""
    try:
        config = yaml.safe_load(content)
    except yaml.YAMLError:
        return None
    if not isinstance(config, dict):
        return None

    # PyYAML (YAML 1.1) parses the `on:` key as boolean True.
    on_block = config.get("on") or config.get(True)
    if not isinstance(on_block, dict):
        return None
    workflow_call = on_block.get("workflow_call")
    if not isinstance(workflow_call, dict):
        return None
    inputs = workflow_call.get("inputs")
    if not isinstance(inputs, dict):
        return None
    node_version_input = inputs.get("nodeVersion")
    if not isinstance(node_version_input, dict):
        return None
    default = node_version_input.get("default")
    if not isinstance(default, str) or not default.strip():
        return None
    return default.strip()


def _extract_coverage_matrix_version(content: str) -> Optional[str]:
    """Return the version matched by a ``collectCoverage: ... == 'X'`` guard."""
    m = RE_COVERAGE_GUARD.search(content)
    if m:
        return m.group(1)
    return None


def _extract_literal_node_versions(content: str) -> list[str]:
    """Collect every literal (non-expression) ``node-version`` value in a workflow file."""
    versions: list[str] = []
    for m in RE_NODE_VERSION_VALUE.finditer(content):
        raw = m.group(1).strip()
        if raw.startswith("${{"):
            continue  # expression, not a literal version
        if raw.startswith("["):
            # matrix list, e.g. [16.x] or [10.x, 12.x, 14.x]
            inner = raw.strip("[]")
            versions.extend(
                tok.strip().strip("'\"") for tok in inner.split(",") if tok.strip()
            )
        else:
            versions.append(raw.strip().strip("'\""))
    return versions


def _normalise(version_str: str) -> Optional[str]:
    """Map a CI version token like ``16.x`` / ``20`` to a Node major string."""
    m = RE_VERSION_TOKEN.match(version_str.strip())
    if m:
        return m.group(1)
    version = find_matching_version_from_version_string(version_str)
    if version:
        return version.split(".")[0]
    return None


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
    **kwargs,
) -> Optional[str]:
    """
    Check the project's GitHub Actions workflows at the given commit for the
    Node.js version its CI actually uses for tests.
    """
    # Priority 1: reusable test workflow's nodeVersion input default.
    for wf in REUSABLE_WORKFLOW_PATHS:
        content = get_file_content(repo_path, commit_hash, wf)
        if not content:
            continue
        default = _extract_workflow_call_default(str(content))
        if default:
            version = _normalise(default)
            if version:
                return version

    # Priority 2: PR / master workflows — coverage guard, then unambiguous literal.
    for wf in PR_WORKFLOW_PATHS:
        content = get_file_content(repo_path, commit_hash, wf)
        if not content:
            continue
        content = str(content)

        coverage_version = _extract_coverage_matrix_version(content)
        if coverage_version:
            version = _normalise(coverage_version)
            if version:
                return version

        literals = _extract_literal_node_versions(content)
        distinct = sorted(
            set(literals), key=lambda v: int(_normalise(v) or 0)
        )
        if not distinct:
            continue
        # A single literal is unambiguous. For a matrix (e.g. [14.x, 16.x])
        # pick the highest tested major: it is the newest version the project
        # itself validates against and avoids resolving to a pre-OpenSSL-3
        # release that violates engines.
        chosen = distinct[-1]
        version = _normalise(chosen)
        if version:
            return version

    return None