#!/bin/bash

set -e

set -euo pipefail

# ─────────────────────────────────────────────
# Coverage collection script
# Coverage is not collected by default in this project.
# We therefore wrap the test command with nyc to collect coverage regardless of the test script.
# Pretest is bypassed via test-tap script if it exists, since it includes linting that may fail and prevent coverage collection.
#
# ─────────────────────────────────────────────

cd /coverage_reloaded/repo


# In some versions the test library (tap) is a dev dependency
# Workaround: add --include=dev to install dev dependencies as well
npm install --no-fund --include=dev

HAS_TEST_COVERAGE=$(grep -q '"test-coverage":' package.json && echo "true" || echo "false")

set +e
if [ "$HAS_TEST_COVERAGE" = "true" ]; then
    echo "Detected test-coverage script"
    npm run test-coverage
    nyc report --reporter=lcov --report-dir="$COVERAGE_REPORT_PATH"
else
    echo "No pretest detected, using npm test"
    npx --registry="$WAYPACK_NPM_REGISTRY" nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- npm run test
fi

TEST_EXIT_CODE=$?
set -e

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi