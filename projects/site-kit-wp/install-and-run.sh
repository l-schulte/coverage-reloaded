#!/bin/bash

set -e

cd /coverage_reloaded/repo

npm install --no-fund

set +e



# Problem: test:js uses npm workspaces (-w) in some versions, which requires an extra -- to pass arguments.
TEST_SCRIPT=$(node -p "require('./package.json').scripts['test:js']")

# check if TEST_SCRIPT is a variation of ["npm run test:js -w tests/js", "npm run -w tests/js test:js", "npm run test:js -w ./tests/js"]
if [[ "$TEST_SCRIPT" == *"-w ./tests/js"* ]] || [[ "$TEST_SCRIPT" == *"-w tests/js"* ]]; then
    echo "Running tests with workspaces enabled"
    npm run -w tests/js test:js -- \
        --coverage \
        --coverageDirectory="$COVERAGE_REPORT_PATH" \
        --coverageReporters=lcov \
        --runInBand
else
    echo "Running tests without workspaces"
    npm run test:js -- \
        --coverage \
        --coverageDirectory="$COVERAGE_REPORT_PATH" \
        --coverageReporters=lcov \
        --runInBand 
fi

TEST_EXIT_CODE=$?
set -e

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi