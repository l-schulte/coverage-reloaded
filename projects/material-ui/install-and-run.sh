#!/bin/bash

set -e

cd /coverage_reloaded/repo


if $IS_NPM_MAIN_PM; then
    echo "Installing dependencies with npm..."
    npm install --no-fund --include=dev

    COMMAND="npm run"
elif $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."

    # Requires a non-existing dependency (vitest-mui, was deleted from registry)
    # Workaround: providing the file (vitest-mui-0.3.3.tgz and vitest-mui-0.3.4.tgz) in the waypack machine
    # Integrity checks fail for this file.
    # Workaround: clean cache with yarn cache clean disable integrity checks for yarn installs by adding --update-checksums
    echo "-> Installing dependencies via yarn..."
    yarn cache clean --force
    yarn install --update-checksums

    COMMAND="yarn run"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install

    COMMAND="pnpm run"
else
    echo "No main package manager detected... raising error."
    exit 1
fi

set +e

if grep -q '"test:coverage"' package.json; then
    echo "Running tests with test:coverage script..."
    $COMMAND test:coverage
elif grep -q '"test:coverage:ci"' package.json; then
    # test:coverage:ci is pre-configured to collect lcov reports.
    echo "Running tests with test:coverage:ci script..."
    $COMMAND test:coverage:ci
else
    echo "No test script found in package.json, skipping tests."
fi  

npx --registry=$VERDACCIO_REGISTRY nyc report --reporter=lcov --report-dir="$COVERAGE_REPORT_PATH"
    
set -e