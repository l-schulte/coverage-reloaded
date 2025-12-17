#!/bin/bash
cd /app/repo

if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    echo "=== Running with pnpm ==="

    pnpm install

    set +e
    pnpm run test -- --coverage --continue
    set -e
elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
    echo "=== Running with yarn ==="

    yarn install

    set +e
    yarn run test --coverage --continue
    set -e
else
    echo "=== Running with npm ==="

    npm ci

    set +e
    npm run test -- --coverage --continue
    set -e
fi
