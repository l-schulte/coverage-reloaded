#!/bin/bash

cd /coverage_reloaded/repo

if $IS_NPM_MAIN_PM; then
    npm install --no-fund --include dev --legacy-peer-deps

    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        npm test
elif $IS_YARN_MAIN_PM; then
    yarn install --no-fund --dev

    npx --registry=$WAYPACK_NPM_REGISTRY nyc \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        yarn test
fi