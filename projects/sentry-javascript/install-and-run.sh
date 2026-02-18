#!/bin/bash

set -euo pipefail

cd /coverage_reloaded/repo

if $IS_NPM_MAIN_PM; then
    echo "Installing dependencies with npm..."
    npm install --no-fund --include=dev
    PKG_MANAGER="npm"
elif $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install --no-fund --dev
    PKG_MANAGER="yarn"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."
    pnpm install
    PKG_MANAGER="pnpm"
else
    echo "No main package manager detected... raising error."
    exit 1
fi

TEST_SCRIPT=$(node -p "require('./package.json').scripts.test")

PROBLEMATIC_FILES=$(find . -mindepth 2 -name "package.json" \
  -not -path "*/node_modules/*" \
  -not -path "./.git/*" \
  | xargs grep -l '"test"' \
  | xargs node -e "
    const fs = require('fs');
    process.argv.slice(1).forEach(f => {
      const p = JSON.parse(fs.readFileSync(f));
      if (p.scripts && p.scripts.test && p.scripts.test.includes('lerna'))
        console.log(f);
    });
  ")

if echo "$TEST_SCRIPT" | grep -q "lerna" && [ -n "$PROBLEMATIC_FILES" ]; then
  echo "ERROR: subpackage test scripts contain lerna - --coverage passthrough unreliable:"
  echo "$PROBLEMATIC_FILES"
  exit 1
fi

set +e
if echo "$TEST_SCRIPT" | grep -q "^lerna"; then
    # Append -- --coverage to the lerna call directly
    npx --registry=$WAYPACK_NPM_REGISTRY $TEST_SCRIPT --no-bail -- --coverage
else
    # Direct jest variants
    $PKG_MANAGER run test -- --coverage
fi
set -e

bash ../find-and-move-lcov.sh