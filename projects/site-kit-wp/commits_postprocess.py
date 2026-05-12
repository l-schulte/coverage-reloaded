import os
import pandas as pd


def postprocess():
    parent_dir = os.path.dirname(__file__)
    commits_file = os.path.join(parent_dir, "commits.csv")
    additional_info_file = os.path.join(parent_dir, "additional_information.csv")

    commits = pd.read_csv(commits_file, low_memory=False)
    additional_info = pd.read_csv(additional_info_file, low_memory=False)

    # Merge additional information with commits
    commits = commits.merge(
        additional_info, on="commit_hash", how="left", suffixes=("", "_additional_info")
    )

    # where column "test:js" container "-w", set "pm_version" to "npm@7"
    commits.loc[commits["test:js"].str.contains("-w", na=False), "pm_version"] = (
        "npm@7.10"
    )
    commits.loc[
        commits["test:js"].str.contains("-w", na=False), "pm_version_source"
    ] = "postprocessing fix"

    # remove additional information columns
    commits = commits.drop(
        columns=[col for col in commits.columns if col.endswith("_additional_info")]
    )

    commits.to_csv(commits_file, index=False)


if __name__ == "__main__":
    postprocess()
