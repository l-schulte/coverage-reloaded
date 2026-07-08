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
    yarn install --ignore-engines
elif $IS_NPM_MAIN_PM; then
    npm install
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Running prepare script (if any)"

if $IS_YARN_MAIN_PM && grep -q '"prepare"' package.json; then
    yarn run prepare
elif $IS_NPM_MAIN_PM && grep -q '"prepare"' package.json; then
    npm run prepare
else
    print_header 4 "No prepare script found."
fi

print_header 2 "Ensuring env.json exists"

# there may be a env.example.json file that we can use to generate env.json
ENV_FILES=(.env.example.json env.example.json .env.sample.json env.sample.json)
if [ ! -f env.json ]; then
    for f in "${ENV_FILES[@]}"; do
        if [ -f "$f" ]; then
            cp "$f" env.json
            print_header 4 "Copied $f to env.json"
            break
        fi
    done
fi

if [ ! -f env.json ]; then
    echo '{}' > env.json
    print_header 4 "Created empty env.json (no configure script or example file available)"
fi

print_header 2 "Running tests..."

set +e

if [ -f jest.config.js ]; then
    suite_start "config" "Running jest with jest.config.js"
    JEST_CONFIG="--config jest.config.js"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_CONFIG \
        --coverage --coverageReporters=lcov --runInBand
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "config" "false" "$EXIT_CODE"
    suite_end "config" "$EXIT_CODE"
fi

if [ -f jest.async.config.js ]; then
    suite_start "async_config" "Running jest with jest.async.config.js"
    JEST_ASYNC_CONFIG="--config jest.async.config.js"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_ASYNC_CONFIG \
        --coverage --coverageReporters=lcov --runInBand
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "async_config" "false" "$EXIT_CODE"
    suite_end "async_config" "$EXIT_CODE"
fi

if [ ! -f jest.config.js ] && [ ! -f jest.async.config.js ]; then
    suite_start "default" "Running jest without config file"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest \
        --coverage --coverageReporters=lcov --runInBand
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "default" "false" "$TEST_EXIT"
    suite_end "default" "$TEST_EXIT"
fi

set -e

print_header 1 "Edge React GUI coverage run complete"
