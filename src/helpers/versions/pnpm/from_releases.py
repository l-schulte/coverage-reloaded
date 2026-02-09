import json

# https://pnpm.io/installation#compatibility
PNPM_RELEASES_PATH = "helpers/versions/pnpm/data/releases.json"
PNPM_RELEASES = json.load(open(PNPM_RELEASES_PATH, "r"))


def get_pnpm_version(node_version: str) -> str | None:
    """
    Given a Node.js version string, returns the appropriate pnpm version.
    """

    version_parts = node_version.split(".")
    major_version = int(version_parts[0])

    return PNPM_RELEASES.get("node:" + str(major_version), None)
