import logging
import os
import subprocess

logger = logging.getLogger(__name__)


def parse_filename(filename) -> tuple[str, str, str]:
    """Parse log filename to extract node, timestamp, commit hash, and job ID."""
    parts = filename.rsplit("_", 3)
    node = parts[0].replace("node", "")
    timestamp = parts[1]
    commit_hash = parts[2].split(".")[0]  # Remove file extension
    return node, timestamp, commit_hash


def get_filename(node, timestamp, commit_hash, success=True):
    """Generate log filename based on parameters."""
    ext = "log" if success else "error"
    return f"node{node}_{timestamp}_{commit_hash}.{ext}"


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

    try:
        result = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Merge stderr into stdout to preserve ordering
            text=True,
        )
        success = result.returncode == 0

        log_filename = os.path.join(
            logs_path,
            get_filename(node, timestamp, commit_hash, success),
        )
        with open(log_filename, "w") as f:
            f.write(result.stdout)
            if success:
                f.write("\n----\nSuccess!\n")

        if not success:
            logger.debug(f"Commit {commit_hash} failed. See log: {log_filename}")
            error_lcov = os.path.join(output_path, f"{commit_hash}.error")
            with open(error_lcov, "w") as f:
                f.write(f"Execution failed. See log for details.\n{log_filename}\n")

        return success

    except subprocess.TimeoutExpired:
        logger.error(f"Timeout expired while processing commit {commit_hash}.")
        return False
    except Exception as e:
        logger.error(f"Error occurred while processing commit {commit_hash}: {e}")
        return False
