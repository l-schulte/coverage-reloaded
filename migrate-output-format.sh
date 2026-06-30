#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# migrate-output-format.sh
#
# Migrates per-commit coverage output from the old flat-file naming conventions
# to the new per-commit directory structure:  projects/<p>/output/{ts}_{hash}/
#
# Handles all historical naming conventions found across projects:
#   A) {ts}_{hash}__{suite}.lcov  +  {ts}_{hash}__{suite}__exitN.exit_code
#   B) {hash}__{suite}.lcov       +  {hash}__{suite}.exit_code
#   C) {hash}.lcov                (no suite, no exit code)
#   D) {ts}_{hash}__{suite}.lcov  (no exit code)
#   E) {ts}_{hash}.lcov           (no suite, no exit code)
#
# Also cleans up stale .error files that coexist with lcov data (re-run
# artifacts).
#
# Idempotent — safe to run multiple times. Already-migrated directories are
# skipped.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[MIGRATE] $*"; }
warn() { echo "[MIGRATE] WARNING: $*" >&2; }
err()  { echo "[MIGRATE] ERROR: $*" >&2; }

# ── Detect if a commit is already migrated ───────────────────────────────────
# A commit is considered migrated if output/<prefix>/ is a directory containing
# at least one .lcov file.
is_migrated() {
    local output_dir="$1" prefix="$2"
    [ -d "$output_dir/$prefix" ] && [ -n "$(find "$output_dir/$prefix" -maxdepth 1 -name '*.lcov' -print -quit 2>/dev/null)" ]
}

# ── Process one project ──────────────────────────────────────────────────────

