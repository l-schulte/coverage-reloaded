import datetime
import json
import csv
from pydriller import Repository
from tqdm import tqdm
import re

repo_path = "repo"
output_file = "commits.csv"

config = json.load(open("../config.json"))
start_date = datetime.datetime.fromisoformat(config["startdate"]).replace(tzinfo=datetime.timezone.utc)
end_date = datetime.datetime.fromisoformat(config["enddate"]).replace(tzinfo=datetime.timezone.utc)

with open(output_file, mode="w", newline="") as csv_file:
    fieldnames = ["commit_hash", "timestamp", "container", "registry"]
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames)

    writer.writeheader()

    lines = []
    latest_container = "node:10-alpine"

    repository = Repository(repo_path)
    print(f"Traversing commits in repository at {repo_path}...")
    for commit in tqdm(repository.traverse_commits(), desc="Processing commits"):
        registry = "yarn"


        if commit.committer_date >= end_date or commit.committer_date < start_date:
            continue

        def get_latest_container_from_dockerfile(content):
            dockerfile_lines = content.splitlines()
            for line in dockerfile_lines:
                match = re.match(r'FROM node:([\d\.]+)', line)
                if match:
                    node_version = match.group(1)
                    distro = "alpine"
                    return f"node:{node_version}-{distro}"
            return None
        

        # Extract node version from Dockerfile if present
        if "Dockerfile" in set(mod.filename for mod in commit.modified_files):
            for mod in commit.modified_files:
                if mod.filename == "Dockerfile":
                    try:
                        content = mod.source_code
                        if content:
                            latest_container = get_latest_container_from_dockerfile(content) or latest_container
                    except Exception:
                        pass

        # Extract expected node version from "engines" field in package.json if present (default node:10)
        # if "package.json" in set(mod.filename for mod in commit.modified_files):
        #     for mod in commit.modified_files:
        #         if mod.filename == "package.json":
        #             try:
        #                 content = mod.source_code
        #                 if content:
        #                     package_json = json.loads(content)
        #                     if "engines" in package_json and "node" in package_json["engines"]:
        #                         node_version_matches = re.findall(r'[^\.]=(\d+)', package_json["engines"]["node"])
        #                         if node_version_matches:
        #                             max_node_version = max(int(v) for v in node_version_matches)
        #                             node_version = str(max_node_version)
        #                         else:
        #                             continue

        #                         if int(node_version) < 12:
        #                             latest_container = f"node:{node_version}-buster"
        #                         else:
        #                             latest_container = f"node:{node_version}-bullseye"

        #             except Exception:
        #                 pass
            

        lines.append(
            {
                "commit_hash": commit.hash,
                "timestamp": str(commit.committer_date.timestamp()).split('.')[0],
                "container": latest_container,
                "registry": registry,
            }
        )
    
    writer.writerows(lines)
