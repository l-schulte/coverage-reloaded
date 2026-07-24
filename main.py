import argparse
from datetime import datetime, timezone
import logging

from src import collect_commits, collect_coverage, collect_single_commit
from src.config import get_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_args():
    cfg = get_config()

    parser = argparse.ArgumentParser(
        description="Collect repository coverage through a projects commit history."
    )
    parser.add_argument(
        "--project",
        type=str,
        required=True,
        help="Project name. Must be in config.json",
    )
    parser.add_argument(
        "--start-date",
        type=str,
        default=cfg.start_date,
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=cfg.end_date,
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=None,
        help="Maximum number of worker threads to use. Defaults to config.json max_workers.",
    )
    parser.add_argument(
        "--max-commits",
        type=int,
        required=False,
        help="Maximum number of commits to process.",
    )
    parser.add_argument(
        "--mode",
        type=str,
        choices=[
            "full",
            "commits-only",
            "coverage-only",
            "single-commit",
            "retry-failed",
        ],
        default="full",
        help="Mode of operation:\n - 'full' to collect commits and coverage\n - 'commits-only' to collect only commits\n - 'coverage-only' to collect only coverage\n - 'single-commit' to collect data for a single commit\n - 'retry-failed' to re-run only previously failed commits.",
    )
    parser.add_argument(
        "--commit-hash",
        type=str,
        required=False,
        help="Commit hash to process when using 'single-commit' mode.",
    )
    parser.add_argument(
        "--base-path",
        type=str,
        required=False,
        help="Base path for project repositories and outputs.",
    )

    return parser.parse_args()


def execute(
    project,
    mode,
    start_date=None,
    end_date=None,
    max_workers=None,
    max_commits=None,
    commit_hash=None,
    base_path=None,
):
    cfg = get_config()
    start_date = start_date or cfg.start_date
    end_date = end_date or cfg.end_date
    max_workers = max_workers or cfg.max_workers
    start_date = datetime.fromisoformat(start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(end_date).replace(tzinfo=timezone.utc)

    logger.info(f"Starting in mode: {mode}")
    logger.info(f"Project: {project}")
    logger.info(f"Date range: {start_date} to {end_date}")

    if mode in ["full", "commits-only"]:
        collect_commits.execute(project, start_date, end_date)
    if mode in ["full", "coverage-only"]:
        collect_coverage.execute(project, max_workers, max_commits)
    if mode == "single-commit":
        if not commit_hash:
            logger.error("Commit hash is required for 'single-commit' mode.")
            return
        collect_single_commit.execute(project, commit_hash, base_path)
    if mode == "retry-failed":
        collect_coverage.execute_failed(project, max_workers, max_commits)


def main():
    args = parse_args()

    if args.project == "all":
        cfg = get_config()
        for project in cfg.projects:
            logger.info(f"Processing project: {project}")
            execute(
                project,
                args.mode,
                args.start_date,
                args.end_date,
                args.max_workers,
                args.max_commits,
                None,  # commit_hash is not applicable for multiple projects
                args.base_path,
            )
    else:
        execute(
            args.project,
            args.mode,
            args.start_date,
            args.end_date,
            args.max_workers,
            args.max_commits,
            args.commit_hash,
            args.base_path,
        )


if __name__ == "__main__":
    main()
