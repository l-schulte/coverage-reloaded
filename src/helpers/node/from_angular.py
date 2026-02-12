import datetime
import json
import logging
import pandas as pd

from src.helpers.helper import get_file_content
from src.helpers.node.parse_version import (
    version_satisfies,
    parse_node_version,
)

ANGULAR_VERSIONS_PATH = "src/helpers/node/data/angular_releases.csv"
ANGULAR_VERSIONS = pd.read_csv(ANGULAR_VERSIONS_PATH)
ANGULAR_VERSIONS["First official release"] = ANGULAR_VERSIONS[
    "First official release"
].apply(lambda x: datetime.datetime.strptime(x, "%m/%d/%y"))
ANGULAR_VERSIONS = ANGULAR_VERSIONS.sort_values(
    by="First official release", ascending=True
)

# https://angular.dev/reference/versions
ANGULAR_MATRIX_PATH = "src/helpers/node/data/angular_matrix.csv"
ANGULAR_MATRIX = pd.read_csv(ANGULAR_MATRIX_PATH)


logger = logging.getLogger(__name__)


def get_node_version(
    repo_path: str,
    revision: str,
    timestamp: int,
    packagejson_path: str = "package.json",
) -> str | None:
    """ """

    content = get_file_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    try:
        package_json = json.loads(content)
    except json.JSONDecodeError:
        logger.error(f"Error decoding package.json at revision {revision}")
        return None

    if (
        "dependencies" in package_json
        and "@angular/core" in package_json["dependencies"]
    ):
        angular_version_range = package_json.get("dependencies", {}).get(
            "@angular/core"
        )
        if not angular_version_range:
            return None

        angular_version = None
        # for potential_version, release_date in ANGULAR_VERSIONS[
        #     ["Version", "First official release"]
        # ].values:
        #     if release_date.timestamp() < timestamp and version_satisfies(
        #         str(potential_version), angular_version_range
        #     ):
        #         angular_version = str(potential_version)
        #         break

        for potential_version, release_date in ANGULAR_VERSIONS[
            ["Version", "First official release"]
        ].values:
            if version_satisfies(str(potential_version), angular_version_range):
                angular_version = str(potential_version)
                break

        if not angular_version:
            return None

        node_version = None
        for angular_version_range, node_version_range in ANGULAR_MATRIX[
            ["Angular", "NodeJS"]
        ].values:
            if version_satisfies(angular_version, angular_version_range):
                node_version = parse_node_version(node_version_range, use_first=True)
                break

        return node_version
