#!/bin/bash

set -e

cd /coverage_reloaded/repo

# Try installing without --legacy-peer-deps
if npm install --no-fund; then
    echo "Installation succeeded without --legacy-peer-deps"
else
    echo "Peer dependency conflicts detected. Retrying with --legacy-peer-deps..."
    npm install --no-fund --legacy-peer-deps
    # Deduplicate to resolve version conflicts
    npm dedupe
fi

npm run build


TEST_SCRIPT=$(node -p "require('./package.json').scripts['test']")

set +e

if [[ "$TEST_SCRIPT" == *"jest"* ]]; then
    echo "Running tests with Jest (original script: $TEST_SCRIPT)"
    NODE_OPTIONS=--experimental-vm-modules npx jest --coverage
    bash ../find-and-move-lcov.sh
    
elif [[ "$TEST_SCRIPT" == *"vitest"* ]]; then
    echo "Running tests with Vitest (original script: $TEST_SCRIPT)"
    # Problem: dependency issues with vitest cause coverage to fail
    # Solution: install latest vitest and coverage plugin
    npm install vitest@latest @vitest/coverage-v8@latest
    npx vitest \
        --coverage \
        --coverage.reporter=lcov \
        --coverage.reportOnFailure=true \
        --coverage.reportsDirectory="$COVERAGE_REPORT_PATH"
fi

TEST_EXIT_CODE=$?
set -e

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi