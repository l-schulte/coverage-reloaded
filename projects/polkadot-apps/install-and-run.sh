#!/bin/bash

cd /coverage_reloaded/repo

yarn install

# nyc runs out of heap space for some versions. using c8 as an alternative.

# set +e
echo "Using test script for coverage collection"
    npx --registry=$WAYPACK_NPM_REGISTRY c8 \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        --force \
        -- yarn test
# set -e