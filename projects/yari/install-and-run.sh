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
    print_header 4 "Setting CONTENT_ROOT to /coverage_reloaded/repo/content/files"
    export CONTENT_ROOT="/coverage_reloaded/repo/content/files"
else
    print_header 4 "Found content commit $CONTENT_COMMIT before timestamp $timestamp"
    git checkout "$CONTENT_COMMIT"

    print_header 4 "Setting CONTENT_ROOT to /coverage_reloaded/content/files"
    export CONTENT_ROOT="/coverage_reloaded/content/files"
fi

cd /coverage_reloaded/repo

print_header 2 "Setting up environment variables"

# Source .env.testing to override all env vars with the testing configuration.
# The yari project ships .env.testing with CONTENT_ROOT=testing/content/files
# pointing to its own fixture data. The globally exported CONTENT_ROOT from the
# checkout step above would otherwise block dotenv from applying this value
# (dotenv does not override existing env vars).
if [ -f ".env.testing" ]; then
    set -a
    source .env.testing
    set +a
    print_header 4 "Sourced .env.testing"
elif [ -f "testing/.env" ]; then
    set -a
    source testing/.env
    set +a
    print_header 4 "Sourced testing/.env"
fi

if [ -f ".env-dist" ]; then
    print_header 4 "Copying .env-dist to .env"
    cat .env-dist
    cp .env-dist .env
fi

# buildSPAs() fetches https://hacks.mozilla.org/feed/ and
# https://hacks.mozilla.org/category/mdn/feed/ for homepage content.
# Those sites are often unreachable; use cached copies served by WayPack instead.
export BUILD_HOMEPAGE_FEED_URL="http://waypack:3000/local/hackmozillaorg_feed.rss"

# Patch the hardcoded URL in build/spas.js to use WayPack local file instead.
# The fetchLatestNews() function hardcodes the URL rather than reading an env var.
# At some commits the file is build/spas.ts (before compilation), at others it's
# build/spas.js (compiled output). Patch whichever exists.
if [ -f build/spas.ts ]; then
    print_header 4 "Patching build/spas.ts to use WayPack local file instead of hacks.mozilla.org"
    sed -i 's|https://hacks.mozilla.org/category/mdn/feed/|http://waypack:3000/local/hackmozillaorg_category_mdn_feed.rss|g' \
        build/spas.ts
fi
if [ -f build/spas.js ]; then
    print_header 4 "Patching build/spas.js to use WayPack local file instead of hacks.mozilla.org"
    sed -i 's|https://hacks.mozilla.org/category/mdn/feed/|http://waypack:3000/local/hackmozillaorg_category_mdn_feed.rss|g' \
        build/spas.js
fi

# Patch the hardcoded popularities URL in tool/popularities.ts.
# The S3 bucket (mdn-popularities-prod) no longer exists; use cached 
# copies served by WayPack instead.
if [ -f tool/popularities.ts ]; then
    print_header 4 "Patching tool/popularities.ts to use WayPack local file instead of S3 bucket"
    sed -i 's|https://mdn-popularities-prod.s3.amazonaws.com/current.txt|http://waypack:3000/local/mdn-current.txt|g' \
        tool/popularities.ts
fi
if [ -f tool/popularities.js ]; then
    print_header 4 "Patching tool/popularities.js to use WayPack local file instead of S3 bucket"
    sed -i 's|https://mdn-popularities-prod.s3.amazonaws.com/current.txt|http://waypack:3000/local/mdn-current.txt|g' \
        tool/popularities.js
fi


print_header 2 "Installing dependencies"

yarn install --no-fund

print_header 2 "Preparing build (if applicable)"

if [ -f ".env.testing" ]; then
    export ENV_FILE=.env.testing
else
    export ENV_FILE=testing/.env
fi

HAS_BUILD_PREPARE_SCRIPT=$(jq -r '.scripts["build:prepare"] // empty' package.json 2>/dev/null)
HAS_PREPARE_BUILD_SCRIPT=$(jq -r '.scripts["prepare-build"] // empty' package.json 2>/dev/null)
HAS_BUILD_LEGACY_PREPARE_SCRIPT=$(jq -r '.scripts["build:legacy:prepare"] // empty' package.json 2>/dev/null)
DID_BUILD=false
if [ "$HAS_BUILD_PREPARE_SCRIPT" ]; then
    print_header 3 "Running yarn build:prepare" "$HAS_BUILD_PREPARE_SCRIPT"
    yarn build:prepare
    DID_BUILD=true
fi
if [ "$HAS_PREPARE_BUILD_SCRIPT" ]; then
    print_header 3 "Running yarn prepare-build" "$HAS_PREPARE_BUILD_SCRIPT"
    yarn prepare-build
    DID_BUILD=true
fi
if [ "$HAS_BUILD_LEGACY_PREPARE_SCRIPT" ]; then
    print_header 3 "Running yarn build:legacy:prepare" "$HAS_BUILD_LEGACY_PREPARE_SCRIPT"
    yarn build:legacy:prepare
    DID_BUILD=true
fi

if [ "$DID_BUILD" = "false" ]; then
    print_header 4 "No build preparation scripts found, skipping build"
fi

print_header 2 "Building"

BUILD_SCRIPT=$(jq -r '.scripts["build"] // empty' package.json 2>/dev/null)
if [ "$BUILD_SCRIPT" != "" ]; then
    print_header 3 "Running yarn build" "$BUILD_SCRIPT"
    yarn build | tail -n 20
else
    print_header 4 "No build script found, skipping build"
fi

set -uo pipefail

REPO_ROOT=$(pwd)

run_suite() {
    local suite=$1
    local cmd=$2
    suite_start "$suite" "Running test suite: $suite"
    set +e
    eval "$cmd"
    EXIT_CODE=$?
    set -e
    cd "$REPO_ROOT"

    bash /coverage_reloaded/find-and-move-lcov.sh "$suite" "true" "$EXIT_CODE"
    suite_end "$suite" "$EXIT_CODE"
}

has_script() {
    local pkg=$1
    local script=$2
    cat "$pkg" | jq -e ".scripts[\"$script\"]" > /dev/null 2>&1
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
# DISABLED: ssr/syntax-highlighter.test.js was a stub that was never functional.
# The source uses ESM import/export but the test uses require(), and there was
# never any babel/jest config to bridge the gap. The ssr workspace only had this
# one test file, and it was never runnable throughout its entire lifetime
# (Apr–Aug 2020) before the workspace was deleted.
# if has_workspace "ssr" && workspace_has_script "ssr" "test"; then
#     run_suite "ssr" "cd ssr && yarn jest \
#         --no-bail \
#         --coverage \
#         --coverageReporters=lcov"
# fi

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

# --- Workspace era: yarn workspace testing test ---
# Runs e2e tests under the hood. Skip.
# if has_workspace "testing" && workspace_has_script "testing" "test"; then
#     run_suite "testing_workspace" "cd testing && yarn jest \
#         --no-bail \
#         --coverage \
#         --coverageReporters=lcov"
# fi

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