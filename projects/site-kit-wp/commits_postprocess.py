import os
import pandas as pd


def postprocess():
    parent_dir = os.path.dirname(__file__)
    commits_file = os.path.join(parent_dir, "commits.csv")

    commits = pd.read_csv(commits_file, low_memory=False)

    # where column "test:js" container "-w", set "pm_version" to "npm@7"
    commits.loc[commits["test:js"].str.contains("-w", na=False), "pm_version"] = (
        "npm@7.10"
    )
    commits.loc[
        commits["test:js"].str.contains("-w", na=False), "pm_version_source"
    ] = "postprocessing fix"

    commits.to_csv(commits_file, index=False)


if __name__ == "__main__":
    postprocess()
