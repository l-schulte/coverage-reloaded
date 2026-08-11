import logging
import os
import subprocess
import shutil

from strip_ansi import strip_ansi

logger = logging.getLogger(__name__)

# Must match EXECUTOR in docker-run.sh
EXECUTOR = "podman"


def _build_base_image(node, workspace_path):
    """Build the base Docker image for a given Node version."""
    tag = f"core_node{node}_base"
    logger.info(f"Building base image {tag}")
    subprocess.run(
        [EXECUTOR, "build", "--build-arg", f"NODE_VERSION={node}", "-t", tag, "."],
        cwd=workspace_path,
        check=True,
    )


def _build_project_image(node, project, workspace_path):
    """Build the project Docker image for a given Node version."""
    tag = f"core_node{node}_{project.lower()}"
    project_dir = os.path.join(workspace_path, "projects", project)
    logger.info(f"Building project image {tag}")
    subprocess.run(
        [EXECUTOR, "build", "--build-arg", f"NODE_VERSION={node}", "-t", tag, "."],
        cwd=project_dir,
        check=True,
    )


def pre_build_images(commits, project, workspace_path):
    """Pre-build base and project Docker images for all commits.

    Collects unique Node versions from the commit list and builds one base
    image per version plus one project image per version.  Must be called
    before the thread pool so that docker-run.sh can skip redundant builds.
    """
    unique_nodes = {commit[4] for commit in commits}  # node is index 4
    logger.info(
        f"Pre-building Docker images for project {project} with {len(unique_nodes)} nodes: {unique_nodes}"
    )
    for node in unique_nodes:
        _build_base_image(node, workspace_path)
        _build_project_image(node, project, workspace_path)


def parse_filename(filename) -> tuple[str, str, str]:
    """Parse log filename to extract timestamp, commit hash, and node."""
    parts = filename.rsplit("_", 2)
    timestamp = parts[0]
    commit_hash = parts[1].split(".")[0]  # Remove file extension
    return timestamp, commit_hash


def get_filename(timestamp, commit_hash, success=True):
    """Generate log filename based on parameters."""
    ext = "log" if success else "error"
    return f"{timestamp}_{commit_hash}.{ext}"


def docker_run_script(commit, workspace_path, logs_path, output_path):
    """
    Run docker container for a single commit.

    Args:
        commit (tuple): A tuple containing project, project_id, commit_hash, timestamp, node, and package manager.
        workspace_path (str): The base path for the workspace to find the docker_run.sh script.
        logs_path (str): The path where logs should be stored.
        output_path (str): The path where output files should be stored.
    """
    DOCKER_RUN_SCRIPT = os.path.join(workspace_path, "docker-run.sh")

    project, project_id, commit_hash, timestamp, node, pm = commit
    logger.debug(f"Processing commit {commit_hash} with Node {node} and PM {pm}")

    command = [
        "/bin/sh",
        DOCKER_RUN_SCRIPT,
        project,
        "exec",
        commit_hash,
        str(timestamp),
        pm,
        node,
        project_id,
    ]

    # Automated collection uses 6 CPUs to keep resource usage predictable.
    # Override by setting CONTAINER_CPUS in .env for manual runs.
    env = os.environ.copy()
    env["CONTAINER_CPUS"] = "6"
    env["SKIP_BUILD"] = "true"

    try:
        result = subprocess.run(
            command,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Merge stderr into stdout to preserve ordering
            text=True,
        )
        exit_code = result.returncode
        is_not_applicable = exit_code == 2
        success = exit_code == 0 or is_not_applicable

        log_filename = os.path.join(
            logs_path,
            get_filename(timestamp, commit_hash, success),
        )
        clean_output = strip_ansi(result.stdout)

        with open(log_filename, "w") as f:
            f.write(clean_output)
            if exit_code == 0:
                f.write("\n----\nSuccess!\n")
            elif is_not_applicable:
                f.write("\n----\nNot applicable (exit code 2)\n")

        if exit_code == 2:
            logger.debug(
                f"Commit {commit_hash} not applicable. See log: {log_filename}"
            )
            not_applicable_file = os.path.join(
                output_path, f"{timestamp}_{commit_hash}.not_applicable"
            )
            with open(not_applicable_file, "w") as f:
                f.write(f"Commit: {commit_hash}\n")
                f.write(f"Timestamp: {timestamp}\n")
                f.write(f"Exit code: 2\n")
                f.write(f"Log: {log_filename}\n")
        elif not success:
            logger.debug(f"Commit {commit_hash} failed. See log: {log_filename}")
            # Keep any existing per-commit directory from a previous run —
            # deleting it would lose historical failure data.
            error_lcov = os.path.join(output_path, f"{timestamp}_{commit_hash}.error")
            with open(error_lcov, "w") as f:
                f.write(f"Execution failed. See log for details.\n{log_filename}\n")

        return success

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout expired while processing commit {commit_hash}.")
        return False
    except Exception as e:
        logger.error(f"Error occurred while processing commit {commit_hash}: {e}")
        return False
