#!/bin/bash

# Input value for which type of test was executed last, e.g. unit, integration, etc.
TEST_TYPE="${1:-}"

echo "Looking for locv files... $TEST_TYPE"

cd /coverage_reloaded/repo

# Define patterns to ignore
IGNORE_PATTERNS=('*/node_modules/*')

# Build the find command's ignore arguments
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

# Create the target directory if it doesn't exist
mkdir -p "$COVERAGE_REPORT_PATH"

# Determine the destination filename
if [ -n "$TEST_TYPE" ]; then
    dest_filename="${TEST_TYPE}.lcov.info"
else
    dest_filename="lcov.info"
fi

# Find all lcov.info files anywhere in the repository
while IFS= read -r -d '' lcov_file; do
    # Get the directory containing the lcov.info file
    dir=$(dirname "$lcov_file")
    # Remove leading './' from the path, and strip the trailing '/coverage' if it exists
    rel_path="${dir%/coverage}"
    rel_path="${rel_path#./}"
    dest_dir="$COVERAGE_REPORT_PATH/$rel_path"
    mkdir -p "$dest_dir"
    mv "$lcov_file" "$dest_dir/$dest_filename"
done < <(find . -type f -name "lcov.info" "${ignore_args[@]}" -print0)

# Check if any prefixed lcov files exist in $COVERAGE_REPORT_PATH
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "*.lcov.info" -o -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi