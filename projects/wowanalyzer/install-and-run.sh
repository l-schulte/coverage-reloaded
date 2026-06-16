#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Detecting test infrastructure"

# Detect test runner from package.json scripts
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn cache clean
    # --ignore-engines: skip Node.js engine compatibility checks so that
    # packages like @playwright/test (requires Node >=16) don't block the
    # install when the project's Dockerfile specifies an older Node version.
    yarn install --ignore-engines
elif $IS_PNPM_MAIN_PM; then
    pnpm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# Install vitest coverage provider if needed (not included in project deps)
if echo "$TEST_SCRIPT" | grep -q "vitest"; then
    print_header 3 "Installing @vitest/coverage-v8"
    if $IS_YARN_MAIN_PM; then
        yarn add --dev @vitest/coverage-v8
    elif $IS_PNPM_MAIN_PM; then
        pnpm add -D @vitest/coverage-v8
    fi
fi

# Note: The project also defines test:interface, test:parser, and test:integration
# sub-suite scripts, but these are just filtered views of the main `test` script
# (e.g. "yarn test --exclude src/parser" or "yarn test ./src/parser"). The main
# `test` suite already covers all behavioral code paths in a single pass, so
# running sub-suites separately would only produce overlapping lcov files with
# no new coverage data.

print_header 2 "Running tests with coverage"

set +e

if echo "$TEST_SCRIPT" | grep -q "vitest"; then
    print_header 3 "Running tests (vitest)"
    npx --registry="$WAYPACK_NPM_REGISTRY" vitest run --coverage --coverage.reporter=lcov --coverage.reportOnFailure=true
    TEST_EXIT=$?
elif echo "$TEST_SCRIPT" | grep -q "react-app-rewired"; then
    print_header 3 "Running tests (react-app-rewired / jest)"
    npx --registry="$WAYPACK_NPM_REGISTRY" react-app-rewired test --coverage --coverageReporters=lcov --watchAll=false
    TEST_EXIT=$?
else
    print_header 3 "Test runner not configured."
fi

set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

print_header 1 "WoWAnalyzer coverage run complete"
