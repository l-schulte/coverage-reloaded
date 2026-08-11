#!/usr/bin/env bash
# Scrapes the public GitHub Releases page for paritytech/substrate and builds
# a TSV of every Release with its actual "published" date, tag name, and
# resolved commit SHA. Avoids the GitHub REST API entirely (no rate limits) -
# uses the public HTML page, paginated with ?page=N (10 releases/page).
#
# Output: releases_dated.tsv, columns: published_at(ISO8601) \t tag \t commit_sha
#
# Usage: ./make_release_tsv.sh

set -euo pipefail

OWNER="paritytech"
REPO="substrate"
UA="Mozilla/5.0"

mkdir -p pages
page=1
while :; do
    out="pages/releases_page${page}.html"
    curl -s -A "$UA" "https://github.com/${OWNER}/${REPO}/releases?page=${page}" -o "$out"
    # stop once a page has no release tag links at all
    if ! grep -q "/releases/tag/" "$out"; then
        rm -f "$out"
        break
    fi
    page=$((page + 1))
    sleep 0.5
done

echo "Fetched $((page - 1)) release pages."

python3 - <<'PYEOF'
import glob
import subprocess
from urllib.parse import unquote
from bs4 import BeautifulSoup

releases = {}  # tag -> published_at
for path in sorted(glob.glob("pages/releases_page*.html")):
    soup = BeautifulSoup(open(path), "html.parser")
    links = soup.find_all("a", href=lambda h: h and "/releases/tag/" in h)
    seen_on_page = {}
    for a in links:
        href = a["href"]
        tag = unquote(href.rsplit("/", 1)[-1])
        if tag in seen_on_page:
            continue
        seen_on_page[tag] = a
    for tag, a in seen_on_page.items():
        if tag in releases:
            continue
        node = a
        published = None
        for _ in range(10):
            node = node.parent
            if node is None:
                break
            rt = node.find("relative-time")
            if rt and rt.parent.get("class"):
                published = rt.get("datetime")
                break
        releases[tag] = published

print(f"Found {len(releases)} releases across all pages.")

# Resolve tag -> commit SHA via git ls-remote (only for these ~tag names, cheap).
raw = subprocess.check_output(
    ["git", "ls-remote", "--tags", "https://github.com/paritytech/substrate.git"]
).decode()

commit = {}
for line in raw.splitlines():
    sha, ref = line.split("\t")
    ref = ref.removeprefix("refs/tags/")
    deref = ref.endswith("^{}")
    if deref:
        ref = ref[:-3]
    if ref not in releases:
        continue
    if deref:
        commit[ref] = sha
    elif ref not in commit:
        commit[ref] = sha

rows = []
for tag, published in releases.items():
    sha = commit.get(tag, "UNKNOWN")
    rows.append((published or "UNKNOWN", tag, sha))

rows.sort()
with open("releases_dated.tsv", "w") as out:
    for published, tag, sha in rows:
        out.write(f"{published}\t{tag}\t{sha}\n")

print(f"Wrote {len(rows)} rows to releases_dated.tsv")
PYEOF

echo "Preview:"
head -5 releases_dated.tsv
echo "..."
tail -5 releases_dated.tsv