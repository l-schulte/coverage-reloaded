#!/bin/bash

TEST_TYPE="${1:-}"
PREPEND_PATHS="${2:-false}"  # Pass "true" for workspace monorepos
TEST_EXIT_CODE="${3:-}"      # Exit code from the test suite (0=all passed, >0=number of failures)

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

print_header 2 "Looking for lcov files..." "TEST_TYPE=$TEST_TYPE PREPEND_PATHS=$PREPEND_PATHS TEST_EXIT_CODE=$TEST_EXIT_CODE"

cd /coverage_reloaded/repo

IGNORE_PATTERNS=('*/node_modules/*')
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

mkdir -p "$COVERAGE_REPORT_PATH"

if [ -n "$TEST_TYPE" ]; then
    dest_filename="${TEST_TYPE}.lcov.info"
    exit_code_filename="${TEST_TYPE}.exit_code"
else
    dest_filename="lcov.info"
    exit_code_filename="exit_code"
fi

FILES_MOVED=0
EMPTY_FILES=0

while IFS= read -r -d '' lcov_file; do
    # Check if file has any records before processing
    if ! grep -q '^SF:' "$lcov_file" 2>/dev/null; then
        print_header 4 "WARNING: Empty $lcov_file — skipped & deleted"
        # Still store exit code so we know the suite ran
        if [ -n "$TEST_EXIT_CODE" ]; then
            echo "$TEST_EXIT_CODE" > "$COVERAGE_REPORT_PATH/$exit_code_filename"
            print_header 4 "NOTICE: Stored exit code $TEST_EXIT_CODE in $exit_code_filename"
        fi
        rm "$lcov_file"
        EMPTY_FILES=$((EMPTY_FILES + 1))
        continue
    fi

    dir=$(dirname "$lcov_file")
    rel_path="${dir%/coverage}"
    rel_path="${rel_path#./}"
    dest_dir="$COVERAGE_REPORT_PATH/$rel_path"
    mkdir -p "$dest_dir"

    print_header 4 "NOTICE: Processing $lcov_file"

    # Always strip absolute repo path and co_re_ prefixes
    sed -i "s|$REPOPATH||g" "$lcov_file"
    sed -i 's|co_re_[^/]*\/||g' "$lcov_file"

    # Optionally prepend rel_path to SF: lines before moving
    if [ "$PREPEND_PATHS" = "true" ] && [ -n "$rel_path" ] && [ "$rel_path" != "." ]; then
        awk -v path="$rel_path/" '{
            if ($0 ~ /^SF:/) {
                sub(/^SF:/, "SF:" path)
            }
            print
        }' "$lcov_file" > "$dest_dir/$dest_filename"
        rm "$lcov_file"
        print_header 4 "NOTICE: Moved and prepended $rel_path to SF: as $dest_filename"
    else
        mv "$lcov_file" "$dest_dir/$dest_filename"
        print_header 4 "NOTICE: Moved as $dest_filename"
    fi

    # Store the test exit code alongside the coverage file
    if [ -n "$TEST_EXIT_CODE" ]; then
        echo "$TEST_EXIT_CODE" > "$dest_dir/$exit_code_filename"
        print_header 4 "NOTICE: Stored exit code $TEST_EXIT_CODE in $exit_code_filename"
    fi

    FILES_MOVED=$((FILES_MOVED + 1))
done < <(find . -type f -name "lcov.info" "${ignore_args[@]}" -print0)

if [ "$FILES_MOVED" -eq 0 ]; then
    print_header 4 "ERROR: No lcov.info files found — no coverage was produced for this suite"
    exit 1
fi

# ── Summary ─────────────────────────────────────────────────
print_header 2 "Coverage summary for: $TEST_TYPE"
echo "  Valid (moved): $FILES_MOVED  Empty (deleted): $EMPTY_FILES"
if [ "$FILES_MOVED" -gt 0 ]; then
    echo ""
    echo "  Coverage rates (lines):"
    max_len=0
    while IFS= read -r -d '' f; do
        rel="${f#$COVERAGE_REPORT_PATH/}"
        len=${#rel}
        [ "$len" -gt "$max_len" ] && max_len=$len
    done < <(find "$COVERAGE_REPORT_PATH" -name "$dest_filename" -print0 2>/dev/null)
    while IFS= read -r -d '' f; do
        rel="${f#$COVERAGE_REPORT_PATH/}"
        summary=$(lcov --summary "$f" 2>&1 | grep 'lines......' | head -1)
        printf "    %-*s  %s\n" "$max_len" "$rel" "$summary"
    done < <(find "$COVERAGE_REPORT_PATH" -name "$dest_filename" -print0 2>/dev/null)
fi