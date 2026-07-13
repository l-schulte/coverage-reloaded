#!/bin/bash
set -e

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/has-option.sh"

cd /coverage_reloaded/repo

if ! has_script "test"; then
    print_header 2 "NOT APPLICABLE: test script not defined"
    exit 2
fi

print_header 2 "Installing dependencies"

npm install --no-fund --include=dev --legacy-peer-deps

print_header 2 "Running tests"

suite_start "unit" "Running tests with jest --coverage"
set +e

npm test -- --coverage
TEST_EXIT_CODE=$?
set -e

bash ../find-and-move-lcov.sh "jest" "false" "$TEST_EXIT_CODE"
suite_end "unit" "$TEST_EXIT_CODE"