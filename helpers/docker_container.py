def get_container_tag(node_version: str | None) -> str | None:
    """
    Given a Node.js version string, returns the appropriate Docker container tag.
    """

    if not node_version:
        return None

    version_parts = node_version.split(".")
    major_version = int(version_parts[0])
    while version_parts[-1] == "0" and len(version_parts) > 1:
        version_parts = version_parts[:-1]
    formatted_version = (
        ".".join(version_parts[:2]) if len(version_parts) > 1 else version_parts[0]
    )

    if major_version < 10:
        formatted_version = "10"

    if major_version <= 15:
        return f"node:{formatted_version}-buster"
    else:
        return f"node:{formatted_version}-bullseye"
