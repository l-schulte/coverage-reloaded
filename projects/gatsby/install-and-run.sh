#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/resolve-and-pin.sh

cd /coverage_reloaded/repo

resolve_and_pin "release-assets.githubusercontent.com"

# Gatsby's telemetry repository-id utility (packages/gatsby-telemetry/src/repository-id.ts)
# hashes `git config --local --get remote.origin.url`. The snapshot in
# sample-site-for-experiment.ts was authored using Gatsby's standard SSH clone URL
# (git@github.com:gatsbyjs/gatsby.git). Ensure the local git config matches this URL
# so murmurhash bucket calculations reproduce the expected snapshot without code edits.
git config remote.origin.url "git@github.com:gatsbyjs/gatsby.git"

# Node 15+ uses --unhandled-rejections=strict, which can abort jest before it
# writes lcov.info on an unhandled rejection. Use warn-only so coverage is kept.
NODE_MAJOR=$(node -p "parseInt(process.versions.node.split('.')[0])")
if [ "$NODE_MAJOR" -ge 15 ]; then
    export NODE_OPTIONS="--unhandled-rejections=warn"
fi

# Prevent puppeteer from downloading Chromium over the network during yarn install
export PUPPETEER_SKIP_DOWNLOAD=true

# Cap Gatsby's parallel query worker pool. On high-core host machines (e.g. 256 CPUs),
# unconstrained worker pools exceed LMDB's default maxReaders (126) during bootstrap
# builds (gatsby-admin), throwing MDB_READERS_FULL. Matches Gatsby's CI (CircleCI = 2).
export GATSBY_CPU_COUNT=2

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


# ── Adapt Windows-oriented LMDB test teardown for Linux ───────────────────────
#
# Gatsby's custom jest test environment (jest.environment.ts, added in f990e082,
# 2022-08-11) tears down the LMDB stores opened by a suite. That teardown was
# written for Windows, where LMDB files cannot be moved/deleted while open, so it
# calls `await rootDb.clearAsync()` before `rootDb.close()`. On Linux
# `clearAsync()` never settles, so the environment teardown hangs, jest never
# reaches its coverage reporter, and no lcov.info is written — the run is
# recorded as a hard error. Upstream made the teardown OS-conditional in
# 62687301 (2023-01-26, "Adjust jest environment conditionally for OS"), keeping
# clear+close on Windows and using close-if-operational + file removal elsewhere.
#
# The latent defect only starts to bite once the LMDB-store suites stop being
# skipped (dc82d92e, 2022-10-18, "Remove LOCKED_IN feature flags") — exactly
# where the hard-error window begins — and ends when the upstream fix lands
# (2023-01-26). Backport the upstream OS-conditional teardown whenever the
# checked-out commit still carries the old, Windows-only version (has
# `clearAsync` but not the fix's `isOperational` guard).

if [ -f jest.environment.ts ] && grep -q "clearAsync" jest.environment.ts && ! grep -q "isOperational" jest.environment.ts; then
    print_header 2 "Adapting Windows-oriented LMDB teardown for Linux (jest.environment.ts)"
    cat > jest.environment.ts <<'JEST_ENV_EOF'
const NodeEnvironmentModule = require(`jest-environment-node`)
const NodeEnvironment =
  NodeEnvironmentModule.TestEnvironment || NodeEnvironmentModule
const fsExtra = require(`fs-extra`)

const isWindows = process.platform === `win32`

class CustomEnvironment extends NodeEnvironment {
  constructor(config, context) {
    super(config, context)
  }

  async teardown(): Promise<void> {
    // close open lmdbs after running test suite
    // this prevent dangling open handles that sometimes cause problems
    // particularly in windows tests (failures to move or delete a db file)
    if (this.global.__GATSBY_OPEN_ROOT_LMDBS) {
      if (isWindows) {
        for (const rootDb of this.global.__GATSBY_OPEN_ROOT_LMDBS.values()) {
          await rootDb.clearAsync()
          await rootDb.close()
        }
      } else {
        for (const [
          dbPath,
          rootDb,
        ] of this.global.__GATSBY_OPEN_ROOT_LMDBS.entries()) {
          if (rootDb.isOperational()) {
            await rootDb.close()
          }
          await fsExtra.remove(dbPath)
        }
      }
      this.global.__GATSBY_OPEN_ROOT_LMDBS = undefined
    }
    await super.teardown()
  }
}

