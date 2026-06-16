import datetime
import json
import logging
from typing import Optional
import pandas as pd

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    version_satisfies,
    find_matching_version_from_version_string,
)

ANGULAR_VERSIONS_PATH = "src/project_metadata/node/data/angular_releases.csv"
ANGULAR_VERSIONS = pd.read_csv(ANGULAR_VERSIONS_PATH)
ANGULAR_VERSIONS["First official release"] = ANGULAR_VERSIONS[
    "First official release"
].apply(lambda x: datetime.datetime.strptime(x, "%m/%d/%y"))
ANGULAR_VERSIONS = ANGULAR_VERSIONS.sort_values(
    by="First official release", ascending=True
)

ANGULAR_MATRIX_PATH = "src/project_metadata/node/data/angular_matrix.csv"
ANGULAR_MATRIX = pd.read_csv(ANGULAR_MATRIX_PATH)

logger = logging.getLogger(__name__)


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
) -> Optional[str]:
    """
    Infer Node.js version from Angular compatibility matrix.
    """
    content = get_file_content(repo_path, commit_hash, "package.json")
    if not content:
        return None

    try:
        package_json = json.loads(str(content))
    except json.JSONDecodeError:
        logger.error(f"Error decoding package.json at revision {commit_hash}")
        return None

    if (
        "dependencies" not in package_json
        or "@angular/core" not in package_json["dependencies"]
    ):
        return None

    angular_version_range = package_json["dependencies"]["@angular/core"]
    angular_version = find_matching_version_from_version_string(
        angular_version_range, use_artificial_minor_version=True
    )
    if not angular_version:
        return None

    angular_major = angular_version.split(".")[0]
    angular_release = ANGULAR_VERSIONS[
        ANGULAR_VERSIONS["Version"].astype(str).str.startswith(angular_major)
    ]
    if angular_release.empty:
        return None

    angular_release_date = angular_release.iloc[0]["First official release"]
    angular_release_date_ts = angular_release_date.timestamp()

    if release_cutoff and angular_release_date_ts > release_cutoff.timestamp():
        return None

    node_version_row = ANGULAR_MATRIX[
        ANGULAR_MATRIX["Angular"].astype(str).str.startswith(angular_major)
    ]
    if node_version_row.empty:
        return None

    node_version_str = str(node_version_row.iloc[0]["NodeJS"])
    node_version = find_matching_version_from_version_string(
        node_version_str, use_artificial_minor_version=True
    )
    return node_version
