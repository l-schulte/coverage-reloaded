import argparse
from datetime import datetime, timezone
import json
import logging

import collect_commits
import collect_coverage

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_defaults_from_config():
    CONFIG = json.load(open("config.json"))
    defaults = {
        "start_date": CONFIG.get("start_date", "1970-01-01"),
        "end_date": CONFIG.get("end_date", "2100-01-01"),
        "max_workers": CONFIG.get("max_workers", 4),
    }
    return defaults


DEFAULTS = get_defaults_from_config()


def parse_args():

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
        default=DEFAULTS["start_date"],
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=DEFAULTS["end_date"],
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=DEFAULTS["max_workers"],
        help="Maximum number of worker threads to use.",
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
        choices=["full", "commits-only", "coverage-only"],
        default="full",
        help="Mode of operation:\n - 'full' to collect commits and coverage\n - 'commits-only' to collect only commits\n - 'coverage-only' to collect only coverage.",
    )

    return parser.parse_args()


def execute(
    project,
    mode,
    start_date=DEFAULTS["start_date"],
    end_date=DEFAULTS["end_date"],
    max_workers=DEFAULTS["max_workers"],
    max_commits=None,
):
    start_date = datetime.fromisoformat(start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(end_date).replace(tzinfo=timezone.utc)

    logger.info(f"Starting in mode: {mode}")
    logger.info(f"Project: {project}")
    logger.info(f"Date range: {start_date} to {end_date}")

    if mode in ["full", "commits-only"]:
        collect_commits.execute(project, start_date, end_date)
    if mode in ["full", "coverage-only"]:
        collect_coverage.execute(project, max_workers, max_commits)


def main():
    args = parse_args()

    execute(
        args.project,
        args.mode,
        args.start_date,
        args.end_date,
        args.max_workers,
        args.max_commits,
    )


if __name__ == "__main__":
    main()
