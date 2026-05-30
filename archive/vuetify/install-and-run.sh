#!/bin/bash

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# ═══════════════════════════════════════════════════════════════════════════════
# VUETIFY COVERAGE COLLECTION
#
# Test-runner eras (detected from packages/vuetify `test` script):
#
#   Era         | PM        | test script             | Runner | Coverage source
#  ─────────────┼───────────┼─────────────────────────┼────────┼─────────────────
#   V1 (yarn)   | yarn@1.x  | node build/run-tests.js | jest   | jest --coverage
#   V1 (pnpm)   | pnpm@9-10 | node build/run-tests.js | jest   | jest --coverage
#   V2 (pnpm)   | pnpm@9-10 | vitest                  | vitest | vitest --coverage
#
# The `test` script flips from run-tests.js (jest) to `vitest` at commit
# 1979fd7b (~2024-09). pnpm appears slightly earlier, so there is a window of
# pnpm + jest commits — hence we detect the RUNNER from the test script text,
# not from the package manager.
#
# Collected coverage sources:
#   - Unit (jest V1, or vitest --project unit V2)  → primary, behavioral ✅
#   - Cypress component tests (mid-era)            → behavioral; collected via
#                                                    external instrumentation,
#                                                    since the project shipped
#                                                    NO cypress coverage config
#                                                    at these commits (patched
#                                                    in by us — provenance:
#                                                    externally instrumented) ✅
#
# NOT collected:
#   - vitest "browser" project (*.spec.browser.tsx, webdriverio + Chrome).
#     These specs ARE behavioral (assertion-driven, not visual snapshots), but
#     the per-commit WebDriver/Chrome environment does not reproduce reliably
#     across history. Excluded on FEASIBILITY grounds — see the V2 block below.
#   - E2E (packages/kitchen) — out of scope (deferred to future work).
#   - Vizzly / test:screen (latest era) — visual regression, out of scope.
# ═══════════════════════════════════════════════════════════════════════════════

# ── Cypress Coverage Config Patching ─────────────────────────────────────────
# Apply coverage-enabled patches to any Cypress config files at this commit
# BEFORE installing deps. The patcher matches file SHA256 against known
# originals and swaps in coverage-enabled versions. NOTE: at the commits we
# care about, Vuetify shipped no cypress coverage config of its own — this
# instrumentation is added by us (external provenance), which is acceptable
# under our exposure definition (coverage = lines executed by behavioral
# tests, whether or not the project measured them).

print_header 2 "Applying Cypress coverage patches"

CONFIG_DIR="/coverage_reloaded/cypress-coverage-configs"
if [ -d "$CONFIG_DIR" ] && [ -f "$CONFIG_DIR/mapper.tsv" ] && [ -d "$CONFIG_DIR/patches" ]; then
    bash /coverage_reloaded/cypress-patcher.sh \
        /coverage_reloaded/repo \
        "$CONFIG_DIR/mapper.tsv" \
        "$CONFIG_DIR/patches"
else
    print_header 3 "  No Cypress coverage configs found — skipping patching"
fi

# ── Dependency Installation ───────────────────────────────────────────────────

print_header 2 "Installing dependencies"

if $IS_NPM_MAIN_PM; then
    echo "ERROR: Vuetify does not use npm as package manager"
    exit 1

elif $IS_YARN_MAIN_PM; then
    # ── Yarn v1 era (majority of historical commits) ──────────────────────────
    print_header 3 " Installing dependencies with yarn..."

    yarn cache clean --force 2>/dev/null || true

    if [ -f yarn.lock ]; then
        yarn install --frozen-lockfile --update-checksums 2>&1 || \
        yarn install --update-checksums 2>&1
    else
        yarn install 2>&1
    fi

    if [ -f lerna.json ]; then
        print_header 3 " Bootstrapping with lerna..."
        npx lerna bootstrap 2>&1 || true
    fi

elif $IS_PNPM_MAIN_PM; then
    # ── pnpm era ─────────────────────────────────────────────────────────────
    print_header 3 " Installing dependencies with pnpm..."

    if [ -f pnpm-lock.yaml ]; then
        pnpm install --frozen-lockfile 2>&1 || \
        pnpm install 2>&1
    else
        pnpm install 2>&1
    fi

else
    print_header 2 "ERROR" "No main package manager detected"
    exit 1
fi

# ── Ensure cross-env is available ─────────────────────────────────────────────
# Used by many test/build scripts (e.g. "cross-env NODE_ENV=test jest").
# Workspace commands from packages/vuetify/ may not see root devDependencies.

print_header 2 "Ensuring cross-env availability"

if ! command -v cross-env &>/dev/null; then
    print_header 3 " cross-env not found globally, installing..."
    npm install --no-fund -g cross-env 2>&1 | tail -1
else
    print_header 3 " cross-env already available"
fi

if ! node -e "require.resolve('cross-env')" 2>/dev/null; then
    print_header 3 " cross-env not in local node_modules, installing..."
    npm install --no-save --no-fund cross-env 2>&1 | tail -1
fi

# ── Ensure @cypress/code-coverage is available ────────────────────────────────
# Cypress coverage patches reference @cypress/code-coverage for task
# registration + support imports. Cypress itself comes from project deps.

