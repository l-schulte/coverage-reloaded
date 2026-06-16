#!/bin/bash

# TODO: Pass exit code as 3rd arg to find-and-move-lcov.sh
#       TEST_EXIT_CODE is captured below but not forwarded.
#       Change: bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT_CODE"

set -e

cd /coverage_reloaded/repo

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")
TEST_MANAGER_SCRIPT=$(node -p "require('./package.json').scripts['test:manager'] || ''")

if $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install --no-fund --dev

    COMMAND="yarn"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install --dev

    pnpm run install:all || echo "No install:all script found, skipping."

    COMMAND="pnpm"
else
    echo "No main package manager detected... raising error."
    exit 1
fi

if [[ "$TEST_SCRIPT" == *"lerna"* ]]; then
    echo "Test script uses lerna. Running lerna bootstrap to link packages and install dependencies."
    npx lerna bootstrap
    npx lerna run build --no-bail
fi

BUILD_SCRIPT=$(node -p "require('./package.json').scripts['build'] || ''")

if [[ -n "$BUILD_SCRIPT" ]]; then
    echo "Build script found. Running build script before tests."
    $COMMAND run build
else
    echo "No build script found. Skipping build step."
fi

set +e

# COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['coverage'] || ''")
# if [[ -n "$COVERAGE_SCRIPT" ]]; then
#     echo "Coverage script found. Running coverage script ($COVERAGE_SCRIPT) with $COMMAND instead of test script."
#     $COMMAND run coverage -- --coverage.reporter=lcov --coverage.reportOnFailure=true --no-bail
# else

# fi

if [[ -n "$TEST_MANAGER_SCRIPT" ]]; then
    echo "Test manager script found. Running test manager script ($TEST_MANAGER_SCRIPT) with $COMMAND instead of test script."
    $COMMAND run test:manager --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true
else
    if [[ "$TEST_SCRIPT" == *"workspaces"* ]]; then
        echo "Test script uses workspaces. Running tests ($TEST_SCRIPT) with $COMMAND at the root level."
        $COMMAND test -- --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true --no-bail
    else
        echo "Test script does not use workspaces. Running tests ($TEST_SCRIPT) with $COMMAND at the current level."
        $COMMAND test --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true
    fi
fi


TEST_EXIT_CODE=$?
set -e

bash ../find-and-move-lcov.sh

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi