#!/bin/bash

# TODO: Fix set +e scope + capture exit code + pass as 3rd arg to find-and-move-lcov.sh
#       Issues:
#       - set +e is too broad — it wraps find-and-move-lcov.sh too (must run under set -e)
#       - No exit code captured after npm test
#       - No warning/error handling for exit codes 0/1 vs >1
#       Fix: set +e / TEST_EXIT_CODE=$? / set -e / warning handling / bash ../find-and-move-lcov.sh jest "false" "$TEST_EXIT_CODE"

set -e

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

npm install --no-fund --include=dev --legacy-peer-deps

print_header 2 "Running tests"
set +e

npm test -- --coverage

bash ../find-and-move-lcov.sh jest
    
set -e