import requests
import os
import json


def __get_available_node_tags() -> set:
    """
    Fetch available Node.js Docker tags from Docker Hub.

    Args:
        distro: Filter by distro name (bullseye, buster, etc.)

    Returns:
        Set of available tags.
    """

    cache_file = os.path.join(os.path.dirname(__file__), "node_tags_cache.json")
    if os.path.exists(cache_file):
        return set(json.load(open(cache_file, "r")))

    tags = set()
    page = 1

    while True:
        url = f"https://registry.hub.docker.com/v2/repositories/library/node/tags/"
        params = {"page_size": 100, "page": page}

        response = requests.get(url, params=params)
        response.raise_for_status()
        data = response.json()

        for result in data.get("results", []):
            tags.add(result["name"])

        # Check if there are more pages
        if data.get("next") is None:
            break
        page += 1

    json.dump(list(tags), open(cache_file, "w"))
    return tags


AVAILABLE_CONTAINER_TAGS = __get_available_node_tags()


def get_container_tag(node_version: str | None) -> str | None:
    """
    Given a Node.js version string, returns the appropriate Docker container tag.
    """

    if not node_version:
        return None

    version_parts = node_version.split(".")
    major_version = int(version_parts[0])
    while version_parts[-1] == "0" and len(version_parts) > 1:
        version_parts = version_parts[:-1]

    formatted_version = ".".join(version_parts[:2])

    if major_version < 10:
        formatted_version = "10"

    if major_version <= 15:
        result = f"node:{formatted_version}-buster"
        if result in AVAILABLE_CONTAINER_TAGS:
            return result
        return f"node:{major_version}-buster"
    else:
        result = f"node:{formatted_version}-bullseye"
        if result in AVAILABLE_CONTAINER_TAGS:
            return result
        return f"node:{major_version}-bullseye"
