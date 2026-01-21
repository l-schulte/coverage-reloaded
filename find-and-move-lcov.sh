#!/bin/bash

cd /app/repo

# Define patterns to match coverage folders
PATTERNS=('coverage' 'packages/*/coverage' 'apps/*/coverage' '.build/coverage')
IGNORE_PATTERNS=('*/node_modules/*')

# Build the find command's ignore arguments
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

# Create the target directory if it doesn't exist
mkdir -p "$COVERAGE_REPORT_PATH"

# Find all coverage folders
while IFS= read -r -d '' dir; do
    lcov_file="$dir/lcov.info"
    if [[ -f "$lcov_file" ]]; then
        # Extract the parent directory path relative to the coverage folder
        rel_path="${dir%/coverage}"
        rel_path="${rel_path#./}"
        dest_dir="$COVERAGE_REPORT_PATH/$rel_path"
        mkdir -p "$dest_dir"
        cp "$lcov_file" "$dest_dir/"
    fi
done < <(find . -type d \( -path "./coverage" -o -path "./packages/*/coverage" -o -path "./apps/*/coverage" -o -path "./.build/coverage" \) "${ignore_args[@]}" -print0)

# Check if any lcov.info files exist in $COVERAGE_REPORT_PATH
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi
