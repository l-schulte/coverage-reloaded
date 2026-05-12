#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"
npm install --no-fund --include=dev --legacy-peer-deps

BUILD_NATIVE_SCRIPT=$(node -p "require('./package.json').scripts['build:native'] || ''")
if [ -n "$BUILD_NATIVE_SCRIPT" ]; then
    print_header 2 "Building native addons"
    npm run build:native
fi

JEST_SCRIPT=$(node -p "require('./package.json').scripts['jest'] || ''")
MOCHA_SCRIPT=$(node -p "require('./package.json').scripts['mocha'] || ''")
set +e

print_header 2 "Running tests"

if [ -n "$JEST_SCRIPT" ]; then
    print_header 3 "Running Jest tests with coverage"
    npx jest --coverage --no-bail
    bash ../find-and-move-lcov.sh jest
elif [ -n "$MOCHA_SCRIPT" ]; then
    print_header 3 "Running Mocha tests with coverage"
    npx nyc --all --include 'src/**/*.js' --exclude 'src/util/mongo_functions.js' --reporter lcov npm run mocha
else
    echo "No known test suite found" 
    exit 1
fi
    
set -e