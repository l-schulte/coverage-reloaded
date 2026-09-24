#!/bin/bash

set -e

# Increase Node.js heap size to avoid WebAssembly out-of-memory errors in worker threads (vitest/tinypool).
export NODE_OPTIONS="--max-old-space-size=8192 --require /coverage_reloaded/pool-shim.js"

# Disable Cypress binary download during npm install (e2e suite is excluded, sandbox has no external network)
export CYPRESS_INSTALL_BINARY=0

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

# mocha_check_passing
# Reads a mocha run's output from stdin, streams it through live (so it still reaches
# the run log), and checks for an "N passing" summary. Returns 0 if the run completed
# and 1 if it did NOT (heap OOM, suite-aborting TypeError, worker death, etc.) — on an
# incomplete run it discards any partial lcov.info so find-and-move-lcov.sh fails hard
# instead of emitting misleading partial coverage. Reusable across mocha-based suites:
#   npm run test:unit:forge -- --exit --no-bail 2>&1 | mocha_check_passing
mocha_check_passing() {
    local out_file
    out_file=$(mktemp)
    tee "$out_file"
    if ! grep -qE '^[[:space:]]*[0-9]+ passing' "$out_file" 2>/dev/null; then
        echo "  [NFO] mocha run did not complete (no passing-summary) — discarding partial coverage and failing hard"
        find "$REPOPATH" -name lcov.info -not -path '*/node_modules/*' -delete
        rm -f "$out_file"
        return 1
    fi
    rm -f "$out_file"
    return 0
}

cd /coverage_reloaded/repo

# --- License fix (coverage_reloaded) ----------------------------------------
# 2022-era history ships EE test suites that supply a license (e.g. "Ben Hardill")
# signed by the project's CI dev key, which does NOT match the dev key committed
# to the repo. In our env applyLicense() therefore throws "Failed to apply license:
# invalid signature" and the app crashes at startup, aborting the whole forge suite.
# The repo's own commented-out developer license ("devLicense", FlowForge Inc.
# Development) IS signed by the committed key and verifies at every affected commit.
#
# Fix = FALLBACK (not force): when a suite supplies a license that fails to validate,
# substitute the valid bundled devLicense so the app starts with an active license
# (matching the project's real CI, where that supplied license is valid). When a
# suite supplies NO license we leave it unlicensed (CE mode), so CE auth-ACL tests
# still expect 401 and test:system's "First run setup" (body.license === false) stays
# green. This resolves all three failure modes (startup crash; EE tests getting 401;
# CE tests getting 200). Applied to every forge suite; never reverted. Verified
# uniform across all 869 affected commits (devLicense verifies against the committed
# dev key at each; the only license-rejection test, loader_spec, checks verifyLicense
# directly and is untouched).
apply_license_fix() {
    if [ -f forge/licensing/index.js ] && grep -q "let userLicense = await app.settings.get('license')" forge/licensing/index.js; then
        print_header 4 "License fix: fall back to bundled devLicense when a supplied license is invalid (forge/licensing/index.js)"
        # 1) make the bundled devLicense available in module scope
        sed -i "s|^    // const devLicense = |    const devLicense = |" forge/licensing/index.js
        # 2) in the startup apply, fall back to devLicense instead of throwing
        sed -i "s|throw new Error('Failed to apply license: ' + err.toString())|app.log.warn('Failed to apply supplied license: ' + err.toString() + '; falling back to bundled devLicense'); await applyLicense(devLicense)|" forge/licensing/index.js
    fi
}

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

# --- Git submodules for local file: dependencies ----------------------------
# In late 2021 / early 2022 (commits between f4c5a1a5f and 1abc71dfe), package.json
# declares dependencies on local paths (e.g. "file:sub_modules/flowforge-driver-localfs")
# tracked as Git submodules. Without initializing them, the directories are empty
# and npm install fails with ENOLOCAL.
if [ -f .gitmodules ] && grep -q "file:sub_modules/" package.json; then
    print_header 2 "Initializing Git submodules for local dependencies"
    git config --global url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true
    git submodule update --init
fi

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install --frozen-lockfile
    PM_RUN="yarn run"
