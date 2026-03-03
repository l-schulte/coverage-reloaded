import os
import pandas as pd


# def fix_node_version(
#     commits: pd.DataFrame, old_version: int, new_version: int
# ) -> pd.Series:
#     """
#     Fixes the node version for commits where the node version is old_version and the source is "node_releases.json (12 months offset)".
#     Sets the node version to new_version and the source to "postprocessing fix".

#     Args:
#         commits (pd.DataFrame): The DataFrame containing the commits data.
#         old_version (int): The old node version to be fixed.
#         new_version (int): The new node version to set for the affected commits.

#     Returns:
#         pd.Series: The updated node_version column with the fixes applied.
#     """
#     condition = (commits["node_version"] == old_version) & (
#         commits["node_version_source"] == "node_releases.json (12 months offset)"
#     )
#     commits.loc[condition, "node_version"] = new_version
#     commits.loc[condition, "node_version_source"] = "postprocessing fix"
#     return commits["node_version"]


def fix_npm_version(
    commits: pd.DataFrame, old_version: str, new_version: str
) -> pd.Series:
    """
    Fixes the npm version for commits where the npm version is old_version and the source is "package.json".
    Sets the npm version to new_version and the source to "postprocessing fix".

    Args:
        commits (pd.DataFrame): The DataFrame containing the commits data.
        old_version (str): The old npm version to be fixed.
        new_version (str): The new npm version to set for the affected commits.

    Returns:
        pd.Series: The updated pm_version column with the fixes applied.
    """
    condition = (commits["pm_version"] == old_version) & (
        commits["pm_version_source"] == "package.json"
    )
    commits.loc[condition, "pm_version"] = new_version
    commits.loc[condition, "pm_version_source"] = "postprocessing fix"
    return commits["pm_version"]


def postprocess():
    parent_dir = os.path.dirname(__file__)
    commits_file = os.path.join(parent_dir, "commits.csv")

    commits = pd.read_csv(commits_file, low_memory=False)

    # npm@8.1.0 fails to install dependencies, so we upgrade to 8.5.0 which is already used in other commits. The error is:
    # npm ERR! code Z_DATA_ERROR
    # npm ERR! errno -3
    # npm ERR! zlib: incorrect data check
    commits["pm_version"] = fix_npm_version(
        commits, old_version="npm@8.1.0", new_version="npm@8.5.0"
    )

    commits.to_csv(commits_file, index=False)

    return


if __name__ == "__main__":
    postprocess()
