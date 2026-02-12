#!/bin/bash

cd /coverage_reloaded/repo


if $IS_NPM_MAIN_PM; then
    npm install
    set +e

    npm run test:unit -- --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
    npm run test:front -- --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
elif $IS_YARN_MAIN_PM; then
    yarn install
    set +e

    yarn run test:unit -- --coverage --coverageDirectory="$COVERAGE_REPORT_PATH"
fi

set -e