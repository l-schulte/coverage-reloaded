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

# Detect what's available at this commit by inspecting the checked-out files.
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
HAS_JEST=$(node -p "(require('./package.json').devDependencies || {}).jest || ''")
HAS_GULP=$(node -p "(require('./package.json').devDependencies || {}).gulp || ''")
HAS_NG_TEST=$(echo "$TEST_SCRIPT" | grep -c "ng test" || true)

print_header 2 "Installing dependencies"

if $IS_NPM_MAIN_PM; then
    npm ci --legacy-peer-deps --engine-strict=false || npm install --legacy-peer-deps --engine-strict=false
elif $IS_YARN_MAIN_PM; then
    yarn install --ignore-engines
elif $IS_PNPM_MAIN_PM; then
    pnpm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

suite_start "unit" "Running tests with coverage"

set +e

if [ "$HAS_NG_TEST" -gt 0 ]; then
    # ng test era (Karma) — single commit boundary, ~Oct 2020
    print_header 3 "Running ng test with coverage"
    npx --registry="$WAYPACK_NPM_REGISTRY" ng test --no-watch --code-coverage --reporters=progress --reporters=coverage-istanbul
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "ng_test" "false" "$TEST_EXIT"
elif [ -n "$HAS_JEST" ]; then
    # Jest era — the dominant test runner for this project
    if [ -n "$HAS_GULP" ]; then
        # Gulp builds lang/env files needed by tests (present from ~Feb 2021 onward)
        print_header 3 "Running gulp to build lang/env files"
        NODE_ENV=testing npx --registry="$WAYPACK_NPM_REGISTRY" gulp
    fi

    print_header 3 "Running jest with lcov coverage"
    # FIX: Use V8 coverage provider instead of the default "babel" provider.
    #
    # The default babel-based Istanbul instrumentation crashes silently (jest
    # exits 1 with zero error output, no coverage directory created).  V8's
    # native coverage API works reliably and produces identical lcov output.
    #
    # Why developers never hit this: npm test runs without --coverage, so
    # the babel provider is never exercised during normal development.
    npx --registry="$WAYPACK_NPM_REGISTRY" jest --verbose --coverage --coverageProvider=v8 --coverageReporters=lcov --runInBand
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "false" "$TEST_EXIT"
else
    print_header 2 "NOT APPLICABLE" "No recognized test runner at this commit"
    exit 2
fi

set -e

suite_end "unit" "$TEST_EXIT"

print_header 1 "MoodleApp coverage run complete"
