#!/bin/bash

cd /coverage_reloaded/repo

yarn install

# nyc runs out of heap space for some versions. using c8 as an alternative.

set +e
if grep -q '"test:all":' package.json; then
    echo "Detected test:all script, using it for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        yarn test:all
else
    echo "Using test script for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        yarn test
fi

set -e