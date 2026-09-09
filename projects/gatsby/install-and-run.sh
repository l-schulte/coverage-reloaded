#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# Node 15+ uses --unhandled-rejections=strict, which can abort jest before it
# writes lcov.info on an unhandled rejection. Use warn-only so coverage is kept.
NODE_MAJOR=$(node -p "parseInt(process.versions.node.split('.')[0])")
if [ "$NODE_MAJOR" -ge 15 ]; then
    export NODE_OPTIONS="--unhandled-rejections=warn"
fi

# ── Dependency installation ───────────────────────────────────────────────────

print_header 2 "Installing dependencies"

# Some yarn.lock URLs point to the defunct nexus.stackline.com registry.
# Rewrite them to WayPack so yarn can fetch those packages.
if $IS_YARN_MAIN_PM; then
    print_header 3 "Patching nexus.stackline.com URLs in yarn.lock → WayPack"
    sed -i "s|https://nexus.stackline.com/repository/npm-group/|${WAYPACK_NPM_REGISTRY}|g" yarn.lock

    # Babel fix for March-April 2020 commits: @babel/core ^7.8.x pulls an older
    # @babel/compat-data that lacks a file required by @babel/preset-env@^7.8.0.
    BABEL_CORE_VERSION=$(node -p "require('./package.json').devDependencies['@babel/core'] || ''")
    if [[ "$BABEL_CORE_VERSION" =~ ^\^7\.8\. ]]; then
        echo "NOTICE: Detected @babel/core $BABEL_CORE_VERSION - applying resolution fix for @babel/compat-data"
        node -e "
        const pkg = require('./package.json');
        if (!pkg.resolutions) pkg.resolutions = {};
        pkg.resolutions['@babel/compat-data'] = '^7.8.0';
        pkg.resolutions['@babel/preset-env'] = '^7.8.0';
        require('fs').writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
        "
    fi

    yarn install --frozen-lockfile 2>&1 || yarn install 2>&1
    PM_RUN="yarn run"
elif $IS_NPM_MAIN_PM; then
    npm ci 2>&1 || npm install 2>&1
    PM_RUN="npm run"
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

# ── Install global build deps ─────────────────────────────────────────────────

print_header 2 "Installing global build dependencies"

# cross-env is used by prepare scripts but may not be hoisted; install it globally.
npm install -g cross-env

# ── Bootstrap (lerna prepare) ─────────────────────────────────────────────────

print_header 2 "Bootstrapping packages (lerna prepare, --concurrency 1)"

# Gatsby is a lerna monorepo; each package must build before tests run.
# Use $PM_RUN (not npx) so npm_execpath is correct — npx makes npm 8 rewrite
# "npm run" to "npm exec run", misresolving "run" to runjs (file watcher → hang).
# --concurrency 1: build serially. Gatsby's parallel builds exhaust fork() with
# EAGAIN in the container; history-wide parallelism comes from multiple containers.

$PM_RUN lerna run prepare --concurrency 1 2>&1


# ── Run tests with coverage ────────────────────────────────────────────────────

suite_start "unit" "Running unit tests with jest --coverage"

set +e

# Run the suite with jest --coverage directly (like test:coverage) to skip lint/peril.
# Request the lcov reporter explicitly and use the repo-local jest binary — npx
# can't resolve modules like 'glob' that jest.config.js requires.
# --maxWorkers=1 avoids PID exhaustion and port clashes from concurrent builds.

# Parcel compiles slowly in containers; the default 5s timeout tears down the
# env mid-compile → reporter.panic → process.exit(1) → no coverage.
./node_modules/.bin/jest --verbose --coverage --collectCoverage=true --coverageReporters=lcov --maxWorkers=1 --testTimeout=30000 --forceExit 2>&1

JEST_EXIT=$?

set -e

if [ $JEST_EXIT -ne 0 ]; then
    echo "WARNING: jest tests exited with code $JEST_EXIT — coverage data preserved but may be partial"
fi

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$JEST_EXIT"
suite_end "unit" "$JEST_EXIT"

