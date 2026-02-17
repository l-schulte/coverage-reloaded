import logging
from src.helpers.helper import get_file_json_content

logger = logging.getLogger(__name__)


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

    for key in scripts.keys():
        if "test" in key:
            test_commands[key] = scripts[key]

    return test_commands
