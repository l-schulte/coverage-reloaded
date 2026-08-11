#!/usr/bin/env python3
"""
Build a CSV mapping commit timestamps → Docker tags for parity/substrate.

Reads two inputs:
  - releases_dated.tsv:  release_date, release_name, commit_hash
  - substrate_tags.tsv:  docker_tag, last_updated, digest

For each release, finds the Docker tag whose hash suffix matches the commit hash
(trying 7, 8, 10, 11, 12 character prefixes).  Produces a CSV that can be used
at runtime to pick the right substrate image for a given commit timestamp.

Output: substrate_lookup.csv (columns: release_date_epoch, docker_tag)
"""

import csv
import sys

RELEASES_FILE = "releases_dated.tsv"
TAGS_FILE = "substrate_tags.tsv"
OUTPUT_FILE = "substrate_lookup.csv"

# ── Load Docker tags ──────────────────────────────────────────────────────────
# Build a dict: hash_suffix → docker_tag  (for all hash lengths)
tag_by_hash = {}  # str -> str
tag_by_date = []  # (date_str, tag)

with open(TAGS_FILE) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        tag = parts[0].strip()
        date_str = parts[1].strip() if len(parts) > 1 else ""
        # Extract the hash suffix: everything after the last '-'
        if "-" in tag:
            suffix = tag.rsplit("-", 1)[1]
            tag_by_hash[suffix] = tag
            tag_by_date.append((date_str, tag))

# Also index by shorter prefixes of each suffix
all_suffixes = list(tag_by_hash.keys())
for suffix in all_suffixes:
    for length in range(7, len(suffix)):
        prefix = suffix[:length]
        if prefix not in tag_by_hash:
            tag_by_hash[prefix] = tag_by_hash[suffix]

# ── Load releases and match ──────────────────────────────────────────────────
rows = []
unmatched = []

with open(RELEASES_FILE) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("\t")
        release_date = parts[0].strip()
        release_name = parts[1].strip()
        commit_hash = parts[2].strip()

        # Try matching from longest prefix to shortest
        matched_tag = None
        for length in range(min(12, len(commit_hash)), 6, -1):
            prefix = commit_hash[:length]
            if prefix in tag_by_hash:
                matched_tag = tag_by_hash[prefix]
                break

        # Convert ISO date to epoch timestamp
        from datetime import datetime, timezone

        try:
            dt = datetime.fromisoformat(release_date.replace("Z", "+00:00"))
            epoch = int(dt.timestamp())
        except Exception:
            epoch = 0

        rows.append((epoch, release_date, release_name, commit_hash, matched_tag or ""))
        if not matched_tag:
            unmatched.append(release_name)

    # ── Write output CSV: only rows with a matched tag ────────────────────────
    # Empty tags would break the runtime lookup (the last row with epoch ≤
    # timestamp would overwrite a valid match with nothing).
    rows_with_tag = [(e, t) for e, _, _, _, t in rows if t]
    rows_with_tag.sort(key=lambda r: r[0])

with open(OUTPUT_FILE, "w", newline="") as f:
    w = csv.writer(f)
    # Simplified: just epoch and tag, with epoch 0 = use :latest
    w.writerow(["epoch", "docker_tag"])
    for epoch, tag in rows_with_tag:
        w.writerow([epoch, tag])

# ── Summary ──────────────────────────────────────────────────────────────────
matched_count = len(rows_with_tag)
total = len(rows)
print(f"Total releases: {total}")
print(f"Matched to Docker tag: {matched_count}")
print(f"Unmatched: {total - matched_count}")
if unmatched:
    print(f'Unmatched releases: {", ".join(unmatched[:10])}')
    if len(unmatched) > 10:
        print(f"  ... and {len(unmatched)-10} more")
print(f"Written to {OUTPUT_FILE}")
