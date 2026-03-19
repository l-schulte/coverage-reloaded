import logging
from src.project_metadata.helper import get_file_json_content

logger = logging.getLogger(__name__)

KEYWORDS = ["test", "jest", "mocha", "ava", "tap", "ci", "coverage"]


def get_test_commands(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> dict[str, str] | None:
    """
    Retrieves the test commands specified in the package.json file at a given revision.
    """

    package_json = get_file_json_content(repo_path, revision, packagejson_path)
    if not package_json:
        return None

    scripts = package_json.get("scripts", {})
    test_commands = {}

    for key, value in scripts.items():
        if any(keyword in key.lower() for keyword in KEYWORDS):
            test_commands[key] = value

        if any(keyword in value.lower() for keyword in KEYWORDS):
            test_commands[key] = value

    return test_commands
