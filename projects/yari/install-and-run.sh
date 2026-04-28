#!/bin/bash

cd /coverage_reloaded/repo

yarn install --no-fund

set -uo pipefail

REPO_ROOT=$(pwd)

run_suite() {
    local suite=$1
    local cmd=$2
    echo "=== Running test suite: $suite ==="
    if eval "$cmd"; then
        echo "=== Suite $suite completed successfully ==="
    else
        echo "=== Suite $suite failed, continuing... ==="
    fi
    cd "$REPO_ROOT"
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


echo "We need to make sure that the coverage dirs are correct. I think we can remove them and just run find-and-move-lcov with the prepending of paths"
exit 1

# --- Workspace era: yarn workspace ssr test ---
if has_workspace "ssr" && workspace_has_script "ssr" "test"; then
    run_suite "ssr" "cd ssr && yarn jest \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_ssr"
fi

# --- Workspace era: yarn workspace client test ---
if has_workspace "client" && workspace_has_script "client" "test"; then
    # Early era uses react-scripts test
    if cat client/package.json | jq -e '.scripts.test' | grep -q "react-scripts"; then
        run_suite "client_workspace" "cd client && ./node_modules/.bin/react-scripts test \
            --no-bail \
            --coverage \
            --coverageReporters=lcov \
            --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_client \
            --watchAll=false"
    fi
fi

# --- test:client (later era, node scripts/test.js) ---
if has_script "package.json" "test:client" && [ -f client/scripts/test.js ]; then
    run_suite "client" "cd client && NODE_ENV=test BABEL_ENV=test node scripts/test.js \
        --env=jsdom \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_client \
        --watchAll=false"
fi

# --- test:kumascript ---
if has_script "package.json" "test:kumascript"; then
    run_suite "kumascript" "yarn jest --rootDir kumascript \
        --env=node \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_kumascript"
fi

# --- test:libs ---
if has_script "package.json" "test:libs"; then
    run_suite "libs" "yarn jest --rootDir libs \
        --env=node \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_libs"
fi

# --- test:build ---
if has_script "package.json" "test:build"; then
    run_suite "build" "yarn jest --rootDir build \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_build"
fi

# --- test:content ---
if has_script "package.json" "test:content"; then
    run_suite "content" "yarn jest --rootDir content \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_content"
fi

# --- test:testing ---
if has_script "package.json" "test:testing"; then
    run_suite "testing" "yarn jest --rootDir testing \
        --no-bail \
        --coverage \
        --coverageReporters=lcov \
        --coverageDirectory=$COVERAGE_REPORT_PATH/co_re_testing"
fi

echo "=== All suites finished ==="