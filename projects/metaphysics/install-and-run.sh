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

yarn install --frozen-lockfile --ignore-scripts

# The project uses patch-package (via "prepare": "patch-package" in package.json)
# to add PageInfoType and other extensions to graphql-relay@0.5.4.
# --ignore-scripts above skips the prepare hook, so we must run patch-package
# explicitly here.
print_header 4 "Applying patches with patch-package"
npx --registry=$WAYPACK_NPM_REGISTRY patch-package

# NOTE: --ignore-scripts also skips postinstall scripts from dependencies like
# vue-demi. If you see "vueDemi.hasInjectionContext is not a function" errors
# in test output, remove --ignore-scripts above (or run the relevant postinstall
# scripts manually).

# Metaphysics uses jest with --coverage (no c8/nyc). The `ci` script exists across
# the entire history and always runs the test suite (usually "yarn test", briefly
# "USE_UNSTITCHED_VIEWING_ROOM_SCHEMA=true yarn test"). Jest's built-in coverage
# reporter produces lcov.info in coverage/ by default.

print_header 2 "Running tests with coverage"

set +e
if [ -f jest.config.js ]; then
    print_header 4 "Using jest.config.js for test run"
    npx --registry=$WAYPACK_NPM_REGISTRY jest --config=jest.config.js --coverage --coverageReporters=lcov
else
    print_header 4 "No jest.config.js found, using defaults"
    npx --registry=$WAYPACK_NPM_REGISTRY jest --coverage --coverageReporters=lcov
fi
JEST_EXIT=$?
set -e


print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$JEST_EXIT"

print_header 1 "Metaphysics coverage run complete"