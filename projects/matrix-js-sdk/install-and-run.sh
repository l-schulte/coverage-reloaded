#!/usr/bin/env bash
set -euo pipefail

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

ROOT_TEST=$(node -p "((require('./package.json').scripts||{}).test) || ''")
if [ -z "$ROOT_TEST" ]; then
    print_header 2 "NOT APPLICABLE" "No test script at this commit"
    exit 2
fi

TEST_HAS_PATH=$(node -p "/spec\//.test((require('./package.json').scripts||{}).test||'')")

EXCLUDED_SUITES="spec/browserify"
COVERAGE_FROM="src/**/*.{js,ts}"

print_header 4 "test script: $ROOT_TEST"
print_header 4 "test script pins a spec path: $TEST_HAS_PATH"
print_header 4 "suite exclusions: $EXCLUDED_SUITES (browser-bundle smoke test; needs yarn build)"
print_header 4 "coverage source glob: $COVERAGE_FROM"

export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=4096"

print_header 2 "Installing dependencies"
if [ "$IS_YARN_MAIN_PM" = "true" ]; then
    yarn install --frozen-lockfile
else
    print_header 2 "ERROR: unsupported package manager" "matrix-js-sdk uses yarn for every commit in the study window, but this commit resolved to '$package_manager'"
    exit 1
fi

run_jest_suite() {
    local suite="$1"
    local path="${2:-}"

    if [ -n "$path" ] && [ ! -d "$path" ]; then
        print_header 4 "SKIP: $path not present at this commit"
        return 0
    fi

    suite_start "$suite" "jest ${path} --coverage --coverageReporters=lcov --collectCoverageFrom=$COVERAGE_FROM --runInBand --forceExit --testTimeout=30000 --testPathIgnorePatterns=/node_modules/ --testPathIgnorePatterns=$EXCLUDED_SUITES --setupFiles=/coverage_reloaded/silence-console.cjs"
    set +e
    yarn test ${path} --coverage --coverageReporters=lcov --collectCoverageFrom="$COVERAGE_FROM" --runInBand --forceExit --testTimeout=30000 --testPathIgnorePatterns=/node_modules/ --testPathIgnorePatterns="$EXCLUDED_SUITES" --setupFiles=/coverage_reloaded/silence-console.cjs
    local suite_exit=$?
    set -e
    bash /coverage_reloaded/find-and-move-lcov.sh "$suite" "false" "$suite_exit"
    suite_end "$suite" "$suite_exit"
}

if [ "$TEST_HAS_PATH" = "true" ]; then
    run_jest_suite "unit"
else
    run_jest_suite "unit" "spec/unit"
    run_jest_suite "integration" "spec/integ"
fi

print_header 1 "matrix-js-sdk coverage run complete"