module.exports = CustomEnvironment
JEST_ENV_EOF
fi


# ── Pre-populate Contentful image cache for unmocked CDN test ─────────────────
#
# Between commits f5dab4f5ac and 94ddb6bade (Aug–Nov 2021),
# packages/gatsby-source-contentful/src/__tests__/extend-node-type.js tests
# live image fetches from images.ctfassets.net without mocking network requests.
# The CDN's server-side image compression later changed, causing strict base64
# string assertions to fail. extend-node-type.js checks for cached files at
# `.cache/remote_cache/images/<urlSha>.base64` before downloading.
# Pre-populating the cache with the expected base64 strings satisfies the test
# offline without modifying any repository source files.

if [ -f packages/gatsby-source-contentful/src/__tests__/extend-node-type.js ] && \
   grep -q "iVBORw0KGgoAAAANSUhEUgAAABQAAAAECAMAAAC5ge+k" packages/gatsby-source-contentful/src/__tests__/extend-node-type.js; then
    print_header 2 "Pre-populating Contentful image cache for unmocked CDN test"
    CACHE_DIR="/coverage_reloaded/repo/.cache/remote_cache/images"
    mkdir -p "$CACHE_DIR"
    mkdir -p packages/gatsby-source-contentful/.cache/remote_cache/images

    if grep -q "CBQANxNx70py" packages/gatsby-source-contentful/src/__tests__/extend-node-type.js; then
        cat << 'EOF' > "$CACHE_DIR/941ab32dcd3b1f3ff24756e4e6ca2b844dae4a4e.base64"
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAECAMAAAC5ge+kAAAAllBMVEUAAABHl745rOE7tOc7tOcqMDkqMDkqMDkqMDnfzG9Pm7o7tOc7tOcqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDn4wF/eXWDtXGjtXGgqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDnbVmDpWGbtXGjtXGh1tTylAAAAMnRSTlMATd3gVSUjTCDgHRIscF+MeqB8qpqbk4ienYAxr+AeEipyZI9/aW+No4WJeWuuTdzgVnu3oiUAAAAJcEhZcwAACxIAAAsSAdLdfvwAAAAHdElNRQflCBQANxNx70pyAAAAMklEQVQI12NkBII/DCDA+htIsDEy/mBj4WDEBCwiyLwnIpyMjL/ZWASB7PMMMPAZTAIALlUHKTqI1/MAAAAASUVORK5CYII=
EOF
    else
        cat << 'EOF' > "$CACHE_DIR/941ab32dcd3b1f3ff24756e4e6ca2b844dae4a4e.base64"
data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAECAMAAAC5ge+kAAAAllBMVEUAAABHl745rOE7tOc7tOcqMDkqMDkqMDkqMDnfzG9Pm7o7tOc7tOcqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDn4wF/eXWDtXGjtXGgqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDkqMDnbVmDpWGbtXGjtXGh1tTylAAAAMnRSTlMATd3gVSUjTCDgHRIscF+MeqB8qpqbk4ienYAxr+AeEipyZI9/aW+No4WJeWuuTdzgVnu3oiUAAAAJcEhZcwAACxIAAAsSAdLdfvwAAAAHdElNRQflCAUMNjFcK/NJAAAAMklEQVQI12NkBII/DCDA+htIsDEy/mBj4WDEBCwiyLwnIpyMjL/ZWASB7PMMMPAZTAIALlUHKTqI1/MAAAAASUVORK5CYII=
EOF
    fi

    cat << 'EOF' > "$CACHE_DIR/a3390d5844b70e2305562232988bf9edcd8180a4.base64"
data:image/jpg;base64,/9j/4AAQSkZJRgABAQIAHAAcAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAEABQDASIAAhEBAxEB/8QAFwABAAMAAAAAAAAAAAAAAAAAAAIDBv/EACQQAAIBAgQHAQAAAAAAAAAAAAECAAMRBBITJAUUFSFBUWHB/8QAFQEBAQAAAAAAAAAAAAAAAAAAAgH/xAAXEQEBAQEAAAAAAAAAAAAAAAABAAIx/9oADAMBAAIRAxEAPwDV4NObWqM70dOoVvROUt9Psy7pYud5jO/jWiJM8lsDSFB+Do+Xe4xQosAtW35ERFC//9k=
EOF

    cp -f "$CACHE_DIR"/*.base64 packages/gatsby-source-contentful/.cache/remote_cache/images/ 2>/dev/null || true
fi


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

