#!/bin/bash

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

# Find all lcov.info files anywhere in the repository
while IFS= read -r -d '' lcov_file; do
    # Get the directory containing the lcov.info file
    dir=$(dirname "$lcov_file")
    # Remove leading './' from the path
    rel_path="${dir#./}"
    dest_dir="$COVERAGE_REPORT_PATH/$rel_path"
    mkdir -p "$dest_dir"
    cp "$lcov_file" "$dest_dir/"
done < <(find . -type f -name "lcov.info" "${ignore_args[@]}" -print0)

# Check if any lcov.info files exist in $COVERAGE_REPORT_PATH
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi
