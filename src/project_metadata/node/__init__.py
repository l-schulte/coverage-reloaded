from datetime import datetime
import json

NODE_RELEASES_PATH = "src/project_metadata/node/data/node_releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def get_node_releases(lts_only: bool = True) -> dict[str, dict[str, str]]:
    """
    Retrieves the Node.js releases from the data file, optionally filtering for LTS versions only.
    """
    if lts_only:
        return {key: value for key, value in NODE_RELEASES.items() if value.get("lts")}
    return NODE_RELEASES
