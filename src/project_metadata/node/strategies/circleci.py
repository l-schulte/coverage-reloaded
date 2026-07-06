"""
CircleCI strategy for Node.js version resolution.

Extracts the Node.js version from ``.circleci/config.yml`` by inspecting:

1. **Direct ``cimg/node`` images** — ``- image: cimg/node:20.19.0``
2. **Parameterized ``cimg/node`` images** — ``- image: cimg/node:<< parameters.image >>``
   (resolves the parameter default from the executor definition)
3. **Custom executors with ``node-version``** — executor-level parameter like
   ``node-version: '22.18'`` (common with orb-managed executors)
4. **Cypress/browsers images** — ``cypress/browsers:node-18.20.3-chrome-...``
   (extracts the node version from the image tag)
"""

import re
from datetime import datetime
from typing import Optional

import yaml

from src.project_metadata.helper import get_file_content
from src.project_metadata.node.parse_version import (
    find_matching_version_from_version_string,
)

CIRCLECI_CONFIG_PATHS = [
    ".circleci/config.yml",
    ".circleci/config.yaml",
]

# Regex to extract node version from cimg/node:<version> tags
RE_CIMG_NODE = re.compile(r"cimg/node:(\d+(?:\.\d+){0,2})")

# Regex to extract node version from cypress/browsers:node-<version>-... tags
RE_CYPRESS_NODE = re.compile(r"cypress/browsers:node-(\d+(?:\.\d+){0,2})")

# Regex to extract node version from any docker image tag containing "node-<version>"
RE_NODE_TAG = re.compile(r"(?:^|[/:-])node[=:-]?(\d+(?:\.\d+){0,2})(?:$|[-\s])")

# Regex to find parameter references like << parameters.image >>
RE_PARAM_REF = re.compile(r"<<\s*parameters\.(\w+)\s*>>")


def _resolve_parameter_default(
    config: dict, param_name: str, executor_name: Optional[str] = None
) -> Optional[str]:
    """
    Resolve the default value of a CircleCI parameter.

    Searches:
    1. The executor definition (if *executor_name* is given) for the parameter default.
    2. Top-level ``parameters`` for pipeline-level parameter defaults.
    """
    # Check executor-level parameters
    if executor_name:
        executor = config.get("executors", {}).get(executor_name, {})
        params = executor.get("parameters", {})
        if param_name in params:
            return params[param_name].get("default")

    # Check top-level (pipeline) parameters
    pipeline_params = config.get("parameters", {})
    if param_name in pipeline_params:
        return pipeline_params[param_name].get("default")

    return None


def _extract_node_version_from_image(image_str: str) -> Optional[str]:
    """Try to extract a node version from a docker image string."""
    # cimg/node:<version>
    m = RE_CIMG_NODE.search(image_str)
    if m:
        return m.group(1)

    # cypress/browsers:node-<version>-...
    m = RE_CYPRESS_NODE.search(image_str)
    if m:
        return m.group(1)

    # Generic node-<version> in tag (e.g. myimage:node-20.19-foo)
    m = RE_NODE_TAG.search(image_str)
    if m:
        return m.group(1)

    return None


def _scan_docker_images(config: dict) -> list[str]:
    """
    Scan the entire CircleCI config for ``docker:`` blocks and collect all
    ``image:`` strings that reference node-related images.
    """
    found: list[str] = []

    # Check top-level executors
    for executor_name, executor_def in config.get("executors", {}).items():
        docker_entries = executor_def.get("docker", [])
        for entry in docker_entries:
            image = entry.get("image", "")
            if image and ("node" in image.lower() or "cimg" in image.lower()):
                found.append(image)

    # Check jobs
    for job_name, job_def in config.get("jobs", {}).items():
        docker_entries = job_def.get("docker", [])
        for entry in docker_entries:
            image = entry.get("image", "")
            if image and ("node" in image.lower() or "cimg" in image.lower()):
                found.append(image)

    return found


def _resolve_parameterized_image(config: dict, image_str: str) -> Optional[str]:
    """
    If *image_str* contains a parameter reference like ``<< parameters.image >>``,
    resolve the default and reconstruct the image string.
    """
    param_refs = RE_PARAM_REF.findall(image_str)
    if not param_refs:
        return image_str

    resolved = image_str
    for param_name in param_refs:
        default = _resolve_parameter_default(config, param_name)
        if default is None:
            return None  # Cannot resolve
        resolved = resolved.replace(f"<< parameters.{param_name} >>", str(default))

    return resolved


def _scan_executor_node_version_parameter(config: dict) -> Optional[str]:
    """
    Some CircleCI configs use custom executors (often via orbs) that accept a
    ``node-version`` parameter. Look for executor references in jobs that have
    a ``node-version`` parameter set.

    Pattern (material-ui style):
    ```yaml
    executor:
      name: code-infra/mui-node
      node-version: '22.18'
    ```
    """
    for job_name, job_def in config.get("jobs", {}).items():
        executor = job_def.get("executor")
        if not isinstance(executor, dict):
            continue
        node_version = executor.get("node-version")
        if node_version:
            return str(node_version)

    # Also check top-level default-job anchors (YAML anchors used in jobs)
    for key, value in config.items():
        if isinstance(value, dict):
            executor = value.get("executor")
            if isinstance(executor, dict):
                node_version = executor.get("node-version")
                if node_version:
                    return str(node_version)

    return None


def get_node_version(
    repo_path: str,
    commit_hash: str,
    release_cutoff: Optional[datetime] = None,
    use_first: bool = False,
) -> Optional[str]:
    """
    Check ``.circleci/config.yml`` at the given commit for Node.js version hints.

    Resolution order:
    1. Look for ``executor`` blocks with a ``node-version`` parameter.
    2. Scan ``docker:`` blocks for node-related images (``cimg/node``,
       ``cypress/browsers``, etc.), resolving parameterized image tags.
    3. Return the first valid Node version found.
    """
    for config_path in CIRCLECI_CONFIG_PATHS:
        content = get_file_content(repo_path, commit_hash, config_path)
        if not content:
            continue

        try:
            config = yaml.safe_load(str(content))
        except yaml.YAMLError:
            continue

        if not isinstance(config, dict):
            continue

        # Priority 1: executor-level node-version parameter
        node_version = _scan_executor_node_version_parameter(config)
        if node_version:
            version = find_matching_version_from_version_string(
                node_version, use_first=use_first
            )
            if version:
                return version

        # Priority 2: docker images
        images = _scan_docker_images(config)
        for image_str in images:
            # Resolve parameter references
            resolved = _resolve_parameterized_image(config, image_str)
            if resolved is None:
                continue

            version_str = _extract_node_version_from_image(resolved)
            if version_str:
                version = find_matching_version_from_version_string(
                    version_str, use_first=use_first
                )
                if version:
                    return version

    return None
