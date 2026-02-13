#!/bin/bash
cd /coverage_reloaded/repo

if $IS_NPM_MAIN_PM; then
    echo "Installing dependencies with npm..."
    npm install --no-fund --include=dev
elif $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install --no-fund --dev
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install
else
    echo "No main package manager detected... raising error."
    exit 1
fi

# set +e
# Lerna monorepo do not work with nyc directly...
# Workaround: sentry-javascript seems to support the --coverage flag,
#   so we use that instead and then collect the coverage reports afterwards.

# npx requires npm_config_registry to be set every time it is called in order to use the verdaccio registry.
npx --registry=$WAYPACK_NPM_REGISTRY lerna run test --concurrency 1 -- --coverage
# set -e

bash ../find-and-move-lcov.sh