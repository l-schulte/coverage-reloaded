import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime, timezone
import logging
import os
import subprocess
import pydriller
import json
import tqdm
import pandas as pd
import numpy as np

from src.project_metadata.project_metadata import extract_project_metadata

CONFIG = json.load(open("config.json"))

logger = logging.getLogger(__name__)


def parse_args():
    parser = argparse.ArgumentParser(description="Process project parameters.")
    parser.add_argument(
        "--project",
        type=str,
        required=False,
        help="Project name. Must be in config.json",
    )
    parser.add_argument(
        "--start-date",
        type=str,
        default=CONFIG.get("startdate", "1970-01-01"),
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=CONFIG.get("enddate", "2100-01-01"),
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    return parser.parse_args()


def get_command_changes(df: pd.DataFrame):
    df_long = df.drop("timestamp", axis=1).melt(
        id_vars=["commit_hash"],
        var_name="script_name",
        value_name="script_definition",
    )

    df_long["script_definition"] = (
        df_long["script_definition"].str.strip().replace("", np.nan)
    )

    return (
        df_long.dropna(subset=["script_definition"])
        .drop_duplicates(subset=["script_name", "script_definition"])
        .sort_values("script_name")
        .reset_index(drop=True)
    )


def execute(project: str, start_date: datetime, end_date: datetime):
    """
    Collects commit data for a given project within a specified date range.

    Args:
        project (str): The name of the project.
        start_date (datetime): The start date for commit collection.
        end_date (datetime): The end date for commit collection.
    """

    logger.info(f"Collecting commits for {project} from {start_date} to {end_date}.")

    project_path = f"projects/{project}"
    project_url = CONFIG["projects"].get(project, {}).get("url", None)
    repo_path = f"{project_path}/repo"

    project_config = CONFIG["projects"].get(project, {})

    os.makedirs(project_path, exist_ok=True)

    if project_url and not os.path.exists(repo_path):
        logger.info(f"Cloning repository for project {project} from {project_url}.")
        subprocess.run(["git", "clone", project_url, repo_path], check=True)

    project_commits_file = f"{project_path}/commits.csv"

    commits = []
    additional_information = []

    # Suppress pydriller logging on info level
    logging.getLogger("pydriller").setLevel(logging.WARNING)

    tasks = [
        {"hash": c.hash, "committer_date": c.committer_date}
        for c in pydriller.Repository(repo_path).traverse_commits()
        if start_date <= c.committer_date < end_date
    ]

    with ProcessPoolExecutor(max_workers=os.cpu_count()) as executor:
        futures = {
            executor.submit(
                extract_project_metadata,
                c["hash"],
                c["committer_date"],
                repo_path,
                project,
                project_config,
            ): c["hash"]
            for c in tasks
        }
        for future in tqdm.tqdm(
            as_completed(futures), total=len(tasks), desc="Processing commits"
        ):
            result = future.result()  # re-raises exceptions from workers
            if not result:
                continue

            commits.append(result["commit"])
            additional_information.append(result["additional"])

    commits.sort(key=lambda c: c["timestamp"])
    additional_information.sort(key=lambda a: a["timestamp"])

    df_additional_info = pd.DataFrame(additional_information)
    df_additional_info.to_csv(f"{project_path}/additional_information.csv", index=False)

    pd.DataFrame(get_command_changes(df_additional_info)).to_csv(
        f"{project_path}/command_changes.csv", index=False
    )

    pd.DataFrame(commits).to_csv(project_commits_file, index=False)
    if os.path.exists(os.path.join(project_path, "commits_postprocess.py")):
        subprocess.run(
            ["python3", "commits_postprocess.py"], cwd=project_path, check=True
        )
    logger.info(f"Collected {len(commits)} commits for project {project}.")
    logger.debug(f"Saved commits to {project_commits_file}")


def __main():
    """
    Main entry point if executed as a script. For testing purposes.
    For production use main.py / call execute() directly.
    """

    args = parse_args()

    start_date = datetime.fromisoformat(args.start_date).replace(tzinfo=timezone.utc)
    end_date = datetime.fromisoformat(args.end_date).replace(tzinfo=timezone.utc)

    if args.project:
        execute(args.project, start_date, end_date)
    else:
        for project in CONFIG.get("projects", {}).keys():
            execute(project, start_date, end_date)


if __name__ == "__main__":
    __main()
