import logging
import os
import subprocess

from strip_ansi import strip_ansi

logger = logging.getLogger(__name__)


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

    try:
        result = subprocess.run(
            command,
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
