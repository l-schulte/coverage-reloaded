
#!/bin/bash
cd /app/repo

if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    echo "=== Running with pnpm ==="

    pnpm install

    set +e
    pnpm dlx turbo run test --continue -- --coverage.enabled true
    set -e
elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
    echo "=== Running with yarn ==="
    
    yarn install

    # check if turbo.json exists
    if [ -f "turbo.json" ]; then
        echo " --> mono-repo detected via turbo.json"
        yarn global add turbo
        set +e
        yarn exec turbo run test --continue --coverage
        set -e
    elif [ -f "lerna.json" ]; then
        echo " --> mono-repo detected via lerna.json"
        yarn global add lerna
        yarn exec lerna init
        set +e
        # Notes:
        # seems to fail with unknown option "coverage" in some (or all?) versions
        # coverate is still generated though
        yarn exec lerna run test --no-bail
        set -e
    else
        echo " --> single-package repo detected"
        set +e
        yarn test --coverage --continue
        set -e
    fi
else
    echo "=== Running with npm ==="

    # npm ci

    # set +e
    # npm run test -- --coverage --continue
    # set -e

    # npm not setup, throw error
    echo "Error: npm is not set up in this project."
    exit 1
fi
