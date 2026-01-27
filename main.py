import argparse
from datetime import datetime, timezone
import json

import collect_commits
import collect_coverage


def get_defaults_from_config():
    CONFIG = json.load(open("config.json"))
    defaults = {
        "start_date": CONFIG.get("startdate", "1970-01-01"),
        "end_date": CONFIG.get("enddate", "2100-01-01"),
        "max_workers": CONFIG.get("max_workers", 4),
    }
    return defaults


def parse_args():
    defaults = get_defaults_from_config()

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
        default=defaults["start_date"],
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=defaults["end_date"],
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="./outputs/",
        help="Path to the output directory.",
    )
    parser.add_argument(
        "--max-workers",
        type=int,
        default=defaults["max_workers"],
        help="Maximum number of worker threads to use.",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    start_date = datetime.fromisoformat(args.start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(args.end_date).replace(tzinfo=timezone.utc)

    print(f"project: {args.project}")
    print(f"start_date: {args.start_date}")
    print(f"end_date: {args.end_date}")
    print(f"output: {args.output}")
    print(f"max_workers: {args.max_workers}")

    collect_commits.execute(args.project, start_date, end_date)
    collect_coverage.execute(args.project, args.max_workers)


if __name__ == "__main__":
    main()
