#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Coverage collection script
# Era is detected by reading the test script from root package.json
#
# Known test script versions and their eras:
#
# ERA: legacy (v1-v4) — no c8, wrapped with c8 by this script
#   v1: npm run testCompile && ts-node ./test-scripts/test.ts
#   v2: npm run compile && node ./test-scripts/test.js
#   v3: npm run testCompile && ts-node ./scripts/test/test.ts
#   v4: npm run testCompile && ts-node ./scripts/test/test.ts && npm run report
#
# ERA: root-c8 (v5-v6) — c8 configured at repo root via .c8rc.json
#   v5: npm run testCompile && c8 ts-node ./scripts/test/test.ts
#   v6: npm run testCompile && c8 esrun ./scripts/test/test.ts
#
# ERA: workspace (v7-v8) — c8 configured per workspace package via .c8rc.json
#   v7: npm run test -w packages/
#   v8: npm run test -w packages/ --if-present
#
# ─────────────────────────────────────────────

cd /coverage_reloaded/repo

# ── VSCode / display setup ───────────────────
Xvfb :99 -screen 0 1024x768x16 &
export DISPLAY=:99
export CHROMIUM_FLAGS="--no-sandbox --disable-setuid-sandbox"

# Problem: older versions load the most recent vscode from github without pinning to a specific version, which causes breakages. 
# Solution: if package.json references vscode in the engines field, extract the version and cache the source code for that version.
# Problem: older versions still try to load the most recent vscode even after caching, causing breakages.
# Solution: set the name of the extracted version to what the build script expects (vscode-$LATEST_VSCODE_VERSION) to ensure it is loaded correctly.
if [ -f package.json ] && grep -q '"vscode"' package.json; then
    VSCODE_VERSION=$(node -e "console.log(require('./package.json').engines.vscode)")
    VSCODE_VERSION=${VSCODE_VERSION#^}
    LATEST_VSCODE_VERSION=$(curl -s https://update.code.visualstudio.com/api/releases/stable | jq -r '.[0]')
    echo "Detected VSCode version: $VSCODE_VERSION; latest stable is $LATEST_VSCODE_VERSION"
    wget http://waypack:3000/request/https://github.com/microsoft/vscode/archive/refs/tags/$VSCODE_VERSION.tar.gz -O /tmp/vscode-$VSCODE_VERSION.tar.gz
    mkdir -p .vscode-test
    tar -xzf /tmp/vscode-$VSCODE_VERSION.tar.gz -C .vscode-test
    cp -r .vscode-test/vscode-$VSCODE_VERSION .vscode-test/vscode-$LATEST_VSCODE_VERSION
    echo "VSCode source code extracted to .vscode-test/vscode-$LATEST_VSCODE_VERSION"
else
    echo "No VSCode version detected in package.json, skipping VSCode cache setup"
fi

# NODE_OPTIONS --max-old-space-size
export NODE_OPTIONS="--max-old-space-size=8192"


# ── Fix potential downloader issues ──

# ─────────────────────────────────────────────
# Helper: check if a commit is an ancestor of another (used for conditional logic based on git history)
# Usage: is_ancestor <ancestor_commit> <descendant_commit>
# ─────────────────────────────────────────────
is_ancestor() {
    local commit_a=$1
    local commit_b=$2
    git merge-base --is-ancestor "$commit_a" "$commit_b"
}

# Problem: pre August 2020, the build script "generateServiceClient.ts" used to clone the most current version of https://github.com/aws/aws-sdk-js.git
#          without selecting a specific commit. This caused builds to break.
# Solution: for commits before the fix (b5e1e4922f5de3f536b603f1eef54ca7ee8b67cf), overwrite the build script with the fixed version from that commit.
if is_ancestor "$revision" "b5e1e4922f5de3f536b603f1eef54ca7ee8b67cf"; then
    echo "Fixing build script "generateServiceClient.ts" for pre-b5e1e4922f5de3f536b603f1eef54ca7ee8b67cf commits..."
    git show b5e1e4922f5de3f536b603f1eef54ca7ee8b67cf:./build-scripts/generateServiceClient.ts > ./build-scripts/generateServiceClient.ts
fi


# ── Install dependencies ─────────────────────
npm install --no-fund

# ── Read test script from root package.json ──
ROOT_TEST_SCRIPT=$(node -e "console.log(require('./package.json').scripts.test || '')")

echo "Detected test script: $ROOT_TEST_SCRIPT"

# ── Era detection ────────────────────────────
if echo "$ROOT_TEST_SCRIPT" | grep -q "\-w packages/"; then
    ERA="workspace"
elif echo "$ROOT_TEST_SCRIPT" | grep -qE "\bc8\b"; then
    ERA="root-c8"
else
    ERA="legacy"
fi

echo "Detected era: $ERA"


# ─────────────────────────────────────────────
# Helper: expand workspace globs from root package.json
# Returns a list of directories that have a package.json
# ─────────────────────────────────────────────
get_workspace_dirs() {
    node -e "
        const fs = require('fs');
        const path = require('path');
        const glob = require('glob');

        const pkg = require('./package.json');
        const patterns = pkg.workspaces || [];

        // workspaces can be an object with a 'packages' key (yarn) or a plain array
        const patternList = Array.isArray(patterns) ? patterns : (patterns.packages || []);

        const dirs = [];
        for (const pattern of patternList) {
            const matches = glob.sync(pattern, { onlyDirectories: true });
            for (const match of matches) {
                const pkgJson = path.join(match, 'package.json');
                if (fs.existsSync(pkgJson)) {
                    dirs.push(match);
                }
            }
        }
        console.log(dirs.join('\n'));
    "
}

# ─────────────────────────────────────────────
# Helper: check if a package has a test script
# ─────────────────────────────────────────────
has_test_script() {
    local pkg_dir="$1"
    node -e "
        const pkg = require('./${pkg_dir}/package.json');
        process.exit((pkg.scripts && pkg.scripts.test) ? 0 : 1);
    " 2>/dev/null
}

# ─────────────────────────────────────────────
# Helper: check if a package has a .c8rc.json
# ─────────────────────────────────────────────
has_c8rc() {
    local pkg_dir="$1"
    test -f "${pkg_dir}/.c8rc.json"
}

# ─────────────────────────────────────────────
# Whitelist: packages with test scripts but no .c8rc.json
# These are intentionally excluded from coverage collection
# (e.g. tooling/infrastructure packages not part of the product)
# Add entries as directory paths relative to repo root.
# ─────────────────────────────────────────────
COVERAGE_EXCLUDED_PACKAGES=(
    "plugins/eslint-plugin-aws-toolkits"
)

is_whitelisted() {
    local pkg_dir="$1"
    for entry in "${COVERAGE_EXCLUDED_PACKAGES[@]}"; do
        if [ "$pkg_dir" = "$entry" ]; then
            return 0
        fi
    done
    return 1
}

# ─────────────────────────────────────────────
# ERA: workspace (v7/v8) — validate before running
# ─────────────────────────────────────────────
if [ "$ERA" = "workspace" ]; then

    echo "Validating workspace packages..."

    WORKSPACE_DIRS=$(get_workspace_dirs)

    if [ -z "$WORKSPACE_DIRS" ]; then
        echo "ERROR: No workspace packages found" >&2
        exit 1
    fi

    VALIDATION_FAILED=0

    while IFS= read -r pkg_dir; do
        [ -z "$pkg_dir" ] && continue

        PKG_HAS_TEST=0
        PKG_HAS_C8RC=0

        has_test_script "$pkg_dir" && PKG_HAS_TEST=1
        has_c8rc "$pkg_dir" && PKG_HAS_C8RC=1

        if [ "$PKG_HAS_TEST" -eq 1 ] && [ "$PKG_HAS_C8RC" -eq 0 ]; then
            if is_whitelisted "$pkg_dir"; then
                PKG_TEST_SCRIPT=$(node -e "console.log(require('./${pkg_dir}/package.json').scripts.test || '')")
                echo "WARNING: Package '${pkg_dir}' is whitelisted — has test script but no .c8rc.json, skipping coverage collection" >&2
                echo "         test script: ${PKG_TEST_SCRIPT}" >&2
            else
                PKG_TEST_SCRIPT=$(node -e "console.log(require('./${pkg_dir}/package.json').scripts.test || '')")
                echo "ERROR: Package '${pkg_dir}' has a test script but no .c8rc.json — cannot determine coverage output format/location" >&2
                echo "       test script: ${PKG_TEST_SCRIPT}" >&2
                VALIDATION_FAILED=1
            fi
        elif [ "$PKG_HAS_TEST" -eq 0 ] && [ "$PKG_HAS_C8RC" -eq 1 ]; then
            echo "WARNING: Package '${pkg_dir}' has a .c8rc.json but no test script — skipping" >&2
        elif [ "$PKG_HAS_TEST" -eq 1 ] && [ "$PKG_HAS_C8RC" -eq 1 ]; then
            echo "OK: Package '${pkg_dir}' has both test script and .c8rc.json"
        else
            echo "INFO: Package '${pkg_dir}' has neither test script nor .c8rc.json — skipping"
        fi

    done <<< "$WORKSPACE_DIRS"

    if [ "$VALIDATION_FAILED" -eq 1 ]; then
        echo "ERROR: Workspace validation failed — aborting coverage collection" >&2
        exit 1
    fi

fi


# ─────────────────────────────────────────────
# Run tests
# legacy: wrap with c8 since project did not configure it
# all other eras: npm run test delegates to the configured tool
# ─────────────────────────────────────────────
set +e

if [ "$ERA" = "legacy" ]; then
    echo "Running legacy ts-node tests with c8 wrapper..."
    npm run postinstall
    npm run compile
    npx --registry="$WAYPACK_NPM_REGISTRY" c8 \
        --all \
        --reporter=lcov \
        --report-dir="$COVERAGE_REPORT_PATH" \
        npm run test
else
    echo "Running tests..."
    npm run test
fi

TEST_EXIT_CODE=$?
set -e

if [ "$TEST_EXIT_CODE" -eq 1 ]; then
    echo "WARNING: Tests exited with code $TEST_EXIT_CODE. Coverage may still be collected. Please check test logs for details." >&2
elif [ "$TEST_EXIT_CODE" -gt 1 ]; then
    echo "ERROR: Test runner exited with code $TEST_EXIT_CODE, indicating a possible setup issue" >&2
    exit "$TEST_EXIT_CODE"
fi

# ── Collect coverage files ───────────────────
echo "Collecting coverage files..."
bash ../find-and-move-lcov.sh