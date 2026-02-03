#!/bin/bash
cd /coverage_reloaded/repo

yarn install

set +e
# Lerna monorepo do not work with nyc directly...
# Workaround: sentry-javascript seems to support the --coverage flag,
#   so we use that instead and then collect the coverage reports afterwards.

# npx requires npm_config_registry to be set every time it is called in order to use the verdaccio registry.
npx --registry=$WAYPACK_NPM_REGISTRY lerna run test --concurrency 1 -- --coverage
set -e

bash ../find-and-move-lcov.sh