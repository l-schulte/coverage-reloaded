#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

# Large workspaces (notably @opencrvs/client) OOM at ~8GB while generating the
# c8 coverage report after all tests pass. The container has no memory cap and
# lerna runs tests serially (--concurrency=1), so a 16GB heap is safe.
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=16384"

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
    yarn install --frozen-lockfile --ignore-scripts
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
# The install runs with --ignore-scripts (some dependency lifecycle scripts need
# network or misbehave in the sandbox), which also skips node-gyp builds. The
# notification SMS suites load the native `iconv` addon at require-time and fail
# to run without its compiled binding, silently dropping notification coverage.
# Rebuild only that addon, using the `n`-installed Node headers so node-gyp does
# not need to download them.
ICONV_DIR=$(node -e "
  try {
    var p = require.resolve('iconv/package.json', { paths: [process.cwd()] });
    console.log(require('path').dirname(p));
  } catch (e) { process.stdout.write(''); }
")
if [ -n "$ICONV_DIR" ] && [ -f "$ICONV_DIR/binding.gyp" ] && [ ! -f "$ICONV_DIR/build/Release/iconv.node" ]; then
    # Use the Node installation's own headers so node-gyp does not download them.
    NODE_HEADERS_DIR=$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")
    # Node 12/14 ship npm 6 / node-gyp 5, which only supports Python 2.7 or
    # <=3.8; the image symlinks `python` to 3.10, so pin python2 for those.
    NODE_MAJOR=$(node -p "process.versions.node.split('.')[0]")
    if [ "$NODE_MAJOR" -le 14 ] && [ -x /usr/bin/python2.7 ]; then
        REBUILD_PYTHON=/usr/bin/python2.7
    else
        REBUILD_PYTHON=$(command -v python)
    fi
    print_header 2 "Rebuilding native addon: iconv (node $NODE_MAJOR, python $REBUILD_PYTHON)"
    ( cd "$ICONV_DIR" && npm_config_nodedir="$NODE_HEADERS_DIR" npm_config_python="$REBUILD_PYTHON" npm rebuild )
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

# ── Start Docker daemon (testcontainers needs Docker for ES/Postgres) ───────
print_header 2 "Starting Docker daemon for testcontainers"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["http://docker-cache:5000"],
  "insecure-registries": ["http://docker-cache:5000"],
  "dns": ["1.1.1.1", "8.8.8.8"]
}
EOF
dockerd > /var/log/dockerd.log 2>&1 &
DOCKERD_PID=$!
for i in $(seq 1 30); do
    if docker ps > /dev/null 2>&1; then
        print_header 4 "Docker daemon ready (attempt $i)"
        break
    fi
    sleep 1
done
if ! docker ps > /dev/null 2>&1; then
    print_header 2 "DOCKER DAEMON FAILED" "Could not start Docker daemon within 30s. Check /var/log/dockerd.log for details."
    cat /var/log/dockerd.log
    exit 1
fi

# ── Build ────────────────────────────────────────────────────────────────────
# Tests import workspace packages via their dist/ entry points. Build all
# workspace packages with the repo's own build script.
if [ "$HAS_ROOT_BUILD" = "true" ]; then
    print_header 2 "Building workspace packages"
    # Patch build script to run lerna with --concurrency=1, preventing race
    # conditions where @opencrvs/api-docs starts before @opencrvs/commons
    # finishes building.
    node -e "
      var p = require('./package.json');
      if (p.scripts && p.scripts.build && p.scripts.build.indexOf('lerna run build') >= 0) {
        p.scripts.build = p.scripts.build.replace(/lerna run build\b(?!.*--concurrency)/, 'lerna run build --concurrency=1');
        require('fs').writeFileSync('package.json', JSON.stringify(p, null, 2) + '\n');
        console.log('Patched build script to add --concurrency=1');
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
