import datetime
import json
import csv
from pydriller import Repository
from tqdm import tqdm

repo_path = "repo"
output_file = "commits.csv"

config = json.load(open("../../config.json"))
start_date = datetime.datetime.fromisoformat(config["startdate"]).replace(tzinfo=datetime.timezone.utc)
end_date = datetime.datetime.fromisoformat(config["enddate"]).replace(tzinfo=datetime.timezone.utc)

with open(output_file, mode="w", newline="") as csv_file:
    fieldnames = ["commit_hash", "timestamp", "container", "registry"]
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames)

    writer.writeheader()

    lines = []
    latest_container = None

    repository = Repository(repo_path)
    print(f"Traversing commits in repository at {repo_path}...")
    for commit in tqdm(repository.traverse_commits(), desc="Processing commits"):
        registry = "yarn"


        if commit.committer_date >= end_date or commit.committer_date < start_date:
            continue

        # Extract expected node version from "volta" field in package.json if present (default node:10)
        if "package.json" in set(mod.filename for mod in commit.modified_files):
            for mod in commit.modified_files:
                if mod.filename == "package.json":
                    try:
                        content = mod.source_code
                        if content:
                            package_json = json.loads(content)
                            if "volta" in package_json and "node" in package_json["volta"]:
                                node_version = package_json["volta"]["node"].split('.')[0]

                                if int(node_version) < 12:
                                    latest_container = f"node:{node_version}-buster"
                                else:
                                    latest_container = f"node:{node_version}-bullseye"

                    except Exception:
                        pass
            

        lines.append(
            {
                "commit_hash": commit.hash,
                "timestamp": str(commit.committer_date.timestamp()).split('.')[0],
                "container": (latest_container if latest_container else "node:10-buster"),
                "registry": registry,
            }
        )
    
    writer.writerows(lines)
