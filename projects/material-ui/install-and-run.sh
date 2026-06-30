#!/bin/bash

source /coverage_reloaded/logging.sh

set -e

cd /coverage_reloaded/repo


if $IS_NPM_MAIN_PM; then
    print_header 2 "Installing dependencies with npm..."
    npm install --no-fund --include=dev

    COMMAND="npm run"
elif $IS_YARN_MAIN_PM; then
    # Requires a non-existing dependency (vitest-mui, was deleted from registry)
    # Workaround: providing the file (vitest-mui-0.3.3.tgz and vitest-mui-0.3.4.tgz) in the waypack machine
    # Integrity checks fail for this file.
    # Workaround: clean cache with yarn cache clean disable integrity checks for yarn installs by adding --update-checksums
    print_header 2 "Installing dependencies with yarn..."
    yarn cache clean --force
    yarn install --update-checksums --ignore-engines

    COMMAND="yarn run"
elif $IS_PNPM_MAIN_PM; then
    print_header 2 "Installing dependencies with pnpm..."
    pnpm install

    COMMAND="pnpm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

set +e

print_header 2 "Running tests with coverage"

# Prevent Node.js from reparsing ambiguous .js files as ESM (which breaks __dirname usage)
# Only needed on Node >=20 where --experimental-detect-module is default
if [ "$(node -e "console.log(process.version.substring(1).split('.')[0])")" -ge 20 ] 2>/dev/null; then
    export NODE_OPTIONS="$NODE_OPTIONS --no-experimental-detect-module"
fi

$COMMAND test:coverage
npx --registry=$VERDACCIO_REGISTRY nyc report --reporter=lcov
EXIT_CODE=$?

set -e

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$EXIT_CODE"