#!/bin/bash

TEST_TYPE="${1:-}"
PREPEND_PATHS="${2:-false}"  # Pass "true" for workspace monorepos

echo "Looking for lcov files... TEST_TYPE=$TEST_TYPE PREPEND_PATHS=$PREPEND_PATHS"

cd /coverage_reloaded/repo

IGNORE_PATTERNS=('*/node_modules/*')
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

mkdir -p "$COVERAGE_REPORT_PATH"

if [ -n "$TEST_TYPE" ]; then
    dest_filename="${TEST_TYPE}.lcov.info"
else
    dest_filename="lcov.info"
fi

while IFS= read -r -d '' lcov_file; do
    dir=$(dirname "$lcov_file")
    rel_path="${dir%/coverage}"
    rel_path="${rel_path#./}"
    dest_dir="$COVERAGE_REPORT_PATH/$rel_path"
    mkdir -p "$dest_dir"

    echo "--> Found $lcov_file"
    lcov --summary "$lcov_file"

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
        echo "--> Moved and prepended $rel_path to SF: paths in $lcov_file"
    else
        mv "$lcov_file" "$dest_dir/$dest_filename"
        echo "--> Moved $lcov_file"
    fi
done < <(find . -type f -name "lcov.info" "${ignore_args[@]}" -print0)

lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "*.lcov.info" -o -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi