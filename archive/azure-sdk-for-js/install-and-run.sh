#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

# Rush-era repos may not have a root package.json (Rush uses rush.json).
# Only bail if neither package.json nor rush.json exist.
if [ ! -f package.json ] && [ ! -f rush.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json or rush.json at this commit"
    exit 2
fi

print_header 2 "Detecting project infrastructure"

HAS_RUSH=0; [ -f rush.json ] && HAS_RUSH=1
HAS_TURBO=0; [ -f turbo.json ] && HAS_TURBO=1

print_header 4 "HAS_RUSH=$HAS_RUSH  HAS_TURBO=$HAS_TURBO"

# ═══════════════════════════════════════════════════════════════
# ERA 1: Rush monorepo (rush.json present)
# ═══════════════════════════════════════════════════════════════
if [ $HAS_RUSH -eq 1 ]; then
    print_header 2 "Rush monorepo detected"

    RUSH_VERSION=$(node -p "require('./rush.json').rushVersion || '5.17.2'")
    print_header 4 "Rush version: $RUSH_VERSION"

    # Install deps via Rush (handles its own pnpm internally)
    print_header 3 "Running rush update"
    set +e
    npx --registry="$WAYPACK_NPM_REGISTRY" "@microsoft/rush@$RUSH_VERSION" update
    RUSH_UPDATE_EXIT=$?
    set -e
    if [ $RUSH_UPDATE_EXIT -ne 0 ]; then
        print_header 3 "rush update failed — trying rush install"
        set +e
        npx --registry="$WAYPACK_NPM_REGISTRY" "@microsoft/rush@$RUSH_VERSION" install
        RUSH_INSTALL_EXIT=$?
        set -e
        if [ $RUSH_INSTALL_EXIT -ne 0 ]; then
            print_header 2 "Rush install failed"
            exit $RUSH_INSTALL_EXIT
        fi
    fi

    # Build
    print_header 3 "Running rush build"
    set +e
    npx --registry="$WAYPACK_NPM_REGISTRY" "@microsoft/rush@$RUSH_VERSION" build
    RUSH_BUILD_EXIT=$?
    set -e
    print_header 4 "rush build exit code: $RUSH_BUILD_EXIT"

    # Wrap rush test with c8
    print_header 3 "Running rush test wrapped with c8"
    set +e
    npx --registry="$WAYPACK_NPM_REGISTRY" c8 --reporter=lcov -- npx --registry="$WAYPACK_NPM_REGISTRY" "@microsoft/rush@$RUSH_VERSION" test
    RUSH_TEST_EXIT=$?
    set -e
    print_header 4 "rush test exit code: $RUSH_TEST_EXIT"

    print_header 2 "Collecting Rush coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "rush" "true" "$RUSH_TEST_EXIT"

    print_header 1 "Azure SDK for JS (Rush era) done"
    exit 0
fi

# ── Non-Rush: need package.json for install ──────────────────
if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit"
    exit 2
fi

print_header 2 "Installing dependencies"

if $IS_PNPM_MAIN_PM; then
    print_header 4 "Package manager: pnpm"
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install --no-frozen-lockfile
    PM_RUN="pnpm run"
elif $IS_NPM_MAIN_PM; then
    print_header 4 "Package manager: npm"
    npm install
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# ERA 2: Turborepo + pnpm (turbo.json present)
# ═══════════════════════════════════════════════════════════════
if [ $HAS_TURBO -eq 1 ]; then
    print_header 2 "Turborepo detected"

    # Build first (turbo pipeline requires build before test)
    print_header 3 "Running turbo build"
    set +e
    $PM_RUN build
    TURBO_BUILD_EXIT=$?
    set -e
    print_header 4 "turbo build exit code: $TURBO_BUILD_EXIT"

    # Patch vitest shared config to add lcov reporter
    if [ -f vitest.shared.config.ts ]; then
        print_header 4 "Patching vitest.shared.config.ts to add lcov reporter"
        sed -i 's/reporter: \["text", "json", "html"\]/reporter: ["text", "json", "html", "lcov"]/' vitest.shared.config.ts
    fi

    print_header 3 "Running turbo run test:node"
    set +e
    npx --registry="$WAYPACK_NPM_REGISTRY" turbo run test:node
    TURBO_TEST_EXIT=$?
    set -e

    print_header 2 "Collecting Turborepo coverage reports"
    bash /coverage_reloaded/find-and-move-lcov.sh "turbo" "true" "$TURBO_TEST_EXIT"

    print_header 1 "Azure SDK for JS (Turborepo era) done"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════
# ERA 3: Standalone (shouldn't happen in this project)
# ═══════════════════════════════════════════════════════════════
print_header 2 "NOT APPLICABLE" "No Rush or Turborepo detected at this commit"
exit 2
