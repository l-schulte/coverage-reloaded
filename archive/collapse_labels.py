#!/usr/bin/env python3
"""Collapse the problematic+unclear rows of failure_labels_project.csv into
error families so they can be reviewed at scale instead of one-by-one.

Outputs two complementary views:
1. projects/<project>/failure_labels_collapsed_by_rule.csv
   Collapsed by auto_classify rule (from failure_patterns.json). This is the
   primary view for reclassification because assessment and resolution operate
   at the rule level.
2. projects/<project>/failure_labels_collapsed_problematic_unclear.csv (and alias
   failure_labels_collapsed_by_signature.csv)
   Collapsed by normalized keyword / test title. Useful for decomposing broad
   rules or inspecting specific test assertions.
"""
import collections
import csv
import json
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT = sys.argv[1] if len(sys.argv) > 1 else os.path.basename(os.getcwd())

SRC = os.path.join(REPO_ROOT, "projects", PROJECT, "failure_labels_project.csv")
PATTERNS_PATH = os.path.join(REPO_ROOT, "projects", PROJECT, "failure_patterns.json")
LOGS_DIR = os.path.join(REPO_ROOT, "projects", PROJECT, "logs")

OUT_SIG = os.path.join(
    REPO_ROOT, "projects", PROJECT, "failure_labels_collapsed_problematic_unclear.csv"
)
OUT_SIG_ALIAS = os.path.join(
    REPO_ROOT, "projects", PROJECT, "failure_labels_collapsed_by_signature.csv"
)
OUT_RULE = os.path.join(
    REPO_ROOT, "projects", PROJECT, "failure_labels_collapsed_by_rule.csv"
)

TARGET_LABELS = ("problematic", "unclear")


def normalize(s):
    """Normalize a failure keyword / test title line into a stable signature."""
    s = re.sub(r"\d{4}-\d{2}-\d{2}T[0-9:.Z]+", "", s)
    s = re.sub(r"/coverage_reloaded/repo", "", s)
    s = re.sub(r"0x[0-9a-fA-F]+", "", s)
    s = re.sub(r"[0-9a-f]{8,}", "H", s)
    s = re.sub(r"\b[0-9]+\b", "N", s)
    s = re.sub(r'"[^"]*"', "Q", s)
    s = re.sub(r"\s+", " ", s).strip()
    s = re.sub(r"^\[\] ?", "", s)
    return s[:160]


def load_rules():
    """Load auto_classify rules from failure_patterns.json."""
    rules_by_id = {}
    compiled_rules = []
    if os.path.isfile(PATTERNS_PATH):
        try:
            with open(PATTERNS_PATH) as fh:
                pdata = json.load(fh)
            for r in pdata.get("auto_classify", []):
                rid = r.get("id")
                if rid:
                    rules_by_id[rid] = r
                    pattern = r.get("match", "")
                    if pattern:
                        try:
                            compiled_rules.append(
                                (re.compile(pattern, re.MULTILINE), r)
                            )
                        except re.error:
                            pass
        except Exception as e:
            print(f"Warning: could not load {PATTERNS_PATH}: {e}")
    return rules_by_id, compiled_rules


def resolve_rule_for_row(r, rules_by_id, compiled_rules):
    """Determine the auto_classify rule for a row in failure_labels_project.csv."""
    rid = r.get("auto_rule_id", "").strip()
    if rid and rid in rules_by_id:
        return rid, rules_by_id[rid]

    # Attempt to resolve from log context if auto_rule_id was not populated
    log_path = os.path.join(LOGS_DIR, f"{r['run_id']}.log")
    if os.path.isfile(log_path) and compiled_rules:
        line_num = int(r.get("line_number") or 1)
        try:
            with open(log_path, "r", errors="replace") as lf:
                lines = lf.readlines()
            start = max(0, line_num - 2)
            end = min(len(lines), line_num + 30)
            ctx = "".join(lines[start:end])
            for rx, rule_meta in compiled_rules:
                if rx.search(ctx):
                    return rule_meta.get("id", ""), rule_meta
        except Exception:
            pass

    fallback_id = f"(no rule: {normalize(r['keyword'])[:50]})"
    fallback_meta = {
        "id": fallback_id,
        "match": normalize(r["keyword"]),
        "label": "unassigned",
        "note": "",
    }
    return fallback_id, fallback_meta


