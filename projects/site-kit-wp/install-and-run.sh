#!/bin/bash

source /coverage_reloaded/logging.sh

set -e

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

# Use npm 8+ for workspace (-w) support if required and current npm is too old.
TEST_SCRIPT=$(node -p "require('./package.json').scripts['test:js']")
TEST_ESLINT_SCRIPT=$(node -p "require('./package.json').scripts['test:js:eslint-plugin'] || ''")

NPM_MAJOR=$(npm --version | cut -d. -f1)
if [ "$NPM_MAJOR" -lt 7 ] && [[ "$TEST_SCRIPT" == *"-w"* ]]; then
    print_header 3 "Using npm 8+ for workspace support"
    npm_use() { npx --package=npm@8 npm "$@"; }
else
    npm_use() { npm "$@"; }
fi

npm_use install --no-fund --ignore-engines --legacy-peer-deps --ignore-scripts


print_header 2 "Running tests" "test:js: >$TEST_SCRIPT<; test:js:eslint-plugin: >$TEST_ESLINT_SCRIPT<"

print_header 3 "Running test:js tests"

set +e

if [[ "$TEST_SCRIPT" == *"-w"* ]]; then
    # Workspace era: root test:js delegates via -w (may self-reference).
    # Run the workspace's test:js directly to avoid recursion.
    npm_use run -w tests/js test:js -- \
        --coverage \
        --coverageReporters=lcov \
        --runInBand
    EXIT_CODE=$?
else
    # Pre-workspace era: test:js runs jest/wp-scripts directly.
    npm_use run test:js -- \
        --coverage \
        --coverageReporters=lcov \
        --runInBand
    EXIT_CODE=$?
fi
set -e
bash /coverage_reloaded/find-and-move-lcov.sh "js" "true" "$EXIT_CODE"

set +e

if [[ -n "$TEST_ESLINT_SCRIPT" ]]; then

    print_header 2 "Running eslint-plugin tests"

    # test:js:eslint-plugin runs jest with a separate config for the eslint-plugin package.
    TEST_ESLINT_SCRIPT=$(node -p "require('./package.json').scripts['test:js:eslint-plugin'] || ''")
    print_header 3 "test:js:eslint-plugin script: $TEST_ESLINT_SCRIPT"

    npm_use run test:js:eslint-plugin -- \
        --coverage \
        --coverageReporters=lcov \
        --runInBand
    EXIT_CODE=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "eslint-plugin" "true" "$EXIT_CODE"
fi