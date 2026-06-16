#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn cache clean
    yarn install
elif $IS_NPM_MAIN_PM; then
    npm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Creating env.json"

# The project requires env.json at import time (src/env.ts imports it).
# All fields are optional with defaults, so an empty object suffices.
echo '{}' > env.json
print_header 4 "Created empty env.json"

print_header 2 "Detecting test infrastructure"

# Determine jest config: prefer standalone jest.config.js, otherwise use defaults
if [ -f jest.config.js ]; then
    JEST_CONFIG="--config jest.config.js"
    print_header 4 "Using jest.config.js"
else
    JEST_CONFIG=""
    print_header 4 "No jest.config.js — using jest defaults (config from package.json)"
fi

print_header 2 "Running tests with coverage"

set +e
TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_CONFIG \
    --coverage --coverageReporters=lcov --runInBand
TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

print_header 1 "Edge React GUI coverage run complete"
