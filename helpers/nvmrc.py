from helpers.helper import get_file_at_commit, parse_version_string


def __get_nvmrc_content(
    repo_path: str, revision: str, nvmrc_path: str = ".nvmrc"
) -> str | None:
    """
    Reads the content of the .nvmrc file if it exists.
    """

    try:
        content = get_file_at_commit(repo_path, revision, nvmrc_path)
        return content.strip() if content else None
    except Exception:
        return None


def get_node_version(
    repo_path: str, revision: str, nvmrc_path: str = ".nvmrc"
) -> str | None:
    """
    Retrieves the Node.js version specified in the .nvmrc file at a given revision.
    """

    content = __get_nvmrc_content(repo_path, revision, nvmrc_path)
    if content:
        version = parse_version_string(content)
        if version:
            return version
    return None
