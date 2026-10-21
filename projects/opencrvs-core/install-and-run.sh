#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

# Large workspaces (notably @opencrvs/client) OOM at ~8GB while generating the
# c8 coverage report after all tests pass. The container has no memory cap and
# lerna runs tests serially (--concurrency=1), so a 16GB heap is safe.
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=16384"
# Prevent Yarn v1 from aborting on patch-level Node engine constraints (e.g. 18.19.x vs 18.20.8)
export YARN_IGNORE_ENGINES=true
# Route MongoMemoryServer binary downloads through Waypack caching proxy (prevents transient fastdl.mongodb.org 502/timeouts)
export MONGOMS_DOWNLOAD_URL="http://waypack:3000/request/https://fastdl.mongodb.org"

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

ROOT_TEST=$(node -p "((require('./package.json').scripts||{}).test) || ''" || true)
if [ -z "$ROOT_TEST" ]; then
    not_applicable "No root test script at this commit"
fi
print_header 4 "Root test script: $ROOT_TEST"

HAS_ROOT_BUILD=$(node -p "!!((require('./package.json').scripts||{}).build)")
print_header 4 "Root build script present: $HAS_ROOT_BUILD"

# ── Patch package.json test scripts to collect coverage ──────────────────────
# Run BEFORE install: scripts are patched in place (dependency changes are
# deliberately avoided so the frozen install is not invalidated). Any required
# vitest coverage provider is recorded in .coverage-providers.json and installed
# out-of-tree after the install.
print_header 2 "Patching package.json test scripts to collect coverage"
node /coverage_reloaded/patch-coverage.js

# ── Install ──────────────────────────────────────────────────────────────────
print_header 2 "Installing dependencies"

if [ "$IS_PNPM_MAIN_PM" = "true" ]; then
    pnpm install
    PM_RUN="pnpm run"
    PM_TEST="pnpm test"
elif [ "$IS_YARN_MAIN_PM" = "true" ]; then
    # --frozen-lockfile matches the project's CI and guarantees the workspace
    # hoisting is identical to it. Without it, any package.json change forces a
    # full re-resolution that rewrites yarn.lock and can re-hoist dependencies
    # (e.g. a duplicate `vite` that breaks packages/login's tsc).
    yarn install --frozen-lockfile --ignore-scripts --ignore-engines
    # Apply patches manually — skip failures when version mismatches occur
    # (e.g. --no-lockfile resolves newer versions than the patch targets).
    # Patches that match still apply; mismatches are warnings, not errors.
    npx patch-package --error-on-fail false 2>&1
    PM_RUN="yarn run"
    PM_TEST="yarn test"
elif [ "$IS_NPM_MAIN_PM" = "true" ]; then
    npm install
    PM_RUN="npm run"
    PM_TEST="npm test"
else
    print_header 2 "Unsupported package manager: $package_manager"
    exit 1
fi

# ── Rebuild native addons skipped by --ignore-scripts ────────────────────────
# In commits prior to 2022-09-28, packages/notification depends on native addon
# iconv. Since --ignore-scripts skipped its node-gyp build, rebuild it using
# local Node headers and Python 2.7.
if grep -q '"iconv"' packages/notification/package.json 2>/dev/null; then
    print_header 2 "Rebuilding native addon: iconv"
    NODE_HEADERS_DIR=$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")
    npm_config_nodedir="$NODE_HEADERS_DIR" npm_config_python=/usr/bin/python2.7 npm rebuild iconv
fi

