#!/bin/bash

set -e

export NODE_OPTIONS="--max-old-space-size=4096"

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
fi

print_header 2 "Fixing broken @fioprotocol/fiosdk git URL"

# edge-currency-accountbased has a hardcoded dependency on @fioprotocol/fiosdk
# from a private/broken git URL (jon-edge/fiosdk_typescript.git) that no longer
# exists (returns 404). We use yarn's resolutions to override it with the
# official working repository (fioprotocol/fiosdk_typescript).
# Only fix the broken jon-edge URL; leave working peachbits URL untouched.

if $IS_YARN_MAIN_PM && [ -f yarn.lock ]; then
    if grep -qE '@fioprotocol/fiosdk@(git\+)?https://github\.com/jon-edge/' yarn.lock; then
        print_header 3 "Detected broken jon-edge/fiosdk_typescript URL, fixing..."

        # Extract version from yarn.lock and add resolution to package.json
        # This tells yarn to use the official repo with the same version
        python3 -c "
import json
import re
import sys

try:
    # Read yarn.lock to extract the version from the broken entry
    with open('yarn.lock', 'r') as f:
        yarn_lock = f.read()
    
    # Find the broken jon-edge entry and extract the version
    # Pattern: \"@fioprotocol/fiosdk@https://github.com/jon-edge/...\":\n  version \"X.Y.Z\"
    match = re.search(
        r'\"@fioprotocol/fiosdk@(git\+)?https://github\.com/jon-edge/[^\"]+\":\n\s+version \"([^\"]+)\"',
        yarn_lock
    )
    
    if not match:
        print('Could not find @fioprotocol/fiosdk version in yarn.lock', file=sys.stderr)
        sys.exit(1)
    
    version = match.group(2)
    print(f'Found @fioprotocol/fiosdk version: {version}')
    
    # Read package.json
    with open('package.json', 'r') as f:
        pkg = json.load(f)
    
    # Add or update resolutions field
    if 'resolutions' not in pkg:
        pkg['resolutions'] = {}
    
    # Use the official repo with the extracted version tag
    resolution_url = f'https://github.com/fioprotocol/fiosdk_typescript#v{version}'
    pkg['resolutions']['@fioprotocol/fiosdk'] = resolution_url
    
    with open('package.json', 'w') as f:
        json.dump(pkg, f, indent=2)
        f.write('\n')
    
    print(f'Added @fioprotocol/fiosdk resolution: {resolution_url}')
except Exception as e:
    print(f'Error modifying package.json: {e}', file=sys.stderr)
    sys.exit(1)
"

        # Remove the broken entry from yarn.lock so yarn resolves it fresh
        # using the resolution we just added
        python3 -c "
import re

with open('yarn.lock', 'r') as f:
    content = f.read()

# Remove the @fioprotocol/fiosdk entry block that references jon-edge
# The entry starts with the quoted package name and includes all indented lines
content = re.sub(
    r'\"@fioprotocol/fiosdk@(git\+)?https://github\.com/jon-edge/[^\"]+\":\n(  [^\n]*\n)*',
    '',
    content
)

with open('yarn.lock', 'w') as f:
    f.write(content)

print('Removed broken @fioprotocol/fiosdk entry from yarn.lock')
"

        print_header 4 "Fixed @fioprotocol/fiosdk URL"
    else
        print_header 4 "No broken jon-edge URL found, skipping"
    fi
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
        --coverage --coverageReporters=lcov --runInBand --forceExit
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "config" "false" "$EXIT_CODE"
    suite_end "config" "$EXIT_CODE"
fi

if [ -f jest.async.config.js ]; then
    suite_start "async_config" "Running jest with jest.async.config.js"
    JEST_ASYNC_CONFIG="--config jest.async.config.js"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest $JEST_ASYNC_CONFIG \
        --coverage --coverageReporters=lcov --runInBand --forceExit
    EXIT_CODE=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "async_config" "false" "$EXIT_CODE"
    suite_end "async_config" "$EXIT_CODE"
fi

if [ ! -f jest.config.js ] && [ ! -f jest.async.config.js ]; then
    suite_start "default" "Running jest without config file"
    TZ=America/Los_Angeles npx --registry="$WAYPACK_NPM_REGISTRY" jest \
        --coverage --coverageReporters=lcov --runInBand --forceExit
    TEST_EXIT=$?
    bash /coverage_reloaded/find-and-move-lcov.sh "default" "false" "$TEST_EXIT"
    suite_end "default" "$TEST_EXIT"
fi

set -e

print_header 1 "Edge React GUI coverage run complete"
