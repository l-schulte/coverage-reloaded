import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from datetime import datetime, timezone
import logging
import os
import subprocess
import pydriller
import tqdm
import pandas as pd
import numpy as np

from src.config import get_config
from src.project_metadata.project_metadata import extract_project_metadata

logger = logging.getLogger(__name__)


def parse_args():
    cfg = get_config()
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
        default=cfg.start_date,
        help="Start date for commit collection in ISO format (YYYY-MM-DD).",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=cfg.end_date,
        help="End date for commit collection in ISO format (YYYY-MM-DD).",
    )
    return parser.parse_args()


def get_command_changes(df: pd.DataFrame):
    """
    Derives era-transition records from per-commit additional_information.

    For each script_name, identifies the unique script_definition values across
    commit history and records the first commit_hash where each definition
    appeared (i.e., the transition point). Also records the last commit where
    a script was present before it disappeared (script_definition="") so the
    full lifecycle is visible.

    Results are sorted chronologically within each script_name so the file
    can be read as an era timeline.

    Args:
        df: DataFrame with commit_hash, timestamp, and one column per script_name.

    Returns:
        DataFrame with columns: commit_hash, timestamp, script_name, script_definition
        sorted by script_name then timestamp. A blank script_definition marks
        the commit where the script was last seen before removal.
    """
    df_long = df.melt(
        id_vars=["commit_hash", "timestamp"],
        var_name="script_name",
        value_name="script_definition",
    )

    df_long["script_definition"] = (
        df_long["script_definition"].str.strip().replace("", np.nan)
    )

    # ── Track appearances ─────────────────────────────────────────────────
    df_present = df_long.dropna(subset=["script_definition"])

    # Sort by commit time so that drop_duplicates keeps the earliest occurrence
    df_present = df_present.sort_values(["script_name", "timestamp"])

    # Keep the first commit_hash where each unique script_definition appeared
    df_appearances = df_present.drop_duplicates(
        subset=["script_name", "script_definition"], keep="first"
    )

    # ── Track removals ─────────────────────────────────────────────────────
    # For each script_name, find the last commit where it was present.
    # If that's not the last commit overall for that script, it was removed.
    df_present_sorted = df_present.sort_values(["script_name", "timestamp"])
    df_last_present = df_present_sorted.groupby("script_name").last().reset_index()

    # Get the last commit overall for each script_name (including NaN rows)
    df_full_sorted = df_long.sort_values(["script_name", "timestamp"])
    df_last_overall = df_full_sorted.groupby("script_name").last().reset_index()

    # A removal occurred if the last present commit differs from the last overall commit
    df_removals = df_last_present.merge(
        df_last_overall[["script_name", "commit_hash"]],
        on="script_name",
        suffixes=("_present", "_overall"),
    )
    df_removals = df_removals[
        df_removals["commit_hash_present"] != df_removals["commit_hash_overall"]
    ].copy()
    df_removals["script_definition"] = ""
    df_removals = df_removals.rename(columns={"commit_hash_present": "commit_hash"})
    df_removals = df_removals[
        ["commit_hash", "timestamp", "script_name", "script_definition"]
    ]

    # ── Combine and sort ───────────────────────────────────────────────────
    df_changes = pd.concat(
        [df_appearances, df_removals],
        ignore_index=True,
    )

    return df_changes.sort_values(["script_name", "timestamp"]).reset_index(drop=True)


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
    cfg = get_config()
    project_cfg = cfg.projects.get(project)
    project_url = project_cfg.url if project_cfg else None
    repo_path = f"{project_path}/repo"

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
                project_cfg,
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
        cfg = get_config()
        for project in cfg.projects:
            execute(project, start_date, end_date)


if __name__ == "__main__":
    __main()
