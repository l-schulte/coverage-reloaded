#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

# ─────────────────────────────────────────────
# Coverage collection script
# Coverage is not collected by default in this project.
# We therefore wrap the test command with nyc to collect coverage regardless of the test script.
# Pretest is bypassed via test-tap script if it exists, since it includes linting that may fail and prevent coverage collection.
#
# ─────────────────────────────────────────────

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

# In some versions the test library (tap) is a dev dependency
# Workaround: add --include=dev to install dev dependencies as well
npm install --no-fund --include=dev

print_header 2 "Running tests with coverage"

HAS_TEST_COVERAGE=$(grep -q '"test-coverage":' package.json && echo "true" || echo "false")

set +e
if [ "$HAS_TEST_COVERAGE" = "true" ]; then
    print_header 3 "Detected test-coverage script"
    npm run test-coverage
    nyc report --reporter=lcov --report-dir="$COVERAGE_REPORT_PATH"
else
    print_header 3 "No test-coverage script, wrapping npm test with nyc"
    npx --registry="$WAYPACK_NPM_REGISTRY" nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- npm run test
fi

TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

print_header 1 "npm/cli coverage run complete"