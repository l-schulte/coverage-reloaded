import sys
from datetime import datetime
from pathlib import Path

import pytest

# Add project root to path
root_path = Path(__file__).parent.parent
sys.path.insert(0, str(root_path))

from src.project_metadata.node.strategies import github_actions


REUSABLE_WORKFLOW = """\
name: Reusable units test workflow

on:
  workflow_call:
    inputs:
      ref:
        required: false
        type: string
        default: master
      nodeVersion:
        description: Version of node to use.
        required: false
        type: string
        default: 20.x
"""

PR_WORKFLOW_MATRIX = """\
jobs:
  test:
    strategy:
      matrix:
        node-version: [14.x, 16.x]
    steps:
      - uses: actions/setup-node@v3
        with:
          node-version: ${{ matrix.node-version }}
"""

PR_WORKFLOW_LITERAL = """\
jobs:
  test:
    steps:
      - uses: actions/setup-node@v3
        with:
          node-version: 16.x
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.nodeVersion }}
"""

MASTER_WORKFLOW_COVERAGE = """\
jobs:
  test:
    strategy:
      matrix:
        node-version: [20.x, 22.x, 24.3.x]
    uses: ./.github/workflows/units-tests-reusable.yml
    with:
      nodeVersion: ${{ matrix.node-version }}
      collectCoverage: ${{ matrix.node-version == '22.x' }}
"""


class TestExtractWorkflowCallDefault:
    def test_reads_default_despite_yaml_on_key(self):
        # PyYAML parses the `on:` key as boolean True — must still work.
        assert github_actions._extract_workflow_call_default(REUSABLE_WORKFLOW) == "20.x"

    def test_empty_default_returns_none(self):
        content = REUSABLE_WORKFLOW.replace("default: 20.x", "default: ''")
        assert github_actions._extract_workflow_call_default(content) is None

    def test_invalid_yaml_returns_none(self):
        assert github_actions._extract_workflow_call_default("on: [unclosed") is None


class TestExtractCoverageMatrixVersion:
    def test_extracts_guarded_version(self):
        assert (
            github_actions._extract_coverage_matrix_version(MASTER_WORKFLOW_COVERAGE)
            == "22.x"
        )

    def test_none_without_guard(self):
        assert github_actions._extract_coverage_matrix_version(PR_WORKFLOW_MATRIX) is None


class TestExtractLiteralNodeVersions:
    def test_single_literal_ignores_expressions(self):
        versions = github_actions._extract_literal_node_versions(PR_WORKFLOW_LITERAL)
        assert versions == ["16.x"]

    def test_matrix_list_is_captured_fully(self):
        versions = github_actions._extract_literal_node_versions(PR_WORKFLOW_MATRIX)
        assert versions == ["14.x", "16.x"]


class TestNormalise:
    @pytest.mark.parametrize(
        "token,expected",
        [
            ("16.x", "16"),
            ("'22.x'", "22"),
            ("20", "20"),
            ("22.4", "22"),
        ],
    )
    def test_normalise(self, token, expected):
        assert github_actions._normalise(token) == expected


class TestGetNodeVersion:
    def _patch(self, monkeypatch, files: dict):
        def fake_get_file_content(repo_path, commit_hash, file_path):
            return files.get(file_path)

        monkeypatch.setattr(
            github_actions, "get_file_content", fake_get_file_content
        )

    def test_reusable_workflow_default_wins(self, monkeypatch):
        self._patch(
            monkeypatch,
            {
                ".github/workflows/units-tests-reusable.yml": REUSABLE_WORKFLOW,
                ".github/workflows/ci-pull-requests.yml": PR_WORKFLOW_LITERAL,
            },
        )
        assert github_actions.get_node_version("repo", "abc") == "20"

    def test_matrix_without_coverage_picks_highest(self, monkeypatch):
        self._patch(
            monkeypatch,
            {".github/workflows/ci-pull-requests.yml": PR_WORKFLOW_MATRIX},
        )
        assert github_actions.get_node_version("repo", "abc") == "16"

    def test_coverage_guard_wins_over_matrix(self, monkeypatch):
        self._patch(
            monkeypatch,
            {".github/workflows/ci-master.yml": MASTER_WORKFLOW_COVERAGE},
        )
        assert github_actions.get_node_version("repo", "abc") == "22"

    def test_no_workflows_returns_none(self, monkeypatch):
        self._patch(monkeypatch, {})
        assert github_actions.get_node_version("repo", "abc") is None

    def test_legacy_matrix_workflow_returns_none(self, monkeypatch):
        # tests.yml (legacy) is not scanned, so early-era repos fall through.
        self._patch(
            monkeypatch,
            {
                ".github/workflows/tests.yml": PR_WORKFLOW_MATRIX,
            },
        )
        assert github_actions.get_node_version("repo", "abc") is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
