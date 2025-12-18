#!/bin/bash
cd /app/repo

# yarn.lock files often contain resolved URLs to central repositories.
# Workaround 1: remove those lines to let yarn resolve them via the configured registry (waypack & verdaccio).
# [ -f "yarn.lock" ] && sed -i '/^  resolved/d' yarn.lock
# Workaround 2: replace URLs with waypack URL (https://registry.yarnpkg.com/)
[ -f "yarn.lock" ] && sed -i 's#resolved "https://registry.yarnpkg.com/#resolved "http://waypack:3000/yarn/'"$timestamp"'/#g' yarn.lock

yarn install

set +e
# Lerna monorepo do not work with nyc directly...
# Workaround: sentry-javascript seems to support the --coverage flag,
#   so we use that instead and then collect the coverage reports afterwards.
npx lerna run test --concurrency 1 -- --coverage
set -e

bash ../find-and-move-lcov.sh