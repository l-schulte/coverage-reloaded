#!/bin/bash

# n8n coverage collection
#
# n8n is a large monorepo. Over the 2020-2025 timeframe it was orchestrated by:
#   - npm + lerna (2020-01 .. 2022-08):  root test = `lerna run test`
#   - npm + turbo (2022-08 .. 2022-11):  root test = `turbo run test`
#   - pnpm + turbo (2022-11 .. 2025-12): root test = `turbo run test`
#
# Runners: jest (backend, whole timeframe), vitest (frontend + later backend),
# vue-cli-service test:unit (early frontend, wraps jest). e2e (cypress/playwright)
# is excluded and never part of the root `test` dispatch.
#
# Strategy: install, build (tests import workspace packages via dist/), then patch
# every package.json `test*` script to enable the runner's own coverage with an
# lcov reporter, then run the root `test` script once.

set -e

source /coverage_reloaded/logging.sh

# Large jest/vitest suites and the webpack-based editor-ui build can OOM without a headroom bump.
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=8192"

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

ROOT_TEST=$(node -p "((require('./package.json').scripts||{}).test) || ''" || true)
if [ -z "$ROOT_TEST" ]; then
    print_header 2 "NOT APPLICABLE" "No root test script at this commit"
    exit 2
fi
print_header 4 "Root test script: $ROOT_TEST"

# ── Install ──────────────────────────────────────────────────────────────────
print_header 2 "Installing dependencies"

if [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install
    PM_RUN="npm run"
    PM_TEST="npm test"
    HAS_BOOTSTRAP=$(node -p "!!((require('./package.json').scripts||{}).bootstrap)")
    if [ "$HAS_BOOTSTRAP" = "true" ]; then
        print_header 4 "lerna-era repo detected — running lerna bootstrap"
        npm run bootstrap
    fi
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install --no-frozen-lockfile
    PM_RUN="pnpm run"
    PM_TEST="pnpm test"
else
    print_header 2 "Unsupported package manager for n8n (expects npm or pnpm): $package_manager"
    exit 1
fi

# ── Patch dead Google Fonts helper API ──────────────────────────────────────
# @beyonk/google-fonts-webpack-plugin defaults its apiUrl to
# https://google-webfonts-helper.herokuapp.com/api/fonts, which has been dead
# since Heroku shut down free-tier apps (Nov 2022). The plugin hangs the
# vue-cli-service build when this endpoint is unreachable.
# The service was redeployed at https://gwfh.mranftl.com — patch vue.config.js
# to point the plugin at the working endpoint.
VUE_CONFIG="packages/editor-ui/vue.config.js"
if [ -f "$VUE_CONFIG" ] && grep -q "GoogleFontsPlugin" "$VUE_CONFIG" 2>/dev/null; then
    print_header 4 "Patching Google Fonts plugin apiUrl in $VUE_CONFIG"
    sed -i 's|new GoogleFontsPlugin({|new GoogleFontsPlugin({\n\t\t\t\tlocal: false,\n\t\t\t\tapiUrl: "https://gwfh.mranftl.com/api/fonts",|' "$VUE_CONFIG"
fi

# ── Build ────────────────────────────────────────────────────────────────────
# Tests import workspace packages via their dist/ entry points (e.g. cli imports
# n8n-core -> dist/). Build with the repo's own build script (lerna exec / turbo run build).
#
# set +e wraps the build so that a non-zero exit code (e.g. exit 2 from a
# TypeScript compile error in a sub-package) does not leak out as the script's
# own exit code. execute.sh treats exit 2 as "not applicable", which would
# silently discard a real build failure. We remap any build failure to exit 1.
HAS_BUILD=$(node -p "!!((require('./package.json').scripts||{}).build)")
if [ "$HAS_BUILD" = "true" ]; then
    print_header 2 "Building workspace packages"
    set +e
    $PM_RUN build
    BUILD_EXIT=$?
    set -e
    if [ $BUILD_EXIT -ne 0 ]; then
        print_header 2 "Build failed with exit code $BUILD_EXIT"
        exit 1
    fi
else
    print_header 2 "No root build script at this commit — skipping build"
fi

# ── Patch package.json test scripts to collect coverage ──────────────────────
# Appends the runner-specific coverage flags to every `test*` script that
# directly invokes a runner, so the root `test` dispatch (lerna/turbo) collects
# lcov for each package. Also adds --no-bail/--continue to the root dispatch
# (tests must never bail) and neutralises the e2e playwright `test` script.
print_header 2 "Patching package.json test scripts to collect coverage"
node /coverage_reloaded/patch-coverage.js

# ── Run root test with coverage ─────────────────────────────────────────────
print_header 2 "Running root test suite with coverage"

export COVERAGE_ENABLED=true

suite_start "test" "Running root test dispatch ($ROOT_TEST)"

set +e
$PM_TEST
TEST_EXIT=$?
set -e

bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"
suite_end "test" "$TEST_EXIT"

print_header 1 "n8n coverage run complete"
