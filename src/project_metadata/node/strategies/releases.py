import datetime
from typing import Optional

from src.project_metadata.node.releases_data import get_node_releases
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
    **kwargs,
) -> Optional[str]:
    """
    Fallback: pick the latest LTS Node version that was released at least
    ``lts_offset_months`` months before the cutoff date.

    Args:
        repo_path: Path to the local git repository (unused, for protocol compat).
        commit_hash: Commit hash (unused, for protocol compat).
        release_cutoff: Date to use as reference for version availability.
        use_first: If True, return the earliest matching version instead of latest.
        lts_offset_months: Number of months an LTS release must have been
            available past the cutoff to be considered.  Default 12 matches
            the original behaviour.
    """
    lts_offset_months = kwargs.get("lts_offset_months", 12)
    if release_cutoff is None:
        return None

    timestamp = release_cutoff.timestamp()
    offset_months = lts_offset_months

    def version_was_available(release_date: str, ts: float, offset: int) -> bool:
        release_ts = datetime.datetime.strptime(release_date, "%Y-%m-%d").timestamp()
        return (release_ts + offset * 30 * 24 * 60 * 60) < ts

    node_releases = [
        (str(release).removeprefix("v"), data)
        for release, data in get_node_releases(lts_only=True).items()
    ]

    available = [
        release
        for release, data in node_releases
        if version_was_available(
            data.get("lts", data["start"]), timestamp, offset_months
        )
    ]

    if not available:
        return None

    idx = 0 if use_first else -1
    latest = find_matching_version_from_version_string(available[idx])
    return latest
