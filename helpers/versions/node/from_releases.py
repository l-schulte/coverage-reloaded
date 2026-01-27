import datetime
import json

from helpers.versions.helper import parse_version_string

NODE_RELEASES_PATH = "helpers/repo/node/releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def get_node_version(
    timestamp: int, major_only: bool = False, offset_months: int = 12
) -> str:
    """
    Retrieves the latest Node.js version applicable at a given timestamp plus a offset (defaut 12 months).
    Node version dates are stored in helpers/repo/node/releases.json.
    """

    def version_was_available(
        release_date: str, timestamp: int, offset_months: int
    ) -> bool:
        return (
            datetime.datetime.strptime(release_date, "%Y-%m-%d").timestamp()
            + offset_months * 30 * 24 * 60 * 60
            < timestamp
        )

    latest_node_releases = [
        release
        for release, data in NODE_RELEASES.items()
        if version_was_available(data["start"], timestamp, offset_months)
    ]

    latest_node_release = parse_version_string(latest_node_releases[-1], major_only)

    if not latest_node_release:
        raise ValueError("No valid Node.js version found for the given timestamp.")

    return latest_node_release
