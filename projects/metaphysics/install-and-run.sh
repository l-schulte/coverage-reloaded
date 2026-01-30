#!/bin/bash
cd /coverage_reloaded/repo

yarn install

set +e

npm run

# Metaphsiyics iterates through multiple test commands over time: ci, test:jest:v2, test:jest, test

if npm run | grep -q "test:jest:v2"; then
    echo "Running jest v2 test command."
    yarn run test:jest:v2 --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
elif npm run | grep -q "test:jest"; then
    echo "Running jest test command. (avoids type checking)"
    yarn run test:jest --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
elif npm run | grep -q "ci"; then
    echo "Running ci test command."
    yarn run ci --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
else
    echo "Running default test command."
    yarn run test --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
fi

set -e