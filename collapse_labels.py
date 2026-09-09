#!/usr/bin/env python3
"""Collapse the problematic+unclear rows of failure_labels_project.csv into
error families so they can be reviewed by signature instead of one-by-one.

Reads  projects/<project>/failure_labels_project.csv
Writes projects/<project>/failure_labels_collapsed_problematic_unclear.csv

A "family" is a normalized error signature: timestamps, hex blobs, numbers,
quoted strings, and the repo path are stripped so the same root cause across
many commits collapses into one row.
"""
import csv
import os
import re
import sys
import collections

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT = sys.argv[1] if len(sys.argv) > 1 else os.path.basename(os.getcwd())

SRC = os.path.join(REPO_ROOT, "projects", PROJECT, "failure_labels_project.csv")
OUT = os.path.join(REPO_ROOT, "projects", PROJECT,
                  "failure_labels_collapsed_problematic_unclear.csv")

TARGET_LABELS = ("problematic", "unclear")


def normalize(s):
    s = re.sub(r"\d{4}-\d{2}-\d{2}T[0-9:.Z]+", "", s)
    s = re.sub(r"/coverage_reloaded/repo", "", s)
    s = re.sub(r"0x[0-9a-fA-F]+", "", s)
    s = re.sub(r"[0-9a-f]{8,}", "H", s)
    s = re.sub(r"\b[0-9]+\b", "N", s)
    s = re.sub(r'"[^"]*"', "Q", s)
    s = re.sub(r"\s+", " ", s).strip()
    # drop the leading log-frame brackets / severity tokens if present
    s = re.sub(r"^\[\] ?", "", s)
    return s[:160]


def main():
    rows = list(csv.DictReader(open(SRC)))
    fams = collections.defaultdict(lambda: {
        "labels": collections.Counter(),
        "fps": set(),
        "occ": 0,
        "runs": set(),
        "raw": "",
        "first": "~",
        "last": "",
    })
    for r in rows:
        if r["label"] not in TARGET_LABELS:
            continue
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
        out_rows.append({
            "family_signature": key,
            "label_breakdown": ";".join(f"{k}:{v}" for k, v in f["labels"].most_common()),
            "n_fingerprints": len(f["fps"]),
            "total_occurrences": f["occ"],
            "n_runs": len(runs),
            "first_run": f["first"],
            "last_run": f["last"],
            "example_run_ids": sample,
            "example_keyword": f["raw"][:200],
        })

    out_rows.sort(key=lambda r: (-r["total_occurrences"], -r["n_fingerprints"]))
    cols = ["family_signature", "label_breakdown", "n_fingerprints",
            "total_occurrences", "n_runs", "first_run", "last_run",
            "example_run_ids", "example_keyword"]
    with open(OUT, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(out_rows)
    print(f"wrote {OUT}")
    print(f"families: {len(out_rows)}  "
          f"(problematic={sum(1 for r in rows if r['label']=='problematic')}, "
          f"unclear={sum(1 for r in rows if r['label']=='unclear')} source rows)")


if __name__ == "__main__":
    main()
