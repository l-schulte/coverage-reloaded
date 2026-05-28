#!/usr/bin/env bash
# cypress-patcher.sh
#
# Runtime patcher for Cypress coverage config files.
# Called from install-and-run.sh after git checkout.
#
# Scans the repository for files listed in mapper.tsv, verifies their
# content SHA256 matches, and replaces them with coverage-enabled patches.
#
# Patch file naming: {sha256}__{filename}.patch  (e.g. "abc123__cypress.json.patch")
# The patcher looks for a file starting with {sha256} in the patches directory,
# so the mapper's patch_file column is optional.
#
# Usage: ./cypress-patcher.sh <repo_dir> <mapper.tsv> <patches_dir>
#
#   repo_dir     — root of the checked-out repository
#   mapper       — path to mapper.tsv (sha256_original  path)
#   patches_dir  — directory containing {sha256}__*.patch files

set -euo pipefail

if [ $# -lt 3 ]; then
    echo "Usage: $0 <repo_dir> <mapper.tsv> <patches_dir>"
    exit 1
fi

REPO_DIR="$1"
MAPPER="$2"
PATCHES="$3"

if [ ! -d "$REPO_DIR" ]; then echo "ERROR: $REPO_DIR not found"; exit 1; fi
if [ ! -f "$MAPPER" ]; then echo "ERROR: $MAPPER not found"; exit 1; fi
if [ ! -d "$PATCHES" ]; then echo "ERROR: $PATCHES not found"; exit 1; fi

applied=0
skipped=0
missing=0

echo "==> cypress-patcher.sh — applying coverage patches"

# Build a quick lookup: hash → patch file path
declare -A PATCH_LOOKUP
while IFS= read -r f; do
    b=$(basename "$f")
    # Extract SHA256 prefix (before the first __)
    sha="${b%%__*}"
    PATCH_LOOKUP["$sha"]="$f"
done < <(find "$PATCHES" -name "*.patch" -type f)

echo "  Found ${#PATCH_LOOKUP[@]} patches available"

# Read mapper.tsv line by line (skip header line if present)
first_line=true
while IFS=$'\t' read -r expected_hash rel_path _; do
    # Skip header line if it matches the expected header
    if [ "$first_line" = true ] && [ "$expected_hash" = "sha256_original" ]; then
        first_line=false
        continue
    fi
    first_line=false

    target="$REPO_DIR/$rel_path"

    # Skip if file doesn't exist at this commit
    if [ ! -f "$target" ]; then
        continue
    fi

    # Verify hash
    actual_hash=$(sha256sum "$target" | cut -d' ' -f1)
    if [ "$actual_hash" != "$expected_hash" ]; then
        # Hash mismatch — file content differs from what we extracted
        continue
    fi

    # Look up patch by hash
    patch_file="${PATCH_LOOKUP[$expected_hash]:-}"
    if [ -z "$patch_file" ]; then
        echo "  [MISS] $rel_path — no patch for hash $expected_hash"
        missing=$((missing + 1))
        continue
    fi

    cp "$patch_file" "$target"
    echo "  [PATCH] $expected_hash $rel_path"
    applied=$((applied + 1))
done < "$MAPPER"

echo "==> Done — $applied patches applied, $missing missing"
