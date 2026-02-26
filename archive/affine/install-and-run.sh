#!/bin/bash

cd /coverage_reloaded/repo

if $IS_NPM_MAIN_PM; then
    echo "NPM is not configures."
    exit 1
elif $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install

    COMMAND="yarn"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install

    COMMAND="pnpm"
else
    echo "No main package manager detected... raising error."
    exit 1
fi

set +e

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test']")
TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage']")
TEST_UNIT_SCRIPT=$(node -p "require('./package.json').scripts['test:unit']")

$COMMAND playwright install

if [[ "$TEST_COVERAGE_SCRIPT" == *"vitest run --coverage"* ]]; then
    echo "Running tests with Vitest (original script: $TEST_COVERAGE_SCRIPT)"
    $COMMAND run test:coverage -- \
        --coverage.reporter=lcov \
        --coverage.reportOnFailure=true \
        --coverage.reportsDirectory="$COVERAGE_REPORT_PATH"
elif [[ "$TEST_UNIT_SCRIPT" == *"playwright"* ]]; then
    # If the coverage script is not based on vitest, it calls the test script.
    # The test script runs playwright, including E2E tests. To exclude E2E tests
    # we instead run the test:unit script, which is still playwright, but should only run the unit tests. 
    COVERAGE=true $COMMAND run test:unit
    bash ../find-and-move-lcov.sh
elif [[ "$TEST_UNIT_SCRIPT" == *"vitest run --coverage"* ]]; then
    echo "Running unit tests with Vitest (original script: $TEST_UNIT_SCRIPT)"
    $COMMAND run test:unit -- \
        --coverage \
        --coverage.reporter=lcov \
        --coverage.reportOnFailure=true \
        --coverage.reportsDirectory="$COVERAGE_REPORT_PATH"
else
    echo "ERROR: expected test:coverage script to include 'vitest run --coverage' or test:unit to include 'playwright', but got:" >&2
    echo "test:coverage: $TEST_COVERAGE_SCRIPT" >&2
    echo "test:unit: $TEST_UNIT_SCRIPT" >&2
    exit 2
fi

TEST_EXIT_CODE=$?
set -e

if [[ "$TEST_EXIT_CODE" -eq 1 ]]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [[ "$TEST_EXIT_CODE" -gt 1 ]]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi