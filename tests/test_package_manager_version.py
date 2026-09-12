import sys
from pathlib import Path

import pytest

# Add project root to path
root_path = Path(__file__).parent.parent
sys.path.insert(0, str(root_path))

from src.project_metadata.package_manager.from_package_json import (
    get_package_manager_version,
)


class TestGetPackageManagerVersion:
    def _patch(self, monkeypatch, package_json):
        def fake_get_file_json_content(repo_path, commit_hash, file_path):
            return package_json

        monkeypatch.setattr(
            "src.project_metadata.package_manager.from_package_json.get_file_json_content",
            fake_get_file_json_content,
        )

    def test_package_manager_wins_over_engines_range(self, monkeypatch):
        # engines gives a truncated two-part version (`8.1`); the concrete
        # packageManager pin (`8.1.0`) must win so corepack can resolve it.
        self._patch(
            monkeypatch,
            {
                "packageManager": "pnpm@8.1.0",
                "engines": {"pnpm": ">=8.1"},
            },
        )
        assert get_package_manager_version("pnpm", "repo", "abc") == "pnpm@8.1.0"

    def test_engines_used_when_no_package_manager(self, monkeypatch):
        self._patch(monkeypatch, {"engines": {"pnpm": ">=7.18"}})
        assert get_package_manager_version("pnpm", "repo", "abc") == "pnpm@7.18"

    def test_volta_used_when_no_package_manager(self, monkeypatch):
        self._patch(monkeypatch, {"volta": {"npm": "8.5.0"}})
        assert get_package_manager_version("npm", "repo", "abc") == "npm@8.5.0"

    def test_package_manager_ignored_for_other_pm(self, monkeypatch):
        # A yarn repo pins pnpm@8.1.0; asking for yarn must not use it.
        self._patch(
            monkeypatch,
            {"packageManager": "pnpm@8.1.0", "engines": {"yarn": ">=1.22"}},
        )
        assert get_package_manager_version("yarn", "repo", "abc") == "yarn@1.22"

    def test_build_metadata_stripped(self, monkeypatch):
        self._patch(monkeypatch, {"packageManager": "pnpm@8.1.0+sha256.abc"})
        assert get_package_manager_version("pnpm", "repo", "abc") == "pnpm@8.1.0"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])