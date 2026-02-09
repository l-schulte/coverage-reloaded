import json
from semantic_version import Version, NpmSpec
import re

NODE_RELEASES_PATH = "helpers/versions/node/data/releases.json"
NODE_RELEASES = json.load(open(NODE_RELEASES_PATH, "r"))


def __npm_satisfies(probe_version: str, range_str: str) -> bool:
    v = list(map(int, probe_version.split(".")))

    # Normal range parsing for everything else
    clauses = re.split(r"\s*\|\|\s*", range_str)

    for clause in clauses:
        clause = clause.strip()
        if not clause:
            continue

        ands = re.split(r"[\s,]+", clause)
        clause_ok = True

        for comp in ands:
            comp = comp.strip()
            if not comp or comp == "*":
                return True

            m = re.match(r"([<>=~^]?)(\*|\d+(?:\.\d+){0,2})", comp)
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
            elif op == "~" or op == "^":
                if v[0] != r[0] or (len(r) > 1 and v[1] > r[1]):
                    clause_ok = False
                    break

        if clause_ok:
            return True
    return False


def __max_major_for_range(version_string: str) -> int | None:
    last_ok = None
    for major in NODE_RELEASES.keys():
        major = major.removeprefix("v")
        if __npm_satisfies(major, version_string):
            last_ok = major
    return last_ok


def parse_node_version(version_string: str, major_only: bool = True) -> str | None:
    """
    Parses a Node.js version string to extract the version.
    """

    # Check if range_str is single concrete version → major match
    if re.match(r"^\d+(?:\.\d+(?:\.\d+)?)?$", version_string.strip()):
        return version_string

    return str(__max_major_for_range(version_string))
