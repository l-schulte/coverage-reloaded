"""failure_patterns.json loading, suite resolution and auto-classify rules."""

import json
import os
import re
import uuid

from . import paths
from .paths import REPO_ROOT

EXAMPLE_CONFIG = os.path.join(REPO_ROOT, "failure_patterns.example.json")

ALL_LABELS = [
    "acceptable",
    "problematic",
    "unclear",
    "false_positive",
    "reevaluated_acceptable",
]


def load_pattern_config(project):
    path = paths.patterns_path(project)
    if not os.path.isfile(path):
        raise SystemExit(
            f"[error] no failure_patterns.json for project {project!r}\n"
            f"        create one first (see failure_patterns.example.json)"
        )
    with open(path) as f:
        return json.load(f)


def compile_patterns(patterns):
    return [re.compile(p) for p in patterns]


def resolve_patterns(cfg, suite=None):
    general = cfg.get("general", {})
    patterns = list(general.get("patterns", []))
    excludes = list(general.get("exclude", []))
    if suite is not None:
        ov = cfg.get("suites", {}).get(suite, {})
        for p in ov.get("remove_patterns", []):
            if p in patterns:
                patterns.remove(p)
        patterns += ov.get("add_patterns", [])
        for p in ov.get("remove_exclude", []):
            if p in excludes:
                excludes.remove(p)
        excludes += ov.get("add_exclude", [])
    return compile_patterns(patterns), compile_patterns(excludes)


def gen_rule_id():
    return uuid.uuid4().hex[:12]


def load_auto_rules(project):
    cfg = load_pattern_config(project)
    out = []
    for r in cfg.get("auto_classify", []):
        match = r.get("match")
        label = r.get("label")
        if match and label in ALL_LABELS:
            out.append((match, label, r.get("note", ""),
                        int(r.get("lines", 5)), r.get("id", "")))
    return out


def add_auto_rule(project, body, label, note="", lines=5, window=None):
    path = paths.patterns_path(project)
    with open(path) as f:
        cfg = json.load(f)
    rid = gen_rule_id()
    rule = {
        "match": re.escape(body),
        "label": label,
        "note": note,
        "lines": lines,
        "id": rid,
        # Marks the rule as v2-generated so it can be told apart from rules
        # created by the v1 tool (which have no `generated_by` field).
        "generated_by": "check_failures_v2",
    }
    if window:
        rule["window"] = window
    cfg.setdefault("auto_classify", []).append(rule)
    with open(path, "w") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    return rid
