#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Removing edge-plugin-wyre (private repo, not needed for tests)"

# edge-plugin-wyre is now a private repo. It's a buy/sell plugin that isn't
# needed for running the unit tests, so we remove it from package.json and
# yarn.lock to let yarn install succeed.

if $IS_YARN_MAIN_PM && [ -f yarn.lock ]; then
    print_header 3 "Removing edge-plugin-wyre from package.json and yarn.lock"

    # Remove from package.json (both dependencies and plugins array)
    sed -i '/"edge-plugin-wyre"/d' package.json

    # Remove from yarn.lock — delete the entire entry block
    # The entry spans multiple lines starting with the quoted name
    python3 -c "
import re
with open('yarn.lock', 'r') as f:
    content = f.read()
# Remove the edge-plugin-wyre entry block
content = re.sub(
    r'\"edge-plugin-wyre@https://github.com/EdgeApp/edge-plugin-wyre\.git#[^\"]+\":\n(  .*\n?)*',
    '',
    content
)
with open('yarn.lock', 'w') as f:
    f.write(content)
"
    print_header 4 "Removal complete"
else
    print_header 4 "Not a yarn project or no yarn.lock — skipping"
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


print_header 2 "Running tests with coverage" "jest.config.js? >$JEST_CONFIG<, jest.async.config.js? >$JEST_ASYNC_CONFIG<"

set +e

if [ -f jest.config.js ]; then
    print_header 3 "Using jest.config.js"
    JEST_CONFIG="--config jest.config.js"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_CONFIG \
        --coverage --coverageReporters=lcov --runInBand
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "config" "false" "$EXIT_CODE"
fi

if [ -f jest.async.config.js ]; then
    print_header 3 "Using jest.async.config.js"
    JEST_ASYNC_CONFIG="--config jest.async.config.js"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_ASYNC_CONFIG \
        --coverage --coverageReporters=lcov --runInBand
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "async_config" "false" "$EXIT_CODE"
fi

if [ ! -f jest.config.js ] && [ ! -f jest.async.config.js ]; then
    print_header 3 "Using jest without config file"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest \
        --coverage --coverageReporters=lcov --runInBand
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "default" "false" "$TEST_EXIT"
fi

set -e

print_header 1 "Edge React GUI coverage run complete"
