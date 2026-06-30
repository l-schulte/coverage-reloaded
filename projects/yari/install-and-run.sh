#!/bin/bash

source /coverage_reloaded/logging.sh

set -e

print_header 2 "Checkout content repository at timestamp"
cd /coverage_reloaded/content

# Find the commit on main that is closest to (but not after) $timestamp
# The main branch was fetched at build time in the Dockerfile
CONTENT_COMMIT=$(git rev-list -n 1 --before="$timestamp" main 2>/dev/null || echo "")

if [ -z "$CONTENT_COMMIT" ]; then
    print_header 4 "WARNING: No content commit found before timestamp $timestamp, using HEAD of main"
    CONTENT_COMMIT="main"
fi

print_header 4 "Checking out content repo at commit: $CONTENT_COMMIT"
git checkout "$CONTENT_COMMIT"

cd /coverage_reloaded/repo

print_header 2 "Setting up environment variables"

if [ -f ".env-dist" ]; then
    print_header 4 "Copying .env-dist to .env"
    cp .env-dist .env
fi

print_header 4 "Setting CONTENT_ROOT to /coverage_reloaded/content/files"
export CONTENT_ROOT="/coverage_reloaded/content/files"

# buildSPAs() fetches https://hacks.mozilla.org/feed/ for homepage content.
# That site is often unreachable; use a cached copy served by WayPack instead.
export BUILD_HOMEPAGE_FEED_URL="http://waypack:3000/local/hackmozillaorg_feed.rss"


print_header 2 "Installing dependencies"

yarn install --no-fund

set -uo pipefail

REPO_ROOT=$(pwd)

has_script() {
    local pkg=$1
    local script=$2
    cat "$pkg" | jq -e ".scripts[\"$script\"]" > /dev/null 2>&1
}

print_header 2 "Test run preparations"

# Generate popularities.json if it doesn't exist.
# The project's own start script uses the same guard pattern:
#   (test -f popularities.json || yarn tool:legacy popularities)
# Across history the command name changed:
#   - Early era: "yarn tool popularities" (via tool/cli.js or tool/cli.ts)
#   - Later era: "yarn tool:legacy popularities" (tool switched to bins/tool.mjs)
if [ ! -f "popularities.json" ]; then
    if has_script "package.json" "tool:legacy"; then
        yarn tool:legacy popularities
    elif has_script "package.json" "tool"; then
        yarn tool popularities
    else
        print_header 4 "WARNING: No tool script found to generate popularities.json"
    fi
fi

run_suite() {
    local suite=$1
    local cmd=$2
    print_header 2 "Running test suite: $suite"
    set +e
    eval "$cmd"
    EXIT_CODE=$?
    set -e
    cd "$REPO_ROOT"

    bash /coverage_reloaded/find-and-move-lcov.sh "$suite" "true" "$EXIT_CODE"
}

has_workspace() {
    local workspace=$1
    cat package.json | jq -e ".workspaces | index(\"$workspace\")" > /dev/null 2>&1
}

workspace_has_script() {
    local workspace=$1
    local script=$2
    [ -f "$workspace/package.json" ] && has_script "$workspace/package.json" "$script"
}

# --- Workspace era: yarn workspace ssr test ---
if has_workspace "ssr" && workspace_has_script "ssr" "test"; then
    run_suite "ssr" "cd ssr && yarn jest \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- Workspace era: yarn workspace client test ---
if has_workspace "client" && workspace_has_script "client" "test"; then
    # Early era uses react-scripts test
    if cat client/package.json | jq -e '.scripts.test' | grep -q "react-scripts"; then
        run_suite "client_workspace" "cd client && ./node_modules/.bin/react-scripts test \
            --no-bail \
            --coverage \
            --coverageReporters=lcov \
            --watchAll=false"
    else
        echo "=== Client workspace test script does not use react-scripts, PANIC ==="
        exit 1
    fi
fi

# --- Workspace era: yarn workspace testing test ---
if has_workspace "testing" && workspace_has_script "testing" "test"; then
    run_suite "testing_workspace" "cd testing && yarn jest \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- test:client (later era, node scripts/test.js) ---
if has_script "package.json" "test:client" && [ -f client/scripts/test.js ]; then
    run_suite "client" "cd client && NODE_ENV=test BABEL_ENV=test node scripts/test.js \
        --env=jsdom \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --watchAll=false"
fi

# --- test:kumascript ---
if has_script "package.json" "test:kumascript"; then
    run_suite "kumascript" "yarn jest --rootDir kumascript \
        --env=node \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- test:libs ---
if has_script "package.json" "test:libs"; then
    run_suite "libs" "yarn jest --rootDir libs \
        --env=node \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- test:build ---
if has_script "package.json" "test:build"; then
    run_suite "build" "yarn jest --rootDir build \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- test:content ---
if has_script "package.json" "test:content"; then
    run_suite "content" "yarn jest --rootDir content \
        --no-bail \
        --coverage \
        --coverageReporters=lcov"
fi

# --- test:testing ---
# Runs e2e tests under the hood. Skip.
# if has_script "package.json" "test:testing"; then
#     # The testing suite reads from ../client/build/ and uses Puppeteer.
#     # Set the testing env for all build steps (build:client/ssr don't read ENV_FILE
#     # but it's harmless to set it).
#     if [ -f ".env.testing" ]; then
#         export ENV_FILE=.env.testing
#     else
#         export ENV_FILE=testing/.env
#     fi

#     print_header 3 "Building client, SSR, and content from testing fixtures"
#     yarn prepare-build
#     env -u CONTENT_ROOT yarn build

#     # Unset ENV_FILE so tests that spawn child processes (like destructive.test.js)
#     # don't pick up the testing env overrides.
#     unset ENV_FILE
#     export TESTING_START_SERVER=true

#     run_suite "testing" "yarn run test:testing \
#         --no-bail \
#         --coverage \
#         --coverageReporters=lcov"
# fi