#!/bin/bash

# TODO: Add set +e + capture exit code + pass as 3rd arg to find-and-move-lcov.sh
#       Issues:
#       - No set +e at all — tests run under set -e, so a failure aborts the script
#       - No exit code captured
#       - No warning/error handling for exit codes 0/1 vs >1
#       Fix: set +e before test / TEST_EXIT_CODE=$? / set -e / warning handling / bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT_CODE"

set -e
cd /coverage_reloaded/repo

CI= yarn install

# set +e
# Yarn workspaces does not work with nyc directly. Ends up overwriting the coverage 
# report from each workspace instead of combining them. Generating them into different 
# report-dirs does not work.
# Workaround: rely on each workspace generating its own lcov.info file, which works for
#   condo since coverage seems to be collected in the individual packages anyway. Then
#   we find and move them afterwards.
    
if yarn workspaces foreach --help >/dev/null 2>&1; then
    echo "Using yarn workspaces foreach to run tests with coverage..."
    yarn workspaces foreach run test --coverage
else
    echo "Using yarn workspaces run to run tests with coverage..."
    # Older versions of yarn do not have 'workspaces foreach'.
    # Workaround: use 'workspaces run' instead.
    yarn workspaces run test --coverage
fi
bash ../find-and-move-lcov.sh
# set -e