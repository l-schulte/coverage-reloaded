#!/usr/bin/env bash
# discover-cypress-configs.sh
#
# Scans a git repository's history for all files relevant to Cypress coverage
# configuration, extracts their contents at introducing commits, and builds
# a mapper file (hash → path) to enable runtime patching.
#
# Usage: ./discover-cypress-configs.sh <repo_dir> [output_dir]
#
#   repo_dir    — path to the git repository
#   output_dir  — where to write results (default: ./cypress-coverage-configs)
#
# Output structure:
#   output_dir/
#     originals/          — extracted file contents at introducing commits
#     patches/            — place {sha256}__{basename}.patch files here
#     mapper.tsv          — tab-separated: sha256_original  path (consumed by cypress-patcher.sh)
#
# Workflow:
#   1. Run this script to extract originals and build mapper.tsv
#   2. Create coverage-enabled patch files in patches/, named {sha256}__{basename}.patch
#      where sha256 matches the first column in mapper.tsv
#   3. At runtime, cypress-patcher.sh uses mapper.tsv + patches/ to apply them

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <repo_dir> [output_dir]"
    exit 1
fi

REPO_DIR="$(cd "$1" && pwd)"
OUTPUT_DIR="$(cd "$(dirname "${2:-$1/../cypress-coverage-configs}")" && pwd)/$(basename "${2:-$1/../cypress-coverage-configs}")"

cd "$REPO_DIR"

ORIGINALS_DIR="$OUTPUT_DIR/originals"
PATCHES_DIR="$OUTPUT_DIR/patches"
MAPPER_FILE="$OUTPUT_DIR/mapper.tsv"

mkdir -p "$ORIGINALS_DIR" "$PATCHES_DIR"

echo "=========================================="
echo " discover-cypress-configs.sh"
echo " Repo:   $REPO_DIR"
echo " Output: $OUTPUT_DIR"
echo "=========================================="

# -------------------------------------------------------------------
# Step 1: Scan git log for coverage-relevant files
# -------------------------------------------------------------------
echo "==> Scanning git history..."

SUMMARY=$(mktemp)
echo -e "commit_hash\tdate\tauthor\tevent\tpath\tsubject" > "$SUMMARY"

git log --all \
    --diff-filter=ADMR \
    --name-status \
    --pretty=format:"COMMIT:%H|%aI|%an|%s" \
    -- \
    ':(glob)**/cypress.config.ts' \
    ':(glob)**/cypress.config.js' \
    ':(glob)**/cypress.config.mjs' \
    ':(glob)**/cypress.config.cjs' \
    ':(glob)**/cypress.json' \
    ':(glob)**/.cypress.json' \
    ':(glob)**/cypress.env.json' \
    ':(glob)**/cypress/support/index.js' \
    ':(glob)**/cypress/support/index.ts' \
    ':(glob)**/cypress/plugins/index.js' \
    ':(glob)**/cypress/plugins/index.ts' \
    ':(glob)**/vite.config.ts' \
    ':(glob)**/vite.config.js' \
    ':(glob)**/vite.config.mjs' \
    ':(glob)**/vite.config.mts' \
    ':(glob)**/vite.config.cjs' \
    ':(glob)**/.nycrc' \
    ':(glob)**/.nycrc.json' \
    ':(glob)**/.nycrc.yaml' \
    ':(glob)**/.nycrc.yml' \
| awk '
    /^COMMIT:/ {
        split(substr($0,8), p, "|")
        h=p[1]; d=p[2]; a=p[3]; s=p[4]
    }
    /^[ADMR]\t/ {
        e=substr($1,1,1); f=substr($0,index($0,"\t")+1)
        print h "\t" d "\t" a "\t" e "\t" f "\t" s
    }
' >> "$SUMMARY"

event_count=$(tail -n +2 "$SUMMARY" | wc -l)
echo "  Found $event_count file events"

# -------------------------------------------------------------------
# Step 2: Extract originals and build mapper
# -------------------------------------------------------------------
echo "==> Extracting originals and computing SHA256 hashes..."
echo -e "sha256_original\tpath" > "$MAPPER_FILE"

# Track seen hashes to avoid duplicates (same file version at different commits)
declare -A SEEN_HASHES

while IFS=$'\t' read -r hash date author event path subject; do
    [[ "$event" != "A" && "$event" != "M" ]] && continue

    safe_name="${path//\//__}"
    short_hash="${hash:0:10}"
    safe_date="${date//:/-}"
    safe_date="${safe_date//+/p}"
    out_file="$ORIGINALS_DIR/${safe_date}__${short_hash}__${safe_name}"

    # Write directly from git to preserve trailing newlines (command subst strips them)
    if ! git show "${hash}:${path}" > "$out_file" 2>/dev/null; then
        echo "  [WARN] Could not extract $path @ $short_hash"
        rm -f "$out_file"
        continue
    fi
    file_hash=$(sha256sum "$out_file" | cut -d' ' -f1)

    # Skip if we already have this exact content version
    if [[ -n "${SEEN_HASHES[$file_hash]:-}" ]]; then
        # Keep the original file (it's referenced by multiple mapper entries)
        # but don't create a duplicate
        echo -e "${file_hash}\t${path}" >> "$MAPPER_FILE"
        echo "  [DUP] $safe_date  $short_hash  $path  (same content as ${SEEN_HASHES[$file_hash]})"
        continue
    fi
    SEEN_HASHES["$file_hash"]="$path"
    echo -e "${file_hash}\t${path}" >> "$MAPPER_FILE"
    echo "  [OK]  $safe_date  $short_hash  $path"
done < <(tail -n +2 "$SUMMARY")

original_count=$(ls "$ORIGINALS_DIR" 2>/dev/null | wc -l)
mapper_count=$(tail -n +2 "$MAPPER_FILE" | wc -l)
echo ""
echo "==> Done — $original_count originals extracted, $mapper_count entries in mapper"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "Files in output directory:"
echo "  $ORIGINALS_DIR/   — $original_count original file snapshots"
echo "  $PATCHES_DIR/     — place .patch files here (empty for now)"
echo "  $MAPPER_FILE      — $mapper_count entries (hash → path)"
echo ""
echo "Next:"
echo "  1. Create coverage-enabled patch files in: $PATCHES_DIR"
echo "     Name each file {sha256_of_original}__{basename}.patch"
echo "     e.g. abc123def456__cypress.json.patch"
echo "  2. Bake patches/ and mapper.tsv into the Docker image"
echo "  3. Call 'helper/cypress-patcher.sh <repo> <mapper> <patches>'"
echo "     before running tests (it matches by sha256 prefix)"

rm -f "$SUMMARY"
