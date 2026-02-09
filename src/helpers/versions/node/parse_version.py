import json
import re


def __npm_satisfies(probe_version: str, range_str: str) -> bool:
    """
    Simplified implementation of npm's semver satisfies function for basic version range checks.
    Deviations from full npm semantics:
    - Only supports basic operators: <, <=, >, >=, =, ~, ^, and wildcard (*).
    - Only supports major.minor.patch versions (no pre-release or build metadata).

    :param probe_version: Description
    :type probe_version: str
    :param range_str: Description
    :type range_str: str
    :return: Description
    :rtype: bool
    """
    v_parts = list(map(int, probe_version.split(".")))
    v = v_parts + [0] * (3 - len(v_parts))  # Pad to major.minor.patch
    range_str = range_str.strip()

    # Normal range parsing for everything else
    clauses = re.split(r"\s*\|\|\s*", range_str)

    for clause in clauses:
        clause = clause.strip()
        if not clause:
            continue

        ands = re.split(r"[\s,]+", clause)
        clause_ok = True

        # Check if range_str is single concrete version
        if re.match(r"^(\d+(?:\.\d+){0,2})$", clause):
            c_parts = list(map(int, clause.split(".")))
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


NODE_RELEASES_PATH = "src/helpers/versions/node/data/releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def parse_node_version(version_string: str, use_first: bool = False) -> str | None:
    """
    Parses a Node.js version string to extract the version.

    Parameters:
    - version_string: The version string to parse.
    - use_first: If True, returns the first matching version instead of the last.
    """

    # Check if range_str is single concrete version -> return as-is
    if re.match(r"^(\d+(?:\.\d+){0,2})$", version_string.strip()):
        return version_string

    last_ok = None
    for major in NODE_RELEASES.keys():
        major = major.removeprefix("v")
        try:
            if __npm_satisfies(major, version_string):
                last_ok = major

                if use_first:
                    return str(major)

        except Exception:
            raise ValueError(
                f"npm satisfies check failed for version '{major}' and range '{version_string}'"
            )

    return str(last_ok)
