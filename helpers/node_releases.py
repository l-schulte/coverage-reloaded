import datetime
import json

from helpers.helper import parse_version_string

NODE_RELEASES_PATH = "helpers/node_releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def get_node_version(timestamp: int, major_only: bool = False) -> str:
    """
    Retrieves the Node.js version applicable at a given timestamp from node_releases.json.
    """

    def version_was_available(release_date: str, timestamp: int) -> bool:
        return (
            datetime.datetime.strptime(release_date, "%Y-%m-%d").timestamp() < timestamp
        )

    latest_node_releases = [
        release
        for release, data in NODE_RELEASES.items()
        if version_was_available(data["start"], timestamp)
    ]

    latest_node_release = parse_version_string(latest_node_releases[-1], major_only)

    if not latest_node_release:
        raise ValueError("No valid Node.js version found for the given timestamp.")

    return latest_node_release
