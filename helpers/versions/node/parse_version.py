import json
from semantic_version import Version, NpmSpec

NODE_RELEASES_PATH = "helpers/versions/node/data/releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def __max_major_for_range(range_str: str) -> int | None:
    spec = NpmSpec.parse(range_str)
    last_ok = None
    for major in NODE_RELEASES.keys():
        version = Version.coerce(major.replace("v", ""))
        if version in spec:  # npm-style satisfies check
            last_ok = version
    return last_ok


def parse_node_version(version_string: str, major_only: bool = True) -> str | None:
    """
    Parses a Node.js version string to extract the version.
    """

    return str(__max_major_for_range(version_string))
