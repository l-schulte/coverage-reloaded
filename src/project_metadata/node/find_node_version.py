from datetime import datetime
from dateutil.relativedelta import relativedelta

from src.project_metadata.node.strategies import STRATEGIES


def find_node_version(
    commit_hash: str,
    committer_date: datetime,
    repo_path: str,
    node_version_delay_months: int = 3,
    disabled_strategies: list[str] | None = None,
    use_first: bool = False,
) -> tuple[str, str | None]:
    """
    Attempts to retrieve the Node.js version for a given commit hash by trying
    each registered strategy in priority order.

    Args:
        commit_hash: The commit hash to inspect.
        committer_date: The committer date of the commit.
        repo_path: Path to the local git repository.
        node_version_delay_months: Minimum months a Node release must have been
            available before the commit date to be considered a valid match
            (stabilisation delay).
        disabled_strategies: Optional set of strategy source names to skip.
            Source names are the first element of each ``STRATEGIES`` tuple
            (e.g. ``"Dockerfile"``, ``".nvmrc"``).
        use_first: If ``True``, returns the first matching Node version from
            the release list instead of the last (most recent) one.

    Returns:
        Tuple of ``(version, source_name)`` where *source_name* identifies
        which strategy succeeded, or ``(None, None)`` if no strategy matched.
    """

    release_cutoff = committer_date - relativedelta(months=node_version_delay_months)
    disabled = set(disabled_strategies or [])

    for source_name, strategy in STRATEGIES:
        if source_name in disabled:
            continue
        node_version = strategy(repo_path, commit_hash, release_cutoff, use_first)
        if node_version:
            return node_version, source_name

    return None, None