# ── Install vitest >= 1 coverage provider out-of-tree ────────────────────────
# vitest 2.x refuses to collect coverage without @vitest/coverage-v8. Adding it
# to a workspace package.json would force a non-frozen yarn install (rewrites
# yarn.lock, re-hoists the tree). Instead install it into an isolated prefix
# inside node_modules and symlink it into the consuming package, leaving the
# frozen workspace tree untouched.
PROVIDER_FILE="$REPOPATH/.coverage-providers.json"
if [ -f "$PROVIDER_FILE" ]; then
    PROV_ROOT="$REPOPATH/node_modules/.coverage-providers"
    declare -A PROVIDER_PREFIX
    while IFS=$'\t' read -r PROV_NAME PROV_VERSION PROV_DIR; do
        [ -n "$PROV_NAME" ] || continue
        PROV_SPEC="$PROV_NAME@$PROV_VERSION"
        PROV_SAFE=$(printf '%s' "$PROV_SPEC" | tr '/@' '__')
        PROV_PREFIX="$PROV_ROOT/$PROV_SAFE"
        if [ -z "${PROVIDER_PREFIX[$PROV_SPEC]:-}" ]; then
            print_header 2 "Installing coverage provider $PROV_SPEC (isolated)"
            mkdir -p "$PROV_PREFIX"
            if [ ! -f "$PROV_PREFIX/package.json" ]; then
                ( cd "$PROV_PREFIX" && npm init -y > /dev/null )
            fi
            npm --prefix "$PROV_PREFIX" install --no-save --ignore-scripts \
                --legacy-peer-deps --no-audit --no-fund \
                --registry="$WAYPACK_NPM_REGISTRY" "$PROV_SPEC"
            PROVIDER_PREFIX[$PROV_SPEC]="$PROV_PREFIX"
        fi
        PROV_LINKDIR="$REPOPATH/$PROV_DIR/node_modules"
        PROV_LINK="$PROV_LINKDIR/$PROV_NAME"
        mkdir -p "$PROV_LINKDIR" "$(dirname "$PROV_LINK")"
        ln -sfn "${PROVIDER_PREFIX[$PROV_SPEC]}/node_modules/$PROV_NAME" "$PROV_LINK"
    done < <(node -e '
        var fs = require("fs");
        var j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        (j.providers || []).forEach(function (p) {
            console.log([p.name, p.version, p.dir].join("\t"));
        });
    ' "$PROVIDER_FILE")
fi

# ── Start Docker daemon (testcontainers needs Docker for ES/Postgres/Redis) ─
if grep -rq "testcontainers" packages/*/package.json 2>/dev/null; then
    source /coverage_reloaded/start-dind.sh
    export DOCKER_HOST="unix:///var/run/docker.sock"
fi

# ── Build ────────────────────────────────────────────────────────────────────
# Tests import workspace packages via their dist/ entry points. Build all
# workspace packages with the repo's own build script.
if [ "$HAS_ROOT_BUILD" = "true" ]; then
    print_header 2 "Building workspace packages"
    # Neutralize @opencrvs/integration build: standalone k6 load tests with no
    # test suite and no dependents; prevents ambient TS2300 collisions in 2021.
    if [ -f packages/integration/package.json ]; then
        node -e "
          var ip = 'packages/integration/package.json';
          var ij = JSON.parse(require('fs').readFileSync(ip));
          if (ij.scripts && ij.scripts.build) {
            ij.scripts.build = 'echo skipping integration build';
            require('fs').writeFileSync(ip, JSON.stringify(ij, null, 2) + '\n');
            console.log('Neutralized packages/integration build script');
          }
        "
    fi
    # Neutralize @opencrvs/api-docs build: standalone documentation generator
    # with no test suite and no dependents.
    if [ -f packages/api-docs/package.json ]; then
        node -e "
          var ap = 'packages/api-docs/package.json';
          var aj = JSON.parse(require('fs').readFileSync(ap));
          if (aj.scripts && aj.scripts.build) {
            aj.scripts.build = 'echo skipping api-docs build';
            require('fs').writeFileSync(ap, JSON.stringify(aj, null, 2) + '\n');
            console.log('Neutralized packages/api-docs build script');
          }
        "
    fi
    # Neutralize build-storybook in packages/components
    if [ -f packages/components/package.json ]; then
        node -e "
          var cp = 'packages/components/package.json';
          var cj = JSON.parse(require('fs').readFileSync(cp));
          if (cj.scripts && cj.scripts['build-storybook']) {
            cj.scripts['build-storybook'] = 'echo skipping build-storybook';
            require('fs').writeFileSync(cp, JSON.stringify(cj, null, 2) + '\n');
            console.log('Neutralized packages/components build-storybook script');
          }
        "
    fi
    # Neutralize builds for non-library targets:
    # - production SPA web bundlers in client and login (Vite/Craco)
    # - standalone metrics and auth services (prevents tsc compiling tests to build/dist where missing assets or db mocks fail under Jest)
    for pkg in client login metrics auth; do
        if [ -f "packages/$pkg/package.json" ]; then
            node -e "
              var pp = 'packages/$pkg/package.json';
              var pj = JSON.parse(require('fs').readFileSync(pp));
              if (pj.scripts && pj.scripts.build) {
                pj.scripts.build = 'echo skipping $pkg build';
                require('fs').writeFileSync(pp, JSON.stringify(pj, null, 2) + '\n');
                console.log('Neutralized packages/$pkg build script');
              }
            "
        fi
    done
    # Patch build script to run lerna with --concurrency=1, preventing race
    # conditions where @opencrvs/api-docs starts before @opencrvs/commons
    # finishes building. Also ignore non-library targets (@opencrvs/integration,
    # @opencrvs/client, @opencrvs/login, @opencrvs/metrics, @opencrvs/auth) and strip build-storybook.
    node -e "
      var p = require('./package.json');
      if (p.scripts && p.scripts.build) {
        p.scripts.build = p.scripts.build.replace(/&&\s*lerna\s+run\s+build-storybook\b/g, '');
        if (p.scripts.build.indexOf('lerna run build') >= 0) {
          p.scripts.build = p.scripts.build.replace(/lerna run build\b(?!.*--concurrency)/, 'lerna run build --concurrency=1');
          ['@opencrvs/integration', '@opencrvs/client', '@opencrvs/login', '@opencrvs/metrics', '@opencrvs/auth'].forEach(function(pkg) {
            if (p.scripts.build.indexOf('--ignore ' + pkg) === -1) {
              p.scripts.build = p.scripts.build.replace(/lerna run build\b/, 'lerna run build --ignore ' + pkg);
            }
          });
        }
        require('fs').writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
        console.log('Patched build script: ' + p.scripts.build);
      }
    "
    set +e
    $PM_RUN build
    BUILD_EXIT=$?
    set -e
    if [ "$BUILD_EXIT" -ne 0 ]; then
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

print_header 1 "opencrvs-core coverage run complete"
