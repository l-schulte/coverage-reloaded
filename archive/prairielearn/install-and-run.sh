#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies" "using npm"
    npm install --no-fund --include=dev --legacy-peer-deps
    COMMAND="npm"
elif $IS_YARN_MAIN_PM; then
    print_header 2 "Installing dependencies" "using yarn"
    yarn install
    COMMAND="yarn"
else
    echo "No configured package manager detected... raising error."
    exit 1
fi

TEST_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")
set +e

if [ -n "$TEST_SCRIPT" ]; then
    print_header 2 "Running package level tests"
    $COMMAND test
    bash ../find-and-move-lcov.sh package
else
    print_header 2 "Building workspaces"
    npx turbo run build
    print_header 2 "Running workspace level tests"
    $COMMAND workspaces foreach --all run test
    bash ../find-and-move-lcov.sh workspace
fi
    
set -e