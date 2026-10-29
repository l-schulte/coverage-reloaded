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

# Bound vitest's worker thread pool so that:
# 1. 256-core host oversubscription is avoided (default sizes from nproc=256 against cgroup quota).
# 2. Worker threads remain ENABLED (unlike --single-thread / --no-threads which breaks
#    worker isolation and causes editor-ui with jsdom to hang indefinitely).
export VITEST_MAX_THREADS=2
export VITEST_MIN_THREADS=2
export VITEST_MAX_WORKERS=2
export VITEST_MIN_WORKERS=2

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

ROOT_TEST=$(node -p "((require('./package.json').scripts||{}).test) || ''" || true)
if [ -z "$ROOT_TEST" ]; then
    not_applicable "No root test script at this commit"
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
        print_header 4 "lerna-era repo detected — running lerna bootstrap with --force-local"
        npm run bootstrap -- --force-local
    fi
elif [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    print_header 4 "pnpm-era repo detected — running pnpm install --no-frozen-lockfile"
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

# ── Patch temporal drift in Google Calendar test ────────────────────────────
# GenericFunctions.test.ts used hardcoded UNTIL=20251231, which expires when run
# past 2025. Upstream commit 20f5bdc4e8 fixed this by extending UNTIL to 20501231.
GCAL_TEST="packages/nodes-base/nodes/Google/Calendar/test/GenericFunctions.test.ts"
if [ -f "$GCAL_TEST" ] && grep -q "UNTIL=20251231" "$GCAL_TEST" 2>/dev/null; then
    print_header 4 "Patching temporal drift UNTIL=20251231 -> UNTIL=20501231 in $GCAL_TEST"
    sed -i 's/UNTIL=20251231/UNTIL=20501231/g' "$GCAL_TEST"
fi

# ── Patch package.json scripts to collect coverage and fix build order ──────
# Appends the runner-specific coverage flags to every `test*` script that
# directly invokes a runner, so the root `test` dispatch (lerna/turbo) collects
# lcov for each package. Also adds --no-bail/--continue to the root dispatch
# (tests must never bail), neutralises the e2e playwright `test` script, and
# rewrites legacy root build 'lerna exec npm run build' to topologically sorted
# 'lerna run build' BEFORE the build runs.
print_header 2 "Patching package.json scripts to collect coverage and fix build order"
node /coverage_reloaded/patch-coverage.js

# ── Build ────────────────────────────────────────────────────────────────────
# Tests import workspace packages via their dist/ entry points (e.g. cli imports
# n8n-core -> dist/). Build with the repo's own build script (lerna run build / turbo run build).
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
