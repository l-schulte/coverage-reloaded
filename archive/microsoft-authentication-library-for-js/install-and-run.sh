#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

npm install --no-fund --include=dev --unsafe-perm

TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")

find . -name "package.json" -not -path "*/node_modules/*" -exec sed -i 's/--reporter=text/--reporter=lcov/g' {} +


if [ -n "$TEST_COVERAGE_SCRIPT" ]; then
    print_header 2 "Running using root package"

    print_header 3 "Building..."
    npm run build

    print_header 3 "Running tests with test:coverage..."
    set +e
    npm run test:coverage
else
    print_header 2 "Running using workspaces"

    print_header 3 "Building..."
    npm run build --workspaces --if-present

    print_header 3 "Running tests with test:coverage..."
    set +e
    npm run test:coverage --workspaces --if-present
fi

bash ../find-and-move-lcov.sh unit True
    
set -e