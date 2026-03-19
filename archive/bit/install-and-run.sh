#!/bin/bash

if $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install --no-fund --dev

    COMMAND="yarn"
elif $IS_NPM_MAIN_PM; then
    echo "Installing dependencies with npm..."
    npm install --no-fund --include=dev

    COMMAND="npm"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install --dev --no-frozen-lockfile
    pnpm install cross-env

    COMMAND="pnpm"
else
    echo "No main package manager detected... raising error."
    exit 1
fi


npx --registry=$WAYPACK_NPM_REGISTRY c8 \
    --require source-map-support/register \
    --require @babel/register \
    --reporter=lcov \
    --report-dir="$MOCHA_COVERAGE_REPORT_PATH" \
        $COMMAND mocha-circleci \
            --no-bail


TEST_EXIT_CODE=$?
set -e

bash ../find-and-move-lcov.sh

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi