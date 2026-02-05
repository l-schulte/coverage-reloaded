from helpers.versions.helper import get_file_content
from helpers.versions.node.parse_version import parse_node_version


def get_node_version(
    repo_path: str, revision: str, tool_version_path: str = ".tool-version"
) -> str | None:
    """
    Retrieves the Node.js version specified in the .tool-version file at a given revision.
    """

    content = get_file_content(repo_path, revision, tool_version_path)
    if content:
        node_line = [line for line in content.splitlines() if line.startswith("node")]
        if not node_line:
            return None
        content = node_line[0].split(maxsplit=1)[1]
        version = parse_node_version(content)
        if version:
            return version
    return None