print_header 2 "Ensuring @cypress/code-coverage availability"

if ! node -e "try { require.resolve('@cypress/code-coverage'); console.log('found') } catch(e) { process.exit(1) }" 2>/dev/null; then
    print_header 3 "  @cypress/code-coverage not found, installing..."
    if $IS_PNPM_MAIN_PM; then
        pnpm add --save-dev @cypress/code-coverage 2>&1 | tail -5 || true
    elif $IS_YARN_MAIN_PM; then
        yarn add --dev @cypress/code-coverage -W 2>&1 | tail -5 || \
        yarn add --dev @cypress/code-coverage --ignore-workspace-root-check 2>&1 | tail -5 || true
    else
        npm install --no-save --no-fund @cypress/code-coverage 2>&1 | tail -5 || true
    fi
else
    print_header 3 "  @cypress/code-coverage already available"
fi

# ── Ensure vite-plugin-istanbul is available ──────────────────────────────────
# Vite-based Cypress era (Cypress 10+) needs vite-plugin-istanbul to inject
# __coverage__ instrumentation. Without it the browser code is uninstrumented
# and no Cypress coverage is produced.

print_header 2 "Ensuring vite-plugin-istanbul availability"

if ! node -e "try { require.resolve('vite-plugin-istanbul'); console.log('found') } catch(e) { process.exit(1) }" 2>/dev/null; then
    print_header 3 "  vite-plugin-istanbul not found, installing..."
    if $IS_PNPM_MAIN_PM; then
        pnpm add --save-dev vite-plugin-istanbul 2>&1 | tail -5 || true
    elif $IS_YARN_MAIN_PM; then
        yarn add --dev vite-plugin-istanbul -W 2>&1 | tail -5 || \
        yarn add --dev vite-plugin-istanbul --ignore-workspace-root-check 2>&1 | tail -5 || true
    else
        npm install --no-save --no-fund vite-plugin-istanbul 2>&1 | tail -5 || true
    fi
else
    print_header 3 "  vite-plugin-istanbul already available"
fi

# ── Global bail guard ─────────────────────────────────────────────────────────
# THE BAIL FLAG RULE (AGENT.md §13): a bailed run produces plausible-looking
# but truncated coverage that passes as success. vitest.workspace.ts has a
# conditional `bail: process.env.TEST_BAIL ? 1 : undefined`. Unset it once,
# unconditionally, before ANY runner executes, so no runner can bail.
unset TEST_BAIL

# ── Era Detection ─────────────────────────────────────────────────────────────
# Detect runner from the `test` script text. Every in-scope commit is either
# `node build/run-tests.js` (jest) or `vitest`; there is no other case, so
# there is no fallback branch.

print_header 2 "Detecting test runner"

cd packages/vuetify

TEST_SCRIPT=$(node -e "try { const p=require('./package.json'); console.log(p.scripts && p.scripts['test'] || ''); } catch { console.log(''); }" 2>/dev/null)

IS_V1=false
IS_V2=false

if echo "$TEST_SCRIPT" | grep -q "node build/run-tests.js"; then
    IS_V1=true
    echo "Detected V1: test = node build/run-tests.js → running Jest directly"
elif echo "$TEST_SCRIPT" | grep -q "vitest"; then
    IS_V2=true
    echo "Detected V2: test = vitest → running Vitest directly"
else
    echo "ERROR: Unrecognized test script: '$TEST_SCRIPT'"
    echo "       Expected 'node build/run-tests.js' (V1) or 'vitest' (V2)."
    echo "       Cannot determine runner — failing loudly."
    exit 1
fi

echo "TEST_SCRIPT: $TEST_SCRIPT"
echo "IS_V1:       $IS_V1"
echo "IS_V2:       $IS_V2"

cd /coverage_reloaded/repo

# ── Run Tests with Coverage ───────────────────────────────────────────────────
# We ignore runner exit codes (single test failures must not abort collection)
# and judge success by whether LCOV was produced. find-and-move-lcov.sh errors
# if a runner ran but produced no coverage.

mkdir -p coverage
set +e

cd packages/vuetify

RAN_ANY_TEST=false
COVERAGE_FAILURE=false

# ── 1. V1: Jest ───────────────────────────────────────────────────────────────
if [ "$IS_V1" = "true" ]; then
    RAN_ANY_TEST=true
    print_header 2 "V1: Running Jest with coverage"

    cd /coverage_reloaded/repo/packages/vuetify

    NODE_ENV=test npx jest --coverage --coverageReporters=lcov --no-cache 2>&1

    cd /coverage_reloaded/repo
    bash /coverage_reloaded/find-and-move-lcov.sh "jest" "true" || COVERAGE_FAILURE=true
fi

