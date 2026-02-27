import os
import pandas as pd


def fix_node_version(
    commits: pd.DataFrame, old_version: int, new_version: int
) -> pd.Series:
    """
    Fixes the node version for commits where the node version is old_version and the source is "node_releases.json (12 months offset)".
    Sets the node version to new_version and the source to "postprocessing fix".

    Args:
        commits (pd.DataFrame): The DataFrame containing the commits data.
        old_version (int): The old node version to be fixed.
        new_version (int): The new node version to set for the affected commits.

    Returns:
        pd.Series: The updated node_version column with the fixes applied.
    """
    condition = (commits["node_version"] == old_version) & (
        commits["node_version_source"] == "node_releases.json (12 months offset)"
    )
    commits.loc[condition, "node_version"] = new_version
    commits.loc[condition, "node_version_source"] = "postprocessing fix"
    return commits["node_version"]


def postprocess():
    parent_dir = os.path.dirname(__file__)
    commits_file = os.path.join(parent_dir, "commits.csv")

    commits = pd.read_csv(commits_file, low_memory=False)

    # Node versions 13 and 15 fail to install dependencies, if they were chosen based
    # on the node_releases.json with a 12 months offset, we set them to the next major
    # version, which is 14 and 16 respectively. Setting node_version_source to "postprocessing fix".
    commits["node_version"] = fix_node_version(commits, 13, 14)
    commits["node_version"] = fix_node_version(commits, 15, 16)

    commits.to_csv(commits_file, index=False)

    return


if __name__ == "__main__":
    postprocess()
