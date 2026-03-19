import datetime
import json

from src.project_metadata.node.parse_version import parse_node_version

NODE_RELEASES_PATH = "src/project_metadata/node/data/node_releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def get_node_version(
    timestamp: float,
    offset_months: int = 12,
    skip_versions: list[str] = [],
) -> str:
    """
    Retrieves the latest Node.js version applicable at a given timestamp plus a offset (defaut 12 months).
    Node version dates are stored in helpers/node/data/node_releases.json.

    Args:
        timestamp (float): The timestamp for which to determine the Node.js version.
        offset_months (int, optional): The number of months to offset the release date. Defaults to 12.
        skip_versions (list[str], optional): List of Node.js versions to skip. Defaults to [].
    """

    def version_was_available(
        release_date: str, timestamp: float, offset_months: int
    ) -> bool:
        release_timestamp = datetime.datetime.strptime(
            release_date, "%Y-%m-%d"
        ).timestamp()
        return (release_timestamp + offset_months * 30 * 24 * 60 * 60) < timestamp

    node_releases = [
        (str(release).removeprefix("v"), data)
        for release, data in NODE_RELEASES.items()
    ]

    latest_node_releases = [
        release
        for release, data in node_releases
        if (
            release not in skip_versions
            and version_was_available(data["start"], timestamp, offset_months)
        )
    ]
    latest_node_release = parse_node_version(latest_node_releases[-1].replace("v", ""))

    if not latest_node_release:
        raise ValueError("No valid Node.js version found for the given timestamp.")

    return latest_node_release
