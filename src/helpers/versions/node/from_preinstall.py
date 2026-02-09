from helpers.versions.helper import get_file_content
from helpers.versions.node.parse_version import parse_node_version


def get_node_version(
    repo_path: str, revision: str, preinstall_path: str = "build/npm/preinstall.js"
) -> str | None:
    """
    Retrieves the Node.js version specified in the build/npm/preinstall.js file at a given revision.
    """

    content = get_file_content(repo_path, revision, preinstall_path)
    if content:
        node_line = [
            line
            for line in content.splitlines()
            if "Please use node.js version" in line
        ]
        if not node_line:
            return None
        content = node_line[0].split(maxsplit=1)[1]
        version = parse_node_version(content)
        if version:
            return version
    return None
