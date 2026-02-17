#!/bin/bash

set -euo pipefail

cd /coverage_reloaded/repo


# In some versions the test library (tap) is a dev dependency
# Workaround: add --include=dev to install dev dependencies as well
npm install --no-fund --include=dev

HAS_PRETEST=$(grep -q '"pretest":' package.json && echo "true" || echo "false")
HAS_TEST_TAP=$(grep -q '"test-tap":' package.json && echo "true" || echo "false")

if [ "$HAS_PRETEST" = "true" ] && [ "$HAS_TEST_TAP" = "false" ]; then
    echo "ERROR: pretest exists but test-tap does not — cannot safely bypass linter" >&2
    exit 1
fi

set +e
if [ "$HAS_PRETEST" = "true" ]; then
    echo "Detected pretest, bypassing via test-tap"
    npx --registry="$WAYPACK_NPM_REGISTRY" nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- npm run test-tap
else
    echo "No pretest detected, using npm test"
    npx --registry="$WAYPACK_NPM_REGISTRY" nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- npm test
fi
set -e