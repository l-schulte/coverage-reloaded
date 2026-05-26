from datetime import datetime
import json
import re
import semantic_version

from src.project_metadata.helper import version_satisfies
from src.project_metadata.node import get_node_releases


def validate_node_version(version_string: str) -> bool:
    """
    Validates if a given version string is a valid Node.js version or range.
    """

    version_string = sanitize_node_version(version_string)

    # Check if version_string is a single concrete version
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return True

    # Check if version_string is a valid range
    try:
        semantic_version.NpmSpec(version_string)
        return True
    except ValueError:
        return False


def sanitize_node_version(version: str) -> str:
    """
    Sanitizes the Node.js version string by removing any prefixes.
    Current cases:
    - "v14.17.0" becomes "14.17.0"
    - ">= 11.7.1" becomes ">=11.7.1" (removes space between operator and version)
    """

    version = version.strip().removeprefix("v")

    # Remove spaces between version operators and the version number
    # e.g. ">= 11.7.1" -> ">=11.7.1", "~ 1.2" -> "~1.2", "^ 1.2.3" -> "^1.2.3"
    version = re.sub(r"([<>=~^])\s+(\d)", r"\1\2", version)

    return version.strip()


def find_matching_version_from_version_string(
    version_string: str,
    use_first: bool = False,
    use_artificial_minor_version: bool = True,
    before_date: datetime | None = None,
) -> str | None:
    """
    Parses a Node.js version string to extract the version.

    Parameters:
    - version_string: The version string to parse.
    - use_first: If True, returns the first matching version instead of the last.
    - use_artificial_minor_version: If True, we upgrade each node release version to an artificially high minor version.
                                    This is usefull because the containers download the latest version anyways.
    - before_date: If provided, only considers versions released before this date.
    """
    version_string = sanitize_node_version(version_string)

    if not validate_node_version(version_string):
        return None

    # Check if range_str is single concrete version -> return as-is
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return version_string

    last_ok = None
    for major, meta_data in get_node_releases(lts_only=False).items():
        version_release_date = datetime.strptime(meta_data["start"], "%Y-%m-%d")
        if before_date and version_release_date.timestamp() > before_date.timestamp():
            continue

        major: str = major.removeprefix("v")

        version = major
        if use_artificial_minor_version:
            version = f"{major}.9999"

        try:
            if version_satisfies(version, version_string):
                last_ok = major

                if use_first:
                    return str(major)

        except Exception:
            raise ValueError(
                f"npm satisfies check failed for version '{version}' and range '{version_string}'"
            )

    return str(last_ok)