def collapse_by_signature(target_rows):
    """Collapse target rows by normalized keyword signature."""
    fams = collections.defaultdict(
        lambda: {
            "labels": collections.Counter(),
            "fps": set(),
            "occ": 0,
            "runs": set(),
            "raw": "",
            "first": "~",
            "last": "",
        }
    )
    for r in target_rows:
        key = normalize(r["keyword"])
        f = fams[key]
        f["labels"][r["label"]] += 1
        f["fps"].add(r["fingerprint"])
        f["occ"] += int(r.get("occurrences") or 0)
        f["runs"].add(r["run_id"])
        if not f["raw"]:
            f["raw"] = r["keyword"].strip()
        if r["run_id"] < f["first"]:
            f["first"] = r["run_id"]
        if r["run_id"] > f["last"]:
            f["last"] = r["run_id"]

    out_rows = []
    for key, f in fams.items():
        runs = sorted(f["runs"])
        sample = ",".join(runs[:5])
        if len(runs) > 5:
            sample += ",..."
        out_rows.append(
            {
                "family_signature": key,
                "label_breakdown": ";".join(
                    f"{k}:{v}" for k, v in f["labels"].most_common()
                ),
                "n_fingerprints": len(f["fps"]),
                "total_occurrences": f["occ"],
                "n_runs": len(runs),
                "first_run": f["first"],
                "last_run": f["last"],
                "example_run_ids": sample,
                "example_keyword": f["raw"][:200],
            }
        )

    out_rows.sort(key=lambda r: (-r["total_occurrences"], -r["n_fingerprints"]))
    return out_rows


def collapse_by_rule(target_rows, rules_by_id, compiled_rules):
    """Collapse target rows by auto_classify rule ID / pattern."""
    fams = collections.defaultdict(
        lambda: {
            "labels": collections.Counter(),
            "fps": set(),
            "occ": 0,
            "runs": set(),
            "raw": "",
            "first": "~",
            "last": "",
            "rule_meta": {},
        }
    )
    for r in target_rows:
        rid, rule_meta = resolve_rule_for_row(r, rules_by_id, compiled_rules)
        f = fams[rid]
        f["rule_meta"] = rule_meta
        f["labels"][r["label"]] += 1
        f["fps"].add(r["fingerprint"])
        f["occ"] += int(r.get("occurrences") or 0)
        f["runs"].add(r["run_id"])
        if not f["raw"]:
            f["raw"] = r["keyword"].strip()
        if r["run_id"] < f["first"]:
            f["first"] = r["run_id"]
        if r["run_id"] > f["last"]:
            f["last"] = r["run_id"]

    out_rows = []
    for rid, f in fams.items():
        runs = sorted(f["runs"])
        sample = ",".join(runs[:5])
        if len(runs) > 5:
            sample += ",..."
        meta = f["rule_meta"]
        out_rows.append(
            {
                "rule_id": rid,
                "rule_pattern": meta.get("match", "")[:160],
                "rule_label": meta.get("label", ""),
                "label_breakdown": ";".join(
                    f"{k}:{v}" for k, v in f["labels"].most_common()
                ),
                "n_fingerprints": len(f["fps"]),
                "total_occurrences": f["occ"],
                "n_runs": len(runs),
                "first_run": f["first"],
                "last_run": f["last"],
                "example_run_ids": sample,
                "example_keyword": f["raw"][:200],
            }
        )

    out_rows.sort(key=lambda r: (-r["total_occurrences"], -r["n_fingerprints"]))
    return out_rows


def main():
    if not os.path.isfile(SRC):
        sys.exit(f"Error: source file not found: {SRC}")

    rows = list(csv.DictReader(open(SRC)))
    target_rows = [r for r in rows if r["label"] in TARGET_LABELS]
    n_prob = sum(1 for r in rows if r["label"] == "problematic")
    n_unclear = sum(1 for r in rows if r["label"] == "unclear")

    rules_by_id, compiled_rules = load_rules()

    # 1. Signature collapse
    sig_rows = collapse_by_signature(target_rows)
    sig_cols = [
        "family_signature",
        "label_breakdown",
        "n_fingerprints",
        "total_occurrences",
        "n_runs",
        "first_run",
        "last_run",
        "example_run_ids",
        "example_keyword",
    ]
    with open(OUT_SIG, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=sig_cols)
        w.writeheader()
        w.writerows(sig_rows)

    with open(OUT_SIG_ALIAS, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=sig_cols)
        w.writeheader()
        w.writerows(sig_rows)

    # 2. Rule collapse
    rule_rows = collapse_by_rule(target_rows, rules_by_id, compiled_rules)
    rule_cols = [
        "rule_id",
        "rule_pattern",
        "rule_label",
        "label_breakdown",
        "n_fingerprints",
        "total_occurrences",
        "n_runs",
        "first_run",
        "last_run",
        "example_run_ids",
        "example_keyword",
    ]
    with open(OUT_RULE, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=rule_cols)
        w.writeheader()
        w.writerows(rule_rows)

    print(f"wrote rule-collapsed file:      {OUT_RULE}")
    print(f"  rule families:                {len(rule_rows)}")
    print(f"wrote signature-collapsed file: {OUT_SIG}")
    print(f"  signature families:           {len(sig_rows)}")
    print(f"source target rows:             problematic={n_prob}, unclear={n_unclear}")


if __name__ == "__main__":
    main()
