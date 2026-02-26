#!/bin/bash

cd /coverage_reloaded/repo


if $IS_NPM_MAIN_PM; then
    echo "Installing dependencies with npm..."
    npm install --no-fund

    set +e

    COMMAND="npm"
elif $IS_YARN_MAIN_PM; then
    echo "Installing dependencies with yarn..."
    yarn install

    set +e

    COMMAND="yarn"
elif $IS_PNPM_MAIN_PM; then
    echo "Installing dependencies with pnpm..."

    # Problem: pnpm fails with "ERR_PNPM_OUTDATED_LOCKFILE" : Cannot install with "frozen-lockfile" 
    # because pnpm-lock.yaml is not up to date with <ROOT>/backend/services/automations/package.json
    # Solution: use --no-frozen-lockfile to ignore the lockfile and install dependencies based on package.json
    pnpm install --no-frozen-lockfile

    set +e

    pnpm nx test
else
    echo "No main package manager detected... raising error."
    exit 1
fi
    
set -e