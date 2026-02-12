import json
from src.helpers.helper import get_file_content


def get_test_commands(
    repo_path: str, revision: str, packagejson_path: str = "package.json"
) -> list[str] | None:
    """
    Retrieves the test commands specified in the package.json file at a given revision.
    """

    content = get_file_content(repo_path, revision, packagejson_path)
    if not content:
        return None

    package_json = json.loads(content)
    scripts = package_json.get("scripts", {})
    test_commands = set()

    for key in scripts.keys():
        if "test" in key:
            test_commands.add(key)

    return list(test_commands)
