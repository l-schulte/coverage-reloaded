from datetime import datetime

from src.project_metadata.node import (
    from_angular,
    from_docker as docker,
    from_pnpm_lock,
)
from src.project_metadata.node import from_package_json as package_json
from src.project_metadata.node import from_nvmrc as nvmrc
from src.project_metadata.node import from_preinstall as preinstall
from src.project_metadata.node import from_tool_version as tool_version
from src.project_metadata.node import from_releases


def find_node_version(
    commit_hash: str, committer_date: datetime, repo_path: str
) -> tuple[str, str | None]:
    """
    Attempts to retrieve the Node.js version for a given commit hash.
    1. Check .nvmrc
    2. Check package.json
    3. Check dockerfiles
    """

    # 1. Check .nvmrc
    node_version = nvmrc.get_node_version(repo_path, commit_hash, nvmrc_path=".nvmrc")
    if node_version:
        return node_version, ".nvmrc"

    # 3. Check package.json
    node_version = package_json.get_node_version(
        repo_path,
        commit_hash,
        packagejson_path="package.json",
        before_date=committer_date,
    )
    if node_version:
        return node_version, "package.json"

    # 2. Check pnpm-lock.yaml
    node_version = from_pnpm_lock.get_node_version(
        repo_path,
        commit_hash,
        pnpm_lock_path="pnpm-lock.yaml",
        before_date=committer_date,
    )
    if node_version:
        return node_version, "pnpm-lock.yaml"

    # 4. Check .tool-version
    node_version = tool_version.get_node_version(
        repo_path, commit_hash, tool_version_path=".tool-version"
    )
    if node_version:
        return node_version, ".tool-version"

    # 5. Check dockerfiles
    node_version = docker.get_node_version(
        repo_path, commit_hash, dockerfile_paths=["Dockerfile", "docker/Dockerfile"]
    )
    if node_version:
        return node_version, "Dockerfile"

    # 6. Check build/npm/preinstall.js
    node_version = preinstall.get_node_version(
        repo_path, commit_hash, preinstall_path="build/npm/preinstall.js"
    )
    if node_version:
        return node_version, "build/npm/preinstall.js"

    # 7. Check Angular compatibility (if applicable)
    node_version = from_angular.get_node_version(repo_path, commit_hash)
    if node_version:
        return node_version, "Angular compatibility"

    # Last: Check node_releases.json based on commit date
    node_version = from_releases.get_node_version(
        committer_date.timestamp(), offset_months=12, lts_only=True
    )

    return node_version, "node_releases.json (LTS, 12 months offset)"