process_project() {
    local project_dir="$1"
    local project_name
    project_name="$(basename "$project_dir")"
    local output_dir="$project_dir/output"

    if [ ! -d "$output_dir" ]; then
        log "SKIP  $project_name — no output directory"
        return 0
    fi

    log "──── $project_name ────"

    # ── Phase 0: Clean up partially migrated directories ───────────────────
    # A directory with flat files sharing the same prefix is a partial
    # migration from a previous interrupted run. Remove the dir so Phase 1
    # can re-process all files cleanly.
    for d in "$output_dir"/*/; do
        [ -d "$d" ] || continue
        local dir_prefix
        dir_prefix="$(basename "$d")"

        # Count flat lcov files with this prefix still remaining
        local flat_count=0
        for f in "$output_dir"/"${dir_prefix}"__*.lcov; do
            [ -f "$f" ] && flat_count=$((flat_count + 1))
        done

        if [ "$flat_count" -gt 0 ]; then
            log "  PARTIAL  $dir_prefix — dir exists with $flat_count flat file(s) remaining — re-migrating"
            rm -rf "$d"
        fi
    done
    unset dir_prefix flat_count

    # ── Phase 1: Scan all files and group by commit prefix ─────────────────
    # We do a two-pass approach:
    #   Pass 1: collect all files grouped by commit prefix
    #   Pass 2: migrate each group
    declare -A commit_files

    shopt -s nullglob
    local all_files=("$output_dir"/*)

    for f in "${all_files[@]}"; do
        [ -f "$f" ] || continue
        local basename_f
        basename_f="$(basename "$f")"

        # Skip directories, error markers, not_applicable markers, and log files
        if [ -d "$f" ]; then
            # Check if it's already a migrated directory — skip if so
            if is_migrated "$output_dir" "$(basename "$f")"; then
                :  # already done, skip
            fi
            continue
        fi

        case "$basename_f" in
            *.error|*.not_applicable|*.log)
                continue
                ;;
        esac

        # ── Extract commit prefix ──────────────────────────────────────────
        local prefix=""

        # Pattern 1: {timestamp}_{hash}__{suite}.lcov  or  __exitN.exit_code
        if [[ "$basename_f" =~ ^([0-9]+_[a-f0-9]+)__ ]]; then
            prefix="${BASH_REMATCH[1]}"
        # Pattern 2: {hash}__{suite}.lcov  or  {hash}__{suite}.exit_code  (no timestamp)
        elif [[ "$basename_f" =~ ^([a-f0-9]+)__ ]]; then
            prefix="${BASH_REMATCH[1]}"
        # Pattern 3: {hash}.lcov  (no suite, no exit code)
        elif [[ "$basename_f" =~ ^([a-f0-9]+)\.lcov$ ]]; then
            prefix="${BASH_REMATCH[1]}"
        # Pattern 4: {timestamp}_{hash}.lcov  (no suite, no exit code)
        elif [[ "$basename_f" =~ ^([0-9]+_[a-f0-9]+)\.lcov$ ]]; then
            prefix="${BASH_REMATCH[1]}"
        fi

        if [ -z "$prefix" ]; then
            warn "$project_name: unrecognized file pattern: $basename_f — skipping"
            continue
        fi

        # Skip if already migrated
        if is_migrated "$output_dir" "$prefix"; then
            continue
        fi

        # Classify file and store
        local safe_key="k_${prefix}"
        if [[ "$basename_f" == *.lcov ]]; then
            if [ -z "${commit_files[$safe_key]:-}" ]; then
                commit_files["$safe_key"]="lcov:$f"
            else
                commit_files["$safe_key"]="${commit_files[$safe_key]}|lcov:$f"
            fi
        elif [[ "$basename_f" == *.exit_code ]]; then
            if [ -z "${commit_files[$safe_key]:-}" ]; then
                commit_files["$safe_key"]="exit:$f"
            else
                commit_files["$safe_key"]="${commit_files[$safe_key]}|exit:$f"
            fi
        fi
    done

    # ── Migrate each commit ────────────────────────────────────────────────
    local total=0 migrated=0 skipped=0
    for safe_key in "${!commit_files[@]}"; do
        local prefix="${safe_key#k_}"
        total=$((total + 1))

        # Parse the collected files for this prefix
        IFS='|' read -ra entries <<< "${commit_files[$safe_key]}"
        local lcov_files=() exit_files=()

        for entry in "${entries[@]}"; do
            local kind="${entry%%:*}"
            local path="${entry#*:}"
            if [ "$kind" = "lcov" ]; then
                lcov_files+=("$path")
            elif [ "$kind" = "exit" ]; then
                exit_files+=("$path")
            fi
        done

        # Check if ALL suites for this commit are already migrated.
        # We check by counting how many lcov files would end up in the dir.
        if is_migrated "$output_dir" "$prefix"; then
            # Verify the directory has the right number of .lcov files
            local existing_count=0
            if [ -d "$output_dir/$prefix" ]; then
                existing_count=$(find "$output_dir/$prefix" -maxdepth 1 -name '*.lcov' | wc -l)
            fi
            if [ "${#lcov_files[@]}" -eq "$existing_count" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            # Partial migration — clean up and redo
            log "  PARTIAL  $prefix — expected ${#lcov_files[@]} lcov files, found $existing_count — re-migrating"
            rm -rf "$output_dir/$prefix"
        fi

        local commit_dir="$output_dir/$prefix"
        mkdir -p "$commit_dir"

        # Process each lcov file and find its matching exit file
        for lcov_f in "${lcov_files[@]}"; do
            local lcov_basename
            lcov_basename="$(basename "$lcov_f")"

            # Determine suite name
            local suite_name
            suite_name="${lcov_basename#"${prefix}__"}"
            if [ "$suite_name" = "$lcov_basename" ]; then
                suite_name="coverage"
            fi
            suite_name="${suite_name%.lcov}"
            suite_name="${suite_name//\//_}"
            suite_name="${suite_name//-/_}"

            # Find matching exit file.
            # Exit files are named: {prefix}__{suite}__exitN.exit_code
            # or {prefix}__{suite}.exit_code
            # We match by checking that the portion after {prefix}__ starts with
            # {suite_name} and ends with .exit_code.
            local matched_exit=""
            local exit_idx=0
            for exit_f in "${exit_files[@]}"; do
                local exit_basename
                exit_basename="$(basename "$exit_f")"
                local exit_suffix="${exit_basename#"${prefix}__"}"
                if [ "$exit_suffix" != "$exit_basename" ]; then
                    # exit_suffix is like "integration__exit56.exit_code" or "coverage_client_client__exit0.exit_code"
                    local exit_suite="${exit_suffix%%.exit_code}"
                    exit_suite="${exit_suite%__exit*}"
                    if [ "$exit_suite" = "$suite_name" ]; then
                        matched_exit="$exit_f"
                        unset 'exit_files[exit_idx]'
                        break
                    fi
                fi
                exit_idx=$((exit_idx + 1))
            done

            # Copy files into the commit directory
            cp "$lcov_f" "$commit_dir/${suite_name}.lcov"
            log "  [OK]  $(basename "$lcov_f") → $prefix/${suite_name}.lcov"
            if [ -n "$matched_exit" ]; then
                cp "$matched_exit" "$commit_dir/${suite_name}.exit_code"
                log "  [OK]  $(basename "$matched_exit") → $prefix/${suite_name}.exit_code"
            fi

            # Remove old flat files
            rm -f "$lcov_f"
            [ -n "$matched_exit" ] && rm -f "$matched_exit"

            migrated=$((migrated + 1))
        done

        # Handle any remaining exit files that didn't match an lcov file
        for exit_f in "${exit_files[@]}"; do
            warn "$project_name: orphaned exit file for $prefix: $(basename "$exit_f")"
        done
    done

    # ── Clean up stale .error files that coexist with migrated data ────────
    for f in "$output_dir"/*.error; do
        [ -f "$f" ] || continue
        local basename_f
        basename_f="$(basename "$f")"
        local prefix="${basename_f%.error}"

        if is_migrated "$output_dir" "$prefix"; then
            log "  CLEANUP  removing stale .error (coverage exists): $basename_f"
            rm -f "$f"
        fi
    done

    log "  DONE  $project_name — $total commit(s) processed, $migrated migrated, $skipped already done"
    echo ""
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    log "Starting output format migration"
    log ""

    # Process projects/ and archive/ directories
    for dir in "$BASEDIR/projects" "$BASEDIR/archive"; do
        if [ ! -d "$dir" ]; then
            continue
        fi
        for project_dir in "$dir"/*/; do
            [ -d "$project_dir" ] || continue
            process_project "$project_dir"
        done
    done

    log "Migration complete"
}

main "$@"
