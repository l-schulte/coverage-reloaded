import json
import re

from src.helpers.helper import version_satisfies


NODE_RELEASES_PATH = "src/helpers/node/data/node_releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def sanitize_node_version(version: str) -> str:
    """
    Sanitizes the Node.js version string by removing any prefixes.
    Current cases:
    - "v14.17.0" becomes "14.17.0"
    """

    version = version.strip().removeprefix("v")

    return version.strip()


def parse_node_version(
    version_string: str,
    use_first: bool = False,
    use_artificial_minor_version: bool = True,
) -> str | None:
    """
    Parses a Node.js version string to extract the version.

    Parameters:
    - version_string: The version string to parse.
    - use_first: If True, returns the first matching version instead of the last.
    - use_artificial_minor_version: If True, we upgrade each node release version to an artificially high minor version.
                                    This is usefull because the containers download the latest version anyways.
    """
    version_string = sanitize_node_version(version_string)

    # Check if range_str is single concrete version -> return as-is
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return version_string

    last_ok = None
    for major in NODE_RELEASES.keys():
        major = major.removeprefix("v")

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
