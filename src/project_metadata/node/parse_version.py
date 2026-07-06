import logging
from datetime import datetime
import json
import re
import semantic_version

from src.project_metadata.helper import version_satisfies
from src.project_metadata.node.releases_data import get_node_releases

logger = logging.getLogger(__name__)


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
    release_cutoff: datetime | None = None,
) -> str | None:
    """
    Parses a Node.js version string to extract the version.

    Parameters:
    - version_string: The version string to parse.
    - use_first: If True, returns the first matching version instead of the last.
    - use_artificial_minor_version: If True, we upgrade each node release version to an artificially high minor version.
                                    This is usefull because the containers download the latest version anyways.
    - release_cutoff: Only consider Node versions whose release date is before this date.
    """
    version_string = sanitize_node_version(version_string)

    if not validate_node_version(version_string):
        return None

    # Check if range_str is single concrete version -> return as-is
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return version_string

    last_ok = None
    for major, meta_data in get_node_releases(lts_only=True).items():
        major: str = major.removeprefix("v")

        version = major
        if use_artificial_minor_version:
            version = f"{major}.9999"

        try:
            satisfies = version_satisfies(version, version_string)
        except Exception:
            raise ValueError(
                f"npm satisfies check failed for version '{version}' and range '{version_string}'"
            )

        if not satisfies:
            continue

        # The first (minimum) version that satisfies the spec is always
        # accepted — the cutoff caps the upper end but must not eliminate
        # the floor that the project explicitly requires.
        if last_ok is None:
            last_ok = major
            if use_first:
                return str(major)
            continue

        # For versions above the minimum, the cutoff prevents picking a
        # version that hadn't been released yet at the commit's time.
        version_release_date = datetime.strptime(meta_data["start"], "%Y-%m-%d")
        if (
            release_cutoff
            and version_release_date.timestamp() > release_cutoff.timestamp()
        ):
            continue

        last_ok = major

    return str(last_ok) if last_ok is not None else None


def resolve_skip_node_version(
    node_version: str,
    skip_list: list[int],
    lts_only: bool = True,
) -> str:
    """If *node_version* (a major version string) is in *skip_list*, bump down
    to the nearest available LTS version not in the list.

    Returns the (possibly bumped) version string.
    """
    node_int = int(node_version)
    if node_int not in skip_list:
        return node_version

    available = sorted(
        int(k.removeprefix("v")) for k in get_node_releases(lts_only=lts_only).keys()
    )
    candidate = node_int - 1
    while candidate >= min(available) and (
        candidate in skip_list or candidate not in available
    ):
        candidate -= 1
        logger.warning(
            f"Node.js version {node_version} is in the skip list {skip_list}. "
            f"Bumping down to {candidate}."
        )
        return str(candidate)
    else:
        logger.warning(
            f"Node.js version {node_version} is in the skip list {skip_list}, "
            f"but no lower LTS version is available. Keeping version {node_version}."
        )
        return node_version
