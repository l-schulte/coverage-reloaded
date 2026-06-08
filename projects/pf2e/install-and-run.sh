#!/bin/bash

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