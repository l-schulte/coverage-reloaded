#!/bin/bash

cd /coverage_reloaded/repo

# In some versions the test library (tap) is a dev dependency
# Workaround: add --include=dev to install dev dependencies as well
npm install --no-fund --include=dev

set +e

# if package.json contains "test": "tap" run npx tap --coverage
# if package.json contains "test-tap" then run that (otherwise tries to run the linter)
if grep -q '"test-tap":' package.json; then
    echo "Detected tap as test runner (test-tap), using tap for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        npm run test-tap
elif grep -q '"test": *"tap' package.json; then
    echo "Detected tap as test runner, using tap for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY tap \
        --coverage \
        --coverage-report=lcov

    bash ../find-and-move-lcov.sh
else
    echo "Using nyc for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        npm test
fi
set -e