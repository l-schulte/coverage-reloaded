import json
import re

from src.helpers.versions.helper import version_satisfies


NODE_RELEASES_PATH = "src/helpers/versions/node/data/node_releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def parse_node_version(version_string: str, use_first: bool = False) -> str | None:
    """
    Parses a Node.js version string to extract the version.

    Parameters:
    - version_string: The version string to parse.
    - use_first: If True, returns the first matching version instead of the last.
    """

    # Check if range_str is single concrete version -> return as-is
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return version_string

    last_ok = None
    for major in NODE_RELEASES.keys():
        major = major.removeprefix("v")
        try:
            if version_satisfies(major, version_string):
                last_ok = major

                if use_first:
                    return str(major)

        except Exception:
            raise ValueError(
                f"npm satisfies check failed for version '{major}' and range '{version_string}'"
            )

    return str(last_ok)