elif $IS_NPM_MAIN_PM; then
    npm install
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# --- Native module rebuild (sqlite3) -----------------------------------------
# In our sandbox the prebuilt native addon for sqlite3 is sometimes missing or
# built against an incompatible glibc / Node-ABI, surfacing as
# "Could not locate the bindings file" or "GLIBC_2.x not found" and crashing the
# forge/system suites (lost coverage). Rebuild affected native modules from
# source *only when their binding fails to load*, so the ~tens of thousands of
# runs that already work are not recompiled.
if [ -d node_modules/sqlite3 ]; then
    print_header 2 "Verifying sqlite3 native binding"
    if ! node -e "require('sqlite3')" >/dev/null 2>&1; then
        print_header 4 "sqlite3 binding unloadable — rebuilding from source"
        # Force node-pre-gyp to compile from source instead of re-downloading a
        # prebuilt binary. Prebuilts are often built against a newer glibc than
        # our base image (bullseye, glibc 2.31) and fail to load with
        # "GLIBC_2.x not found". A source build links against the image's glibc.
        npm_config_build_from_source=true npm rebuild sqlite3
    else
        print_header 4 "sqlite3 binding OK — no rebuild needed"
    fi
fi

print_header 2 "Detecting test scripts and infrastructure"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.test || '')")
TEST_UNIT_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit'] || '')")
TEST_UNIT_FORGE_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit:forge'] || '')")
TEST_UNIT_FRONTEND_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:unit:frontend'] || '')")
TEST_SYSTEM_SCRIPT=$(node -p "p=require('./package.json').scripts; (p['test:system'] || '')")

HAS_NYC=0
if [ -f .nycrc.json ] || node -e "process.exit(require('./package.json').devDependencies?.nyc ? 0 : 1)" 2>/dev/null; then
    HAS_NYC=1
fi

HAS_FORGE=0
if [ -n "$TEST_UNIT_FORGE_SCRIPT" ]; then
    HAS_FORGE=1
fi

HAS_FRONTEND=0
if [ -n "$TEST_UNIT_FRONTEND_SCRIPT" ]; then
    HAS_FRONTEND=1
fi

HAS_UNIT=0
if [ -n "$TEST_UNIT_SCRIPT" ]; then
    HAS_UNIT=1
fi

HAS_SYSTEM=0
if [ -n "$TEST_SYSTEM_SCRIPT" ]; then
    HAS_SYSTEM=1
fi

HAS_TEST=0
if [ -n "$TEST_SCRIPT" ] && ! echo "$TEST_SCRIPT" | grep -q "Error: no test specified"; then
    HAS_TEST=1
fi

print_header 4 "test:                 $TEST_SCRIPT"
print_header 4 "test:unit:            $TEST_UNIT_SCRIPT"
print_header 4 "test:unit:forge:      $TEST_UNIT_FORGE_SCRIPT"
print_header 4 "test:unit:frontend:   $TEST_UNIT_FRONTEND_SCRIPT"
print_header 4 "test:system:          $TEST_SYSTEM_SCRIPT"
print_header 4 "HAS_NYC=$HAS_NYC  HAS_FORGE=$HAS_FORGE  HAS_FRONTEND=$HAS_FRONTEND  HAS_UNIT=$HAS_UNIT  HAS_SYSTEM=$HAS_SYSTEM  HAS_TEST=$HAS_TEST"

if [ $HAS_FORGE -eq 0 ] && [ $HAS_FRONTEND -eq 0 ] && [ $HAS_UNIT -eq 0 ] && [ $HAS_SYSTEM -eq 0 ] && [ $HAS_TEST -eq 0 ]; then
    not_applicable "No test scripts found at this commit, no test infrastructure to run"
fi

if [ $HAS_NYC -eq 1 ]; then
    COVER_TOOL=(npx --registry="$WAYPACK_REGISTRY_CURRENT" nyc --reporter=lcov)
    print_header 4 "Coverage tool: nyc"
else
    COVER_TOOL=(npx --registry="$WAYPACK_REGISTRY_CURRENT" c8 --reporter=lcov --)
    print_header 4 "Coverage tool: c8"
fi

# Forge backend tests start the app server and need frontend/dist/index.html.
print_header 2 "Building frontend assets"
npm run build

print_header 2 "Running tests with coverage"

# IMPORTANT: set +e around test execution so failures don't abort the script.
# Coverage collection (find-and-move-lcov.sh) runs with set -e and must fail loudly.

# --- test:unit:forge (mocha/nyc or mocha/c8) ---
if [ $HAS_FORGE -eq 1 ]; then
    apply_license_fix
    suite_start "forge-unit" "Running test:unit:forge"
    set +e
    "${COVER_TOOL[@]}" npm run test:unit:forge -- --exit --no-bail 2>&1 | mocha_check_passing
    FORGE_EXIT=${PIPESTATUS[0]}
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "forge-unit" "false" "$FORGE_EXIT"
    suite_end "forge-unit" "$FORGE_EXIT"
else
    print_header 4 "NOTICE: No test:unit:forge script found — skipping forge unit tests"
fi

