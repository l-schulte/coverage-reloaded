import datetime
import json
import csv
from pydriller import Repository
from tqdm import tqdm
import re
import subprocess
import pandas as pd

repo_path = "repo"
output_file = "commits.csv"

config = json.load(open("../../config.json"))
start_date = datetime.datetime.fromisoformat(config["startdate"]).replace(
    tzinfo=datetime.timezone.utc
)
end_date = datetime.datetime.fromisoformat(config["enddate"]).replace(
    tzinfo=datetime.timezone.utc
)

# from https://github.com/chicoxyzzy/node-releases/blob/master/data/release-schedule/release-schedule.json
node_releases = json.load(open("../../node_releases.json"))


def get_file_at_commit(repo_path, commit_hash, file_path):
    cmd = ["git", "-C", repo_path, "show", f"{commit_hash}:{file_path}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


def get_container_from_node_version(version_string: str) -> str:
    """
    Given a Node.js version string, returns the appropriate Docker container tag.
    """

    version_split = version_string.split(".")
    major_version = int(version_split[0])
    while version_split[-1] == "0" and len(version_split) > 1:
        version_split = version_split[:-1]
    node_version = (
        ".".join(version_split[:2]) if len(version_split) > 1 else version_split[0]
    )

    if major_version < 10:
        node_version = "10"

    if major_version < 12:
        return f"node:{node_version}-buster"
    else:
        return f"node:{node_version}-bullseye"


def get_engines_from_package(package_json) -> tuple[str | None, str | None]:
    """
    Extracts the Node.js and package manager versions from the "engines" field in package.json.
    """

    container = latest_container
    registry = latest_registry
    re_version_match = re.compile(r"(?:>=|\^)([\d\.]+)")

    if "engines" in package_json:
        if "node" in package_json["engines"]:
            version_match = re.findall(
                re_version_match, package_json["engines"]["node"]
            )
            if version_match:
                container = get_container_from_node_version(version_match[-1])
        if "pnpm" in package_json["engines"]:
            version_match = re.findall(
                re_version_match, package_json["engines"]["pnpm"]
            )
            if version_match:
                version = version_match[-1]
                registry = f"pnpm@{version}"

    return container, registry


def get_node_version_by_timestamp(timestamp: int) -> str:
    """
    Determines the latest available Node.js version based on the commit timestamp.
    """

    def version_was_available(release_date: str, timestamp: int) -> bool:
        return (
            datetime.datetime.strptime(release_date, "%Y-%m-%d").timestamp() < timestamp
        )

    latest_node_releases = [
        release
        for release, data in node_releases.items()
        if version_was_available(data["start"], timestamp)
    ]
    return get_container_from_node_version(latest_node_releases[-1].replace("v", ""))


lines = []
latest_container = None
latest_registry = None

repository = Repository(repo_path)
print(f"Traversing commits in repository at {repo_path}...")
for commit in tqdm(repository.traverse_commits(), desc="Processing commits"):

    if commit.committer_date >= end_date or commit.committer_date < start_date:
        continue

    # If first commit, get the package json directly (even if not in modified files)
    if len(lines) == 0:
        print(set(mod.new_path for mod in commit.modified_files))
        try:
            package_json_content = get_file_at_commit(
                repo_path, commit.hash, "package.json"
            )
            # print(package_json_content)
            if package_json_content:
                package_json = json.loads(package_json_content)
                latest_container, latest_registry = get_engines_from_package(
                    package_json
                )
        except Exception:
            pass

    # Extract expected node version from "volta" field in package.json if present
    modified_files = set(mod.old_path for mod in commit.modified_files)
    if "package.json" in modified_files:
        for mod in commit.modified_files:
            if mod.old_path == "package.json":
                try:
                    content = mod.source_code
                    if content:
                        package_json = json.loads(content)
                        latest_container, latest_registry = get_engines_from_package(
                            package_json
                        )

                except Exception as e:
                    print(f"Failed to parse package.json in commit {commit.hash}: {e}")
                    pass

    commit_timestamp = int(str(commit.committer_date.timestamp()).split(".")[0])

    lines.append(
        {
            "commit_hash": commit.hash,
            "timestamp": commit_timestamp,
            "container": (
                latest_container
                if latest_container
                else get_node_version_by_timestamp(commit_timestamp)
            ),
            "registry": latest_registry,
        }
    )

pd.DataFrame(lines).to_csv(output_file, index=False)
