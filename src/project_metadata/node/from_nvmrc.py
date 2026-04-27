from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)


def get_node_version(
    repo_path: str, revision: str, nvmrc_path: str = ".nvmrc"
) -> str | None:
    """
    Retrieves the Node.js version specified in the .nvmrc file at a given revision.
    """

    content = get_file_content(repo_path, revision, nvmrc_path)
    if content:
        version = find_matching_version_from_version_string(
            str(content), use_artificial_minor_version=True
        )
        if version:
            return version
    return None
