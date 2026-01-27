import pydriller

from helpers.versions.node import from_docker as docker
from helpers.versions.node import from_package_json as package_json
from helpers.versions.node import from_nvmrc as nvmrc
from helpers.versions.node import from_preinstall as preinstall
from helpers.versions.node import from_tool_version as tool_version
from helpers.versions.node import from_releases


def get_node_version(
    commit: pydriller.Commit, repo_path: str
) -> tuple[str, str | None]:
    """
    Attempts to retrieve the Node.js version for a given commit hash.
    1. Check .nvmrc
    2. Check package.json
    3. Check dockerfiles
    """

    # 1. Check .nvmrc
    node_version = nvmrc.get_node_version(repo_path, commit.hash, nvmrc_path=".nvmrc")
    if node_version:
        return node_version, ".nvmrc"

    # 2. Check package.json
    node_version = package_json.get_node_version(
        repo_path, commit.hash, packagejson_path="package.json"
    )
    if node_version:
        return node_version, "package.json"

    # 3. Check .tool-version
    node_version = tool_version.get_node_version(
        repo_path, commit.hash, tool_version_path=".tool-version"
    )
    if node_version:
        return node_version, ".tool-version"

    # 4. Check dockerfiles
    node_version = docker.get_node_version(
        repo_path, commit.hash, dockerfile_paths=["Dockerfile", "docker/Dockerfile"]
    )
    if node_version:
        return node_version, "Dockerfile"

    # 5. Check build/npm/preinstall.js
    node_version = preinstall.get_node_version(
        repo_path, commit.hash, preinstall_path="build/npm/preinstall.js"
    )
    if node_version:
        return node_version, "build/npm/preinstall.js"

    # Last: Check node_releases.json based on commit date
    timestamp = int(commit.committer_date.timestamp())
    node_version = from_releases.get_node_version(
        timestamp, major_only=True, offset_months=12
    )

    return node_version, "node_releases.json (12 months offset)"
