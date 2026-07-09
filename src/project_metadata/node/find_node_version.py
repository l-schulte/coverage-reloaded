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
    node_version_lts_offset_months: int = 12,
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
        node_version_lts_offset_months: Additional offset (in months) applied
            inside the releases.py fallback strategy.  A Node LTS release must
            have been out for at least this many months past the cutoff to be
            selected.  Default 12 (original behaviour).

    Returns:
        Tuple of ``(version, source_name)`` where *source_name* identifies
        which strategy succeeded, or ``(None, None)`` if no strategy matched.
    """

    release_cutoff = committer_date - relativedelta(months=node_version_delay_months)
    disabled = set(disabled_strategies or [])

    extra_kwargs = {
        "lts_offset_months": node_version_lts_offset_months,  # passed to releases.py strategy
    }

    for source_name, strategy in STRATEGIES:
        if source_name in disabled:
            continue
        node_version = strategy(
            repo_path,
            commit_hash,
            release_cutoff,
            use_first,
            **extra_kwargs,
        )
        if node_version:
            return node_version, source_name

    return None, None
