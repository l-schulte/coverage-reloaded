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


def resolve_wildcard_at_commit(repo_path, commit_hash, wildcard_path) -> list[str]:
    parent = wildcard_path.rsplit("/*", 1)[0]  # e.g. "samples/msal-react-samples"
    cmd = ["git", "-C", repo_path, "ls-tree", "--name-only", commit_hash, parent + "/"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.splitlines()


def resolve_workspace_globs(
    repo_path: str, commit_hash: str, glob_patterns: list[str]
) -> list[str]:
    """
    Given raw workspace glob patterns (e.g. "packages/*", "samples/**", "lib/foo"),
    find all package.json files within the scope of each pattern and return the
    unique parent directories as workspace paths.

    This is more efficient than first resolving wildcards and then searching for
    package.json, because it uses a single recursive ls-tree per unique parent
    directory rather than one ls-tree per resolved subdirectory.
    """
    workspaces: list[str] = []

    for pattern in glob_patterns:
        if not isinstance(pattern, str) or not pattern:
            continue

        # Strip trailing wildcards like /*, /** to get the search root
        search_root = pattern
        while search_root.endswith("/*") or search_root.endswith("/**"):
            search_root = search_root.rsplit("/", 1)[0]

        # Run a single recursive ls-tree on the search root
        cmd = [
            "git",
            "-C",
            repo_path,
            "ls-tree",
            "-r",
            "--name-only",
            commit_hash,
            f"{search_root}/",
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            continue

        for file_path in result.stdout.splitlines():
            if not file_path.endswith("/package.json"):
                continue
            parent = file_path.rsplit("/", 1)[0]

            # Check if this package.json is within the original pattern's scope.
            # For a pattern like "packages/*", a package.json at "packages/foo/package.json"
            # is in scope, but "packages/foo/bar/package.json" is not (too deep).
            # For "samples/**", any depth is fine.
            if "**" in pattern:
                # ** matches any depth — accept all
                if parent not in workspaces:
                    workspaces.append(parent)
            elif "/*" in pattern:
                # Single-level wildcard: parent must be a direct child of search_root
                # e.g. pattern "packages/*" → parent "packages/foo" is valid,
                # but "packages/foo/bar" is not.
                if "/" not in parent[len(search_root) + 1 :]:
                    if parent not in workspaces:
                        workspaces.append(parent)
            else:
                # Literal path — only accept if it matches exactly or is a subdirectory
                if parent == pattern or parent.startswith(pattern + "/"):
                    if parent not in workspaces:
                        workspaces.append(parent)

    return workspaces


def get_file_json_content(repo_path, commit_hash, file_path) -> dict | None:
    content = get_file_at_commit(repo_path, commit_hash, file_path)

    if not content:
        # logger.info(
        #     f"File {file_path} at revision {commit_hash} in {repo_path} does not exist or is empty."
        # )
        return None

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
    range_str = range_str.replace(" ", "")

    # Normal range parsing for everything else
    clauses = re.split(r"\s*\|\|\s*", range_str)

    for clause in clauses:
        clause = clause.strip()
        clause = clause.replace(".x", "")  # Handle wildcard in minor/patch
        if not clause:
            continue

        # Handle hyphen ranges: "A - B" → ">=A <=B"
        hyphen_match = re.match(r"^(\d+(?:\.\d+){0,2})-(\d+(?:\.\d+){0,2})$", clause)
        if hyphen_match:
            lo, hi = hyphen_match.group(1), hyphen_match.group(2)
            clause = f">={lo} <={hi}"

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
