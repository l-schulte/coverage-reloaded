from helpers.helper import get_file_at_commit, parse_version_string


def __get_tool_version_content(
    repo_path: str, revision: str, tool_version_path: str = ".tool-version"
) -> str | None:
    """
    Reads the content of the .tool-version file if it exists.
    """

    try:
        content = get_file_at_commit(repo_path, revision, tool_version_path)
        return content.strip() if content else None
    except Exception:
        return None


def get_node_version(
    repo_path: str, revision: str, tool_version_path: str = ".tool-version"
) -> str | None:
    """
    Retrieves the Node.js version specified in the .tool-version file at a given revision.
    """

    content = __get_tool_version_content(repo_path, revision, tool_version_path)
    if content:
        node_line = [line for line in content.splitlines() if line.startswith("node")]
        if not node_line:
            return None
        content = node_line[0].split(maxsplit=1)[1]
        version = parse_version_string(content)
        if version:
            return version
    return None