# ── 2. V2: Vitest (unit project only) ─────────────────────────────────────────
if [ "$IS_V2" = "true" ]; then
    RAN_ANY_TEST=true
    print_header 2 "V2: Running Vitest unit project with coverage"

    cd /coverage_reloaded/repo/packages/vuetify

    print_header 3 "Running Vitest unit tests"
    if $IS_PNPM_MAIN_PM; then
        pnpm exec vitest --project unit --coverage --coverage.reporter=lcov 2>&1
    else
        npx vitest --project unit --coverage --coverage.reporter=lcov 2>&1
    fi

    cd /coverage_reloaded/repo
    bash /coverage_reloaded/find-and-move-lcov.sh "vitest_unit" "true" || COVERAGE_FAILURE=true

    # ── V2 browser project: NOT COLLECTED (feasibility) ───────────────────
    # The vitest "browser" project (webdriverio + Chrome, *.spec.browser.tsx)
    # could not be collected reliably and is intentionally not run.
    #
    # These specs ARE behavioral — 570 `expect(` assertions across 34/41
    # specs, 0 percySnapshot calls in spec bodies (the visual/Percy layer
    # lives in the browser-setup harness, not the specs). This is therefore
    # NOT a visual-regression / non-behavioral exclusion.
    #
    # The blocker is purely environmental: the browser project needs a
    # per-commit WebDriver + Chrome setup that does not reproduce across
    # history (browserVersion pinning vs installed Chrome, @vitest/browser
    # pnpm hoisting, vitest 3.1.x custom-root bug). Stabilizing this per
    # commit was incommensurate with its marginal coverage contribution,
    # consistent with the project-wide decision to defer E2E.
    #
    # CONSEQUENCE: for vitest-era commits whose behavioral suite is
    # unit + browser, unit-only coverage UNDERSTATES exposure. This is the
    # basis on which Vuetify is being assessed against the >=90%-complete
    # criterion. See archive note.
    print_header 3 "Skipping Vitest browser project — coverage not reliably collectable (WebDriver/Chrome per-commit env). Behavioral, but excluded on feasibility. NOT a visual-regression exclusion."
fi

# ── 3. Cypress component tests (if cy:run exists) ─────────────────────────────
# Behavioral component tests (mid-era). Coverage via patched-in
# @cypress/code-coverage (external instrumentation). cy:run forms over time:
#   cypress run-ct  →  percy exec -- cypress run-ct  →  percy exec -- cypress run --component
# We strip the `percy exec --` wrapper (Percy unavailable here) and run the
# bare cypress command; the specs' assertions are what we collect.
# NOTE: packages/kitchen E2E (cypress:run = bare `cypress run`, server-
# dependent) is deliberately NOT collected — E2E is out of scope.

print_header 2 "Checking for Cypress component tests"

CYPRESS_CMD=""
if [ -f "/coverage_reloaded/repo/packages/vuetify/package.json" ]; then
    CYPRESS_CMD=$(node -p "const p=require('/coverage_reloaded/repo/packages/vuetify/package.json'); (p.scripts&&p.scripts['cy:run'])||''" 2>/dev/null || echo "")
fi

if [ -n "$CYPRESS_CMD" ]; then
    RAN_ANY_TEST=true
    print_header 3 "  Found cy:run: $CYPRESS_CMD"

    cd /coverage_reloaded/repo/packages/vuetify

    # Strip percy wrapper, --bail (truncates coverage), and --headed
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD#percy exec -- }"
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD_CLEAN/--bail/}"
    CYPRESS_CMD_CLEAN="${CYPRESS_CMD_CLEAN/--headed/}"
    CYPRESS_CMD_CLEAN="$(echo "$CYPRESS_CMD_CLEAN" | tr -s ' ')"

    print_header 3 "  Running: xvfb-run npx $CYPRESS_CMD_CLEAN"

    xvfb-run --auto-servernum npx $CYPRESS_CMD_CLEAN
    CYPRESS_EXIT=$?
    print_header 3 "  Cypress exit code: $CYPRESS_EXIT"

    # @cypress/code-coverage writes .nyc_output/out.json → convert to lcov
    cd /coverage_reloaded/repo
    if [ -f ".nyc_output/out.json" ]; then
        print_header 3 "  Converting Cypress coverage (root) to lcov"
        npx nyc report --reporter=lcovonly --report-dir=coverage/cypress 2>&1 || true
    fi
    if [ -f "packages/vuetify/.nyc_output/out.json" ]; then
        print_header 3 "  Converting Cypress coverage (packages/vuetify) to lcov"
        (cd packages/vuetify && npx nyc report --reporter=lcovonly --report-dir=coverage/cypress 2>&1) || true
    fi

    bash /coverage_reloaded/find-and-move-lcov.sh "cypress" "true" || COVERAGE_FAILURE=true

    cd packages/vuetify
else
    print_header 3 "  No cy:run script found — skipping Cypress tests"
fi

# ── 4. Final exit code ────────────────────────────────────────────────────────
if [ "$RAN_ANY_TEST" = true ] && [ "$COVERAGE_FAILURE" = true ]; then
    echo "ERROR: One or more test runners executed but produced no coverage files."
    GLOBAL_TEST_EXIT=1
elif [ "$RAN_ANY_TEST" = false ]; then
    echo "ERROR: No test infrastructure detected (no V1/V2 runner, no cy:run script)"
    GLOBAL_TEST_EXIT=1
else
    GLOBAL_TEST_EXIT=0
fi

set -e