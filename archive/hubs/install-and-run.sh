#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

npm ci

print_header 2 "Building project"

npm run build

print_header 2 "Running tests"
set +e

npx --registry="$WAYPACK_NPM_REGISTRY" c8 --reporter=lcov npm run test:unit

bash ../find-and-move-lcov.sh c8
    
set -e