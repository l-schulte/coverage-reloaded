#!/usr/bin/env bash
# bin_excess_commits.sh — bin excess coverage commits for manual deletion.
# Usage: bash scripts/bin_excess_commits.sh <project_name> [--apply]
# Default: dry-run. Moves entries in MAIN output/ & logs/ whose commit hash
# is NOT in the freshly regenerated commits.csv into <project>/bin/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_DIR="$ROOT/projects"

APPLY=0
PROJECT=""
for arg in "$@"; do
  case "$arg" in
    --apply)   APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) PROJECT="$arg" ;;
  esac
done

[[ -n "$PROJECT" ]] || { echo "Usage: bash helper/bin_excess_commits.sh <project_name> [--apply]" >&2; exit 2; }

PROJ="$PROJECTS_DIR/$PROJECT"
[[ -d "$PROJ" ]] || { echo "No such project: $PROJECT" >&2; exit 1; }
CSV="$PROJ/commits.csv"
[[ -f "$CSV" ]] || { echo "[skip] $PROJECT: no commits.csv — run 'main.py --mode commits-only' first." >&2; exit 1; }

declare -A keep_set
while IFS=, read -r hash _; do
  [[ -n "$hash" ]] && keep_set["$hash"]=1
done < <(tail -n +2 "$CSV")
total_commits=${#keep_set[@]}

declare -A collected_set
count_excess=0

for dir in output logs; do
  src="$PROJ/$dir"
  [[ -d "$src" ]] || continue
  dest="$PROJ/bin/$dir"
  for entry in "$src"/*; do
    [[ -e "$entry" ]] || continue
    base="$(basename "$entry")"
    hash="${base%.*}"; hash="${hash#*_}"
    if [[ -n "${keep_set[$hash]:-}" ]]; then
      collected_set["$hash"]=1
    else
      count_excess=$((count_excess+1))
      if (( APPLY )); then mkdir -p "$dest"; mv "$entry" "$dest/"; fi
    fi
  done
done

not_yet=$(( total_commits - ${#collected_set[@]} ))
echo "=========================================="
echo "Project: $PROJECT"
echo "  Total commits in new commits.csv : $total_commits"
echo "  Excess entries moved to bin      : $count_excess"
echo "  Not yet collected (need running) : $not_yet"
(( APPLY )) || echo "  MODE: dry-run (nothing moved). Use --apply to move."
echo "=========================================="
