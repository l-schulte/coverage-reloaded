#!/bin/bash

cd /coverage_reloaded/repo

yarn install --no-fund --dev
yarn build

set +e

npx --registry=$WAYPACK_NPM_REGISTRY nyc \
    --reporter=lcov \
    --report-dir="$COVERAGE_REPORT_PATH" \
    yarn test
    
set -e