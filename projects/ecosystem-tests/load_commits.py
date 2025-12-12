import datetime
import json
import csv
from pydriller import Repository
from tqdm import tqdm
import re
import subprocess

repo_path = "repo"
output_file = "commits.csv"

config = json.load(open("../../config.json"))
start_date = datetime.datetime.fromisoformat(config["startdate"]).replace(tzinfo=datetime.timezone.utc)
end_date = datetime.datetime.fromisoformat(config["enddate"]).replace(tzinfo=datetime.timezone.utc)

# from https://github.com/chicoxyzzy/node-releases/blob/master/data/release-schedule/release-schedule.json
node_releases = json.load(open("../../node_releases.json"))

def get_file_at_commit(repo_path, commit_hash, file_path):
    cmd = ["git", "-C", repo_path, "show", f"{commit_hash}:{file_path}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout

with open(output_file, mode="w", newline="") as csv_file:
    fieldnames = ["commit_hash", "timestamp", "container", "registry", "container_source"]
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames)

    writer.writeheader()

    lines = []
    latest_container_specified = False
    latest_container = None

    repository = Repository(repo_path)
    print(f"Traversing commits in repository at {repo_path}...")
    for commit in tqdm(repository.traverse_commits(), desc="Processing commits"):
        registry = "yarn"
        source = None


        if commit.committer_date >= end_date or commit.committer_date < start_date:
            continue

        def get_container_from_node_version(version_string: str) -> str:
            version_split = version_string.split('.')
            major_version = int(version_split[0])
            node_version = ".".join(version_split[:2]) if len(version_split) > 1 else version_split[0]

            if major_version < 10:
                node_version = "10"

            if major_version < 12:
                return f"node:{node_version}-buster"
            else:
                return f"node:{node_version}-bullseye"

        def get_container_from_package(package_json) -> str:
            if "engines" in package_json and "node" in package_json["engines"]:
                version_match = re.findall(r'>=([\d\.]+)', package_json["engines"]["node"])
                if version_match:
                    latest_container_specified = True
                    return get_container_from_node_version(version_match[-1])

            return latest_container

        # If first commit, get the package json directly (even if not in modified files)
        if len(lines) == 0:
            print(set(mod.new_path for mod in commit.modified_files))
            try:
                package_json_content = get_file_at_commit(repo_path, commit.hash, "package.json")
                # print(package_json_content)
                if package_json_content:
                    package_json = json.loads(package_json_content)
                    latest_container = get_container_from_package(package_json)
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
                            latest_container = get_container_from_package(package_json)

                    except Exception as e:
                        print(f"Failed to parse package.json in commit {commit.hash}: {e}")
                        pass
            
        commit_timestamp = int(str(commit.committer_date.timestamp()).split('.')[0])

        def get_node_from_release() -> str:
            def version_was_available(release_date: str, timestamp: int) -> bool:
                return (datetime.datetime.strptime(release_date, "%Y-%m-%d").timestamp() < timestamp)
            latest_node_releases = [release for release, data in node_releases.items() if version_was_available(data['start'], commit_timestamp)]
            return get_container_from_node_version(latest_node_releases[-1].replace('v', ''))

        if not latest_container_specified:
            # Fallback, sets the 
            latest_container = get_node_from_release()

        lines.append(
            {
                "commit_hash": commit.hash,
                "timestamp": commit_timestamp,
                "container": (latest_container if latest_container else "node:12-bullseye"),
                "registry": registry,
                "container_source": source
            }
        )
    
    writer.writerows(lines)
