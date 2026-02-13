import logging
import subprocess
import re
import json

logger = logging.getLogger(__name__)


def file_existed_at_commit(repo_path: str, commit_hash: str, file_path: str) -> bool:
    """Checks if a file existed at a specific commit in the given repository."""
    result = subprocess.run(
        ["git", "-C", repo_path, "cat-file", "-e", f"{commit_hash}:{file_path}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def get_file_at_commit(repo_path, commit_hash, file_path):
    cmd = ["git", "-C", repo_path, "show", f"{commit_hash}:{file_path}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


def get_file_json_content(repo_path, commit_hash, file_path) -> dict | None:
    content = get_file_at_commit(repo_path, commit_hash, file_path)
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        logger.error(
            f"Failed to parse {file_path} at revision {commit_hash} in {repo_path}: {e}"
        )
        return None


def get_file_content(
    repo_path: str, revision: str, file_path: str
) -> str | dict | None:
    """
    Reads the content of the specified file if it exists.
    """

    try:
        content = get_file_at_commit(repo_path, revision, file_path)

        return content.strip() if content else None
    except Exception:
        return None


def version_satisfies(probe_version: str, range_str: str) -> bool:
    """
    Simplified implementation of npm's semver satisfies function for basic version range checks.
    Deviations from full npm semantics:
    - Only supports basic operators: <, <=, >, >=, =, ~, ^, and wildcard (*).
    - Only supports major.minor.patch versions (no pre-release or build metadata).

    :param probe_version: The version to test.
    :type probe_version: str
    :param range_str: The version range string to test against.
    :type range_str: str
    :return: True if the probe_version satisfies the range_str, False otherwise.
    :rtype: bool
    """
    v_parts = list(map(int, probe_version.split(".")))
    v = v_parts + [0] * (3 - len(v_parts))  # Pad to major.minor.patch
    range_str = range_str.strip()

    # Normal range parsing for everything else
    clauses = re.split(r"\s*\|\|\s*", range_str)

    for clause in clauses:
        clause = clause.strip()
        clause = clause.replace(".x", "")  # Handle wildcard in minor/patch
        if not clause:
            continue

        ands = re.split(r"[\s,]+", clause)
        clause_ok = True

        # Check if range_str is single concrete version
        if re.match(r"^(\d+(?:\.\d+){0,2})$", clause.strip()):
            c_parts = list(map(int, clause.strip().split(".")))
            if tuple(v[: len(c_parts)]) != tuple(c_parts):
                clause_ok = False
                continue

        for comp in ands:
            comp = comp.strip()
            if not comp or comp == "*":
                return True

            m = re.match(r"([<>=~^]+)(\*|\d+(?:\.\d+){0,2})", comp)
            if not m:
                continue

            op, r_str = m.groups()
            op = op or "="
            r_parts = list(map(int, r_str.split(".")))
            r = r_parts + [0] * (3 - len(r_parts))

            if op == "<":
                if tuple(v) >= tuple(r):
                    clause_ok = False
                    break
            elif op == "<=":
                if tuple(v) > tuple(r):
                    clause_ok = False
                    break
            elif op == ">":
                if tuple(v) <= tuple(r):
                    clause_ok = False
                    break
            elif op == ">=":
                if tuple(v) < tuple(r):
                    clause_ok = False
                    break
            elif op == "=":
                if v != r:
                    clause_ok = False
                    break
            elif op == "~":
                if (
                    v[0] != r[0]
                    or (len(v) > 1 and v[1] != r[1])
                    or (len(v) > 2 and v[2] < r[2])
                ):
                    clause_ok = False
                    break
            elif op == "^":
                if v[0] != r[0]:
                    clause_ok = False
                    break

        if clause_ok:
            return True
    return False