# --- test:unit:frontend (vitest) ---
if [ $HAS_FRONTEND -eq 1 ]; then
    suite_start "frontend-unit" "Running test:unit:frontend (vitest)"

    # Ensure a matching vitest coverage package is available.
    INSTALLED_VITEST=$(node -p "require('./node_modules/vitest/package.json').version" 2>/dev/null || true)
    if [ -n "$INSTALLED_VITEST" ]; then
        if [ ! -d node_modules/@vitest/coverage-v8 ] && \
           [ ! -d node_modules/@vitest/coverage-c8 ] && \
           [ ! -d node_modules/@vitest/coverage-istanbul ]; then
            VITEST_MAJOR=$(echo "$INSTALLED_VITEST" | cut -d. -f1)
            VITEST_MINOR=$(echo "$INSTALLED_VITEST" | cut -d. -f2)
            # Vitest < 0.32.0 used c8; 0.32.0+ switched to v8.
            if [ "$VITEST_MAJOR" -eq 0 ] && [ "$VITEST_MINOR" -lt 32 ]; then
                print_header 4 "Installing @vitest/coverage-c8@$INSTALLED_VITEST..."
                npm install --no-save --legacy-peer-deps "@vitest/coverage-c8@$INSTALLED_VITEST" 2>/dev/null || \
                npm install --no-save --legacy-peer-deps "@vitest/coverage-c8"
            else
                print_header 4 "Installing @vitest/coverage-v8@$INSTALLED_VITEST..."
                npm install --no-save --legacy-peer-deps "@vitest/coverage-v8@$INSTALLED_VITEST" 2>/dev/null || \
                npm install --no-save --legacy-peer-deps "@vitest/coverage-v8"
            fi
        fi
    fi

    # Disable worker threads to avoid WebAssembly out-of-memory in tinypool.
    # The flag name changed across vitest versions: --threads (old) vs --poolOptions.threads.singleThread (new).
    VITEST_SINGLE_THREAD=""
    if has_option --threads npx --registry=$WAYPACK_NPM_REGISTRY vitest; then
        VITEST_SINGLE_THREAD="--threads=false"
    elif has_option --poolOptions npx --registry=$WAYPACK_NPM_REGISTRY vitest; then
        VITEST_SINGLE_THREAD="--poolOptions.threads.singleThread"
    fi

    set +e
    npx --registry=$WAYPACK_NPM_REGISTRY vitest run --config ./config/vitest.config.ts \
        --coverage.enabled --coverage.reporter=lcov --reporter=verbose \
        --coverage.include='frontend/src/**' \
        $VITEST_SINGLE_THREAD
    FRONTEND_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "frontend-unit" "false" "$FRONTEND_EXIT"
    suite_end "frontend-unit" "$FRONTEND_EXIT"
else
    print_header 4 "NOTICE: No test:unit:frontend script found — skipping frontend tests"
fi

# --- test:unit (mocha/nyc or mocha/c8) — only if forge and frontend are absent ---
if [ $HAS_UNIT -eq 1 ]; then
    if [ $HAS_FORGE -eq 1 ] || [ $HAS_FRONTEND -eq 1 ]; then
        print_header 4 "NOTICE: test:unit skipped because test:unit:forge or test:unit:frontend already covers unit tests"
    else
        suite_start "unit" "Running test:unit"
        apply_license_fix
        set +e
        "${COVER_TOOL[@]}" npm run test:unit -- --exit
        UNIT_EXIT=$?
        set -e

        bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
        suite_end "unit" "$UNIT_EXIT"
    fi
else
    print_header 4 "NOTICE: No test:unit script found — skipping unit tests"
fi

# --- test:system (mocha/nyc or mocha/c8) ---
if [ $HAS_SYSTEM -eq 1 ]; then
    suite_start "system" "Running test:system"
    set +e
    "${COVER_TOOL[@]}" npm run test:system -- --exit --no-bail 2>&1 | mocha_check_passing
    SYSTEM_EXIT=${PIPESTATUS[0]}
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "system" "false" "$SYSTEM_EXIT"
    suite_end "system" "$SYSTEM_EXIT"
else
    print_header 4 "NOTICE: No test:system script found — skipping system tests"
fi

# --- test fallback — only when no per-suite scripts exist ---
if [ $HAS_FORGE -eq 0 ] && [ $HAS_FRONTEND -eq 0 ] && [ $HAS_UNIT -eq 0 ] && [ $HAS_SYSTEM -eq 0 ] && [ $HAS_TEST -eq 1 ]; then
    suite_start "unit" "Falling back to c8 on test script"

    print_header 4 "Installing c8 locally for fallback..."
    npm install --no-save c8@7

    set +e
    npx --registry=$WAYPACK_REGISTRY_CURRENT c8 --reporter=lcov -- npm run test
    TEST_EXIT=$?
    set -e

    bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
    suite_end "unit" "$TEST_EXIT"
fi

print_header 1 "FlowFuse coverage run complete"
