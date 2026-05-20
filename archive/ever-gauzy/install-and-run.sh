#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

cd /coverage_reloaded/repo

print_header 2 "Installing dependencies"

yarn install --ignore-engines
yarn add rimraf
yarn add jest-preset-angular


TEST_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test'] || ''")

# find . -name "package.json" -not -path "*/node_modules/*" -exec sed -i 's/--reporter=text/--reporter=lcov/g' {} +

export NX_NO_CLOUD=true

if [ -n "$TEST_COVERAGE_SCRIPT" ]; then
    print_header 2 "Building project" "with yarn"
    yarn build

    print_header 2 "Running tests" "with yarn"
    set +e
    yarn nx run-many --target=test --exclude=. --skip-nx-cache --verbose
else
    print_header 2 "Initializing lerna" "with lerna init"
    lerna init

    print_header 2 "Building project" "with lerna"
    lerna run build --workspaces --if-present --no-bail

    print_header 2 "Running tests" "with lerna"
    set +e
    lerna run test --workspaces --if-present --no-bail
fi

bash ../find-and-move-lcov.sh jest
    
set -e