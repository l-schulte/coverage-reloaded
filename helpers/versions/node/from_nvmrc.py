from helpers.versions.helper import parse_version_string, get_file_content


def get_node_version(
    repo_path: str, revision: str, nvmrc_path: str = ".nvmrc"
) -> str | None:
    """
    Retrieves the Node.js version specified in the .nvmrc file at a given revision.
    """

    content = get_file_content(repo_path, revision, nvmrc_path)
    if content:
        version = parse_version_string(content)
        if version:
            return version
    return None
