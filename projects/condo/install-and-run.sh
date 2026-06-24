#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

CI= yarn install

print_header 2 "Running tests with coverage"

# Yarn workspaces does not work with nyc directly. Ends up overwriting the coverage
# report from each workspace instead of combining them. Generating them into different
# report-dirs does not work.
# Workaround: rely on each workspace generating its own lcov.info file, which works for
#   condo since coverage seems to be collected in the individual packages anyway. Then
#   we find and move them afterwards.

set +e
if yarn workspaces foreach --help >/dev/null 2>&1; then
    print_header 3 "Using yarn workspaces foreach to run tests with coverage..."
    yarn workspaces foreach run test --coverage
else
    print_header 3 "Using yarn workspaces run to run tests with coverage..."
    # Older versions of yarn do not have 'workspaces foreach'.
    # Workaround: use 'workspaces run' instead.
    yarn workspaces run test --coverage
fi
TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"

print_header 1 "condo coverage run complete"