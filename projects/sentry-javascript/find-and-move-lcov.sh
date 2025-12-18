#!/bin/bash
cd /app/repo

# Define patterns to match only the coverage folder (not subdirectories)
PATTERNS=('coverage' 'packages/*/coverage' 'apps/*/coverage')
IGNORE_PATTERNS=('*/node_modules/*')

# Build the find command's ignore arguments
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

# Create the target directory if it doesn't exist
mkdir -p "$COVERAGE_REPORT_PATH"

# Find and copy all coverage folders to $COVERAGE_REPORT_PATH, preserving the source path
for pattern in "${PATTERNS[@]}"; do
    while IFS= read -r -d '' dir; do
        # Create the corresponding directory in $COVERAGE_REPORT_PATH
        dest="$COVERAGE_REPORT_PATH/${dir#./}"
        mkdir -p "$(dirname "$dest")"
        cp -r "$dir" "$dest"
    done < <(find . -path "./$pattern" -type d "${ignore_args[@]}" -print0)
done

# Check if any lcov.info files exist in $COVERAGE_REPORT_PATH
lcov_count=$(find "$COVERAGE_REPORT_PATH" -name "lcov.info" | wc -l)
if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi
