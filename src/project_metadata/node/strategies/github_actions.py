"""
GitHub Actions strategy for Node.js version resolution.

Extracts the Node.js version used by the project's own GitHub Actions CI at a
given commit.  This is the most faithful source for projects whose CI runs a
specific Node major that ``engines.node`` ranges (``>=``) do not pin down
(e.g. n8n runs the *lowest* supported major while ``>=20.15`` would resolve to
the highest available LTS).

Sources (tried in priority order):
1. Reusable test workflow's ``on.workflow_call.inputs.nodeVersion.default`` (e.g. ``20.x``).
2. Coverage guard (``collectCoverage: ${{ matrix.node-version == 'X' }}``).
3. CI test workflows (e.g. ``ci.yml``, ``test.yml``, ``main.yml``) — highest tested
   LTS major (falling back to highest tested non-LTS major).
"""

import re
from datetime import datetime
from typing import Optional

import yaml

from src.project_metadata.helper import get_file_content, resolve_wildcard_at_commit
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)
from src.project_metadata.node.releases_data import get_node_releases

REUSABLE_WORKFLOW_PATHS = [
    ".github/workflows/units-tests-reusable.yml",
    ".github/workflows/test-unit-reusable.yml",
]

CI_WORKFLOW_PATHS = [
    ".github/workflows/ci-pull-requests.yml",
    ".github/workflows/ci-master.yml",
    ".github/workflows/ci.yml",
    ".github/workflows/ci.yaml",
    ".github/workflows/test.yml",
    ".github/workflows/test.yaml",
    ".github/workflows/tests.yml",
    ".github/workflows/tests.yaml",
    ".github/workflows/main.yml",
    ".github/workflows/main.yaml",
    ".github/workflows/build.yml",
    ".github/workflows/build.yaml",
]

NON_CI_NAME_PATTERNS = (
    "release",
    "triage",
    "lock",
    "label",
    "publish",
    "stale",
    "dependabot",
    "codeql",
)

# Captures a literal node-version value, e.g.:
#   node-version: 16.x
#   node-version: '22.x'
#   node-version: [16.x]
#   node-version: [14.x, 16.x]
#   node-version: ${{ matrix.node-version }}   (expression -> skipped)
RE_NODE_VERSION_VALUE = re.compile(r"node-version:\s*(\[[^\]]*\]|[^\s#]+)")

# Captures the version singled out by a collectCoverage guard:
#   collectCoverage: ${{ matrix.node-version == '20.x' }}
RE_COVERAGE_GUARD = re.compile(
    r"(?:collectCoverage|coverage)[^\n]*node(?:-version)?\s*==\s*['\"]?([\d.]+x?)['\"]?",
    re.IGNORECASE,
)

# Matches plain CI version tokens: 16, 16.x, 22.4, 22.4.1, '22.x' — group(1) is
# the whole token, including any minor/patch components.
RE_VERSION_TOKEN = re.compile(r"^\s*['\"]?(\d+(?:\.(?:x|\d+)){0,2})['\"]?\s*$")

RE_MAJOR = re.compile(r"^\d+")


def _major(version_str: str) -> Optional[str]:
    """Return only the Node major of a CI token (``22.4.1`` -> ``22``).

    Used for the LTS-membership test, which must compare majors —
    ``node_releases.json`` is keyed by major only (``v22``).
    """
    m = RE_MAJOR.match(version_str.strip().lstrip("'\""))
    return m.group(0) if m else None


def _version_key(version_str: str) -> tuple[int, tuple[int, ...]]:
    """Total ordering for CI tokens: by major, then by version specificity.

    ``22`` < ``22.5`` < ``22.11``. A plain ``sorted(..., key=int)`` is not enough
    once minors are preserved, and leaving ties to ``set`` ordering makes the
    chosen token depend on hash randomisation.
    """
    major = _major(version_str)
    parts: list[int] = []
    for chunk in version_str.strip().lstrip("'\"").split("."):
        if chunk.isdigit():
            parts.append(int(chunk))
        else:
            break
    return (int(major) if major else -1, tuple(parts))


def _normalise(version_str: str) -> Optional[str]:
    """Map a CI version token to a Node version, keeping its specificity.

    ``22.4.1`` -> ``22.4.1``, ``22.4`` -> ``22.4``, ``22.x`` / ``22`` -> ``22``.

    The minor/patch is deliberately preserved: a workflow that pins
    ``node-version: 22.10`` names an exact Node release, and truncating it to
    ``22`` makes the container install the newest 22.x instead, which can be
    years ahead of the commit. ``project_metadata`` decides whether to keep the
    exact version (``use_exact_node_version``) or truncate to the major.
    """
    m = RE_VERSION_TOKEN.match(version_str.strip())
    if m:
        token = m.group(1)
        # `22.x` is just the major: drop trailing `.x` placeholders.
        while token.endswith(".x"):
            token = token[: -len(".x")]
        return token or None
    # Quoted / range forms such as `"18.20.0"` or `>=14` — strip the quotes the
    # regex above tolerates but the parser below does not.
    version = find_matching_version_from_version_string(version_str.strip().strip("'\""))
    return version or None


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
    for k in ("nodeVersion", "node-version", "node"):
        node_version_input = inputs.get(k)
        if isinstance(node_version_input, dict):
            default = node_version_input.get("default")
            if isinstance(default, str) and default.strip():
                return default.strip()
    return None


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
    return [v for v in versions if v != "*"]


def _get_workflow_paths(repo_path: str, commit_hash: str) -> list[str]:
    """Return candidate CI workflow paths to inspect."""
    paths = list(CI_WORKFLOW_PATHS)
    try:
        discovered = resolve_wildcard_at_commit(
            repo_path, commit_hash, ".github/workflows/*"
        )
        for p in discovered:
            if (p.endswith(".yml") or p.endswith(".yaml")) and p not in paths:
                base = p.rsplit("/", 1)[-1].lower()
                if not any(pattern in base for pattern in NON_CI_NAME_PATTERNS):
                    paths.append(p)
    except Exception:
        pass
    return paths


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

    # Priority 2: CI workflows — coverage guard, then highest tested LTS major.
    lts_majors = set(get_node_releases(lts_only=True).keys())
    for wf in _get_workflow_paths(repo_path, commit_hash):
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
        # Rank on the full version (major, then specificity) and test LTS
        # membership on the *major* — `node_releases.json` is keyed by major.
        distinct = sorted(set(literals), key=_version_key)
        if not distinct:
            continue

        # Prefer the highest tested LTS release (even major). Fall back to highest
        # tested non-LTS release if no LTS release is present in the workflow.
        lts_candidates = [
            v for v in distinct if f"v{_major(v)}" in lts_majors
        ]
        chosen = lts_candidates[-1] if lts_candidates else distinct[-1]
        version = _normalise(chosen)
        if version:
            return version

    return None
