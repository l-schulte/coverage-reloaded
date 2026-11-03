#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/na-if-focus-marker.sh

# Large workspaces (notably @opencrvs/client) OOM at ~8GB while generating the
# c8 coverage report after all tests pass. The container has no memory cap and
# lerna runs tests serially (--concurrency=1), so a 16GB heap is safe.
export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=16384"
# Prevent Yarn v1 from aborting on patch-level Node engine constraints (e.g. 18.19.x vs 18.20.8)
export YARN_IGNORE_ENGINES=true
# Prevent Lerna v8 / Nx from bailing when a package test fails (violates Bail Rule by truncating monorepo runs)
export NX_BAIL=false
# Point MongoMemoryServer directly to pre-installed mongod binary, avoiding all runtime downloads
if [ -x /usr/local/bin/mongod ]; then
    export MONGOMS_SYSTEM_BINARY="/usr/local/bin/mongod"
else
    # Fallback to Waypack proxy mirror if image lacks pre-installed binary
    export MONGOMS_DOWNLOAD_MIRROR="http://waypack:3000/request/https://fastdl.mongodb.org"
fi

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

# ── Generate the local JWT key pair (.secrets) ───────────────────────────────
# Backend services read their signing keys at import time: packages/*/src/
# constants.ts default CERT_{PRIVATE,PUBLIC}_KEY_PATH to
# ../../.secrets/{private,public}-key.pem. .secrets/ is gitignored, so a fresh
# checkout never has it and the key-loading test suites (notably two gateway
# suites) die with ENOENT before running a single test. The repository's own
# dev:secrets:gen script (openssl genrsa + rsa -pubout) is the canonical
# generator used by setup.sh. Era-aware and inert: only runs when the commit
# defines the script and the key pair is still missing.
if [ ! -f .secrets/private-key.pem ] && node -e "const s=(require('./package.json').scripts||{});process.exit(s['dev:secrets:gen']?0:1)" 2>/dev/null; then
    print_header 2 "Generating local test key pair (.secrets)"
    $PM_RUN dev:secrets:gen
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
                --registry="$WAYPACK_NPM_REGISTRY" "$PROV_SPEC" "vitest@$PROV_VERSION"
            PROVIDER_PREFIX[$PROV_SPEC]="$PROV_PREFIX"
        fi
        PROV_LINKDIR="$REPOPATH/$PROV_DIR/node_modules"
        PROV_LINK="$PROV_LINKDIR/$PROV_NAME"
        mkdir -p "$PROV_LINKDIR" "$(dirname "$PROV_LINK")"
        rm -rf "$PROV_LINK"
        ln -sfn "${PROVIDER_PREFIX[$PROV_SPEC]}/node_modules/$PROV_NAME" "$PROV_LINK"
    done < <(node -e '
        var fs = require("fs");
        var j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        (j.providers || []).forEach(function (p) {
            console.log([p.name, p.version, p.dir].join("\t"));
        });
    ' "$PROVIDER_FILE")
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
    # ── Build accommodations (validated by container probes, 2026-10-31) ──
    #
    # Fix B — skipLibCheck for the BUILD only: several eras' builds fail inside
    # node_modules *.d.ts files (apollo-link's ExecutionResult interface merge
    # conflict with graphql; apollo-server-hapi importing the renamed 'hapi'
    # package). Those are declaration-CHECK errors — emit is unaffected — but
    # `tsc` exits non-zero and aborts the build before dist/ exists. skipLibCheck
    # suppresses exactly this class; it changes no test or coverage semantics.
    print_header 3 "Build accommodation: skipLibCheck for workspace tsconfigs"
    for _tc in tsconfig*.json packages/*/tsconfig*.json; do
        [ -f "$_tc" ] || continue
        grep -q '"skipLibCheck"' "$_tc" && continue
        sed -i 's/"compilerOptions"[[:space:]]*:[[:space:]]*{/"compilerOptions": {\n    "skipLibCheck": true,/' "$_tc"
        echo "[---] patched $_tc (skipLibCheck: true)"
    done

    # Fix A — declaration pass for workspace packages that emit no type
    # declarations: e.g. @opencrvs/commons at early-2022 commits builds plain
    # `tsc` (no `declaration`) and exposes only `main`, so dependents compiling
    # under `noImplicitAny` fail with TS7016 ("Could not find a declaration file
    # for module '@opencrvs/...'") and the build aborts. The dev's tests run
    # against source and never needed the build; only our dist-based flow trips.
    # A declaration-only emit restores the missing .d.ts without touching runtime
    # code. Inert where not needed: packages that already declare `types` or emit
    # declarations (`tsc -d` / `declaration: true` eras) and neutralized builds
    # are skipped.
    print_header 3 "Build accommodation: declaration pass for untyped workspace packages"
    _TSC_ROOT="$(pwd)/node_modules/.bin/tsc"
    for _pj in packages/*/package.json; do
        _dir=$(dirname "$_pj")
        _types=$(node -p "const p=require('./$_pj'); String(!p.types && !p.typings)" 2>/dev/null)
        [ "$_types" = "true" ] || continue
        _build=$(node -p "((require('./$_pj').scripts||{}).build||'')" 2>/dev/null)
        case "$_build" in *tsc*) ;; *) continue ;; esac
        case "$_build" in *skipping*) continue ;; esac
        case "$_build" in *--declaration*|*"tsc -d"*|*" -d "*) continue ;; esac
        _proj=$(echo "$_build" | grep -oE '[ ;]((-p)|(--project))(=| +)[^ |&;]+' | tail -1 | sed 's/.*--project[= ]*//; s/.*-p[= ]*//')
        if [ -z "$_proj" ]; then
            [ -f "$_dir/tsconfig.json" ] && _proj="tsconfig.json"
        fi
        [ -n "$_proj" ] && [ -f "$_dir/$_proj" ] || continue
        grep -q '"declaration"[[:space:]]*:[[:space:]]*true' "$_dir/$_proj" && continue
        _tsc="$(pwd)/$_dir/node_modules/.bin/tsc"
        [ -x "$_tsc" ] || _tsc="$_TSC_ROOT"
        [ -x "$_tsc" ] || { echo "[WARN] no tsc binary for $_dir — skipping declaration pass"; continue; }
        echo "[---] $_dir: emitting declarations (project: $_proj)"
        set +e
        (cd "$_dir" && "$_tsc" --declaration --emitDeclarationOnly --project "$_proj")
        _decl_exit=$?
        set -e
        if [ "$_decl_exit" -ne 0 ]; then
            echo "[WARN] declaration pass for $_dir exited with code $_decl_exit (a fatal type error will surface in the build below)"
        fi
    done

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

# ── Start Docker daemon (testcontainers needs Docker for ES/Postgres/Redis) ─
# Started *after* the build so the daemon is fresh when the suites run: the
# testcontainers packages resolve their client strategy at container-creation
# time, and a daemon that has been idle/degraded through a long build produces
# "No Docker client strategy found" as an ordinary test failure. Readiness is
# asserted here (start-dind exits non-zero if the daemon never answers), so a
# failure is a hard error rather than a silent test failure.
if grep -rq "testcontainers" packages/*/package.json 2>/dev/null; then
    source /coverage_reloaded/start-dind.sh
    export DOCKER_HOST="unix:///var/run/docker.sock"
fi

# ── Focus marker (.only) guard ──────────────────────────────────────────────
# A committed `.only` makes the runner execute only the marked subset of that
# file, yet the run still finishes and writes a structurally valid lcov — a
# silent partial. Both runners used in this repository are per-file (jest and
# vitest everywhere; no mocha / @hapi/lab in any era, verified across history),
# so a marker never truncates the whole run: the suite continues, the affected
# file's other tests do not execute, and the deficit is recorded in a
# focus_marker.txt sidecar that execute.sh copies next to the commit's lcov.
# Because no declared runner is run-global, this can never mark a commit
# not-applicable.
na_if_focus_marker --runner jest --runner vitest packages

# ── Choose how tests are dispatched ─────────────────────────────────────────
# Lerna >= 7 runs on Nx, whose task graph makes each package's `test` target
# depend on the `test` target of its workspace dependencies. One failing
# dependency therefore skips every dependent package *before it starts*: when
# @opencrvs/commons fails, the remaining 12 tasks are never run and the run
# still looks like a normal (partial) result - only the first packages write
# lcov. This is not bail (--no-bail already disables that): packages with no
# dependents keep running after they fail, while dependents are dropped.
# The project's own CI does not use the root aggregator. It runs one job per
# package (`cd ${{ matrix.package }} && yarn test`) after building commons and
# components, so those eras are executed the same way here: every package with
# a test script is run independently, its exit code recorded, and nothing is
# skipped because a dependency failed.
PER_PACKAGE_TESTS=false
if [[ "$ROOT_TEST" == *"lerna run test"* ]]; then
    LERNA_RANGE=$(node -e "const d=require('./package.json');process.stdout.write(String(((d.devDependencies||{}).lerna)||((d.dependencies||{}).lerna)||''))")
    LERNA_MAJOR=$(printf '%s' "$LERNA_RANGE" | grep -oE '[0-9]+' | head -1)
    if [ -z "$LERNA_MAJOR" ]; then
        print_header 2 "ERROR: root test script is Lerna-driven but no lerna version is pinned (range: '${LERNA_RANGE}')"
        exit 1
    fi
    if [ "$LERNA_MAJOR" -ge 7 ]; then
        PER_PACKAGE_TESTS=true
    fi
    print_header 4 "Lerna range: $LERNA_RANGE (major: $LERNA_MAJOR) -> per-package dispatch: $PER_PACKAGE_TESTS"
fi

# Per-package dispatch requires workspace packages that define a test script.
# If none are found the layout is not what this branch was written for: fail
# loudly instead of silently running nothing (or drifting back to the root
# aggregator, which is exactly the truncating path being avoided).
if [ "$PER_PACKAGE_TESTS" = "true" ]; then
    PKG_WITH_TESTS=0
    for PKG_JSON in packages/*/package.json; do
        [ -f "$PKG_JSON" ] || continue
        PKG_HAS_TEST=$(node -e "const d=require('./$PKG_JSON');process.stdout.write(String(((d.scripts||{}).test)||''))")
        if [ -n "$PKG_HAS_TEST" ]; then
            PKG_WITH_TESTS=$((PKG_WITH_TESTS + 1))
        fi
    done
    if [ "$PKG_WITH_TESTS" -eq 0 ]; then
        print_header 2 "ERROR: per-package dispatch selected but no package under packages/* defines a test script"
        exit 1
    fi
    print_header 4 "Packages with a test script: $PKG_WITH_TESTS"
fi

export COVERAGE_ENABLED=true

if [ "$PER_PACKAGE_TESTS" = "true" ]; then
    # ── Per-package test execution (Nx task graph bypassed) ─────────────────
    print_header 2 "Running per-package test suites with coverage"

    suite_start "test" "Running per-package test suites with coverage"

    TEST_EXIT=0
    PKG_COUNT=0
    FAILED_PACKAGES=()
    CRASHED_PACKAGES=()
    # Packages whose (patched) test script invokes a coverage-capable runner.
    # Each of them must contribute an lcov file; anything else means a suite
    # silently produced no coverage.
    EXPECTED_LCOV_PKGS=()

    for PKG_JSON in packages/*/package.json; do
        [ -f "$PKG_JSON" ] || continue
        PKG_DIR=$(dirname "$PKG_JSON")
        PKG_TEST=$(node -e "const d=require('./$PKG_JSON');process.stdout.write(String(((d.scripts||{}).test)||''))")
        [ -n "$PKG_TEST" ] || continue

        PKG_COUNT=$((PKG_COUNT + 1))
        if printf '%s' "$PKG_TEST" | grep -qE 'vitest|jest|mocha|craco test'; then
            EXPECTED_LCOV_PKGS+=("$(basename "$PKG_DIR")")
        fi
        print_header 3 "$PKG_DIR" "$PKG_TEST"

        PKG_LOG=$(mktemp)
        set +e
        ( cd "$PKG_DIR" && $PM_TEST ) 2>&1 | tee "$PKG_LOG"
        PKG_EXIT=${PIPESTATUS[0]}
        set -e

        if [ "$PKG_EXIT" -ne 0 ]; then
            TEST_EXIT=1
            FAILED_PACKAGES+=("$PKG_DIR (exit $PKG_EXIT)")

            # Same zero-test guard as the root dispatch: a package that exits
            # non-zero without ever reporting a test count did not run its
            # suite (infrastructure failure, not a developer-facing failure).
            CLEAN_PKG_LOG=$(mktemp)
            sed -E 's/\x1b\][^\x07]*(\x07|\x1b\\)//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b[()][A-Z0-9]//g; s/\r/\n/g' "$PKG_LOG" > "$CLEAN_PKG_LOG"
            if grep -qE "Test Files[[:space:]]+no tests|Tests:[[:space:]]+0 total" "$CLEAN_PKG_LOG" || \
               ! grep -qE "([1-9][0-9]* passed|[1-9][0-9]* failed|[1-9][0-9]* passing|[1-9][0-9]* failing|Tests:[[:space:]]+[1-9])" "$CLEAN_PKG_LOG"; then
                CRASHED_PACKAGES+=("$PKG_DIR")
            fi
            rm -f "$CLEAN_PKG_LOG"
        fi
        rm -f "$PKG_LOG"
    done

    print_header 4 "Packages executed: $PKG_COUNT | failed: ${#FAILED_PACKAGES[@]}"
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        printf '  - %s\n' "${FAILED_PACKAGES[@]}"
    fi

    if [ ${#CRASHED_PACKAGES[@]} -gt 0 ]; then
        print_header 2 "ERROR: ${#CRASHED_PACKAGES[@]} package(s) crashed before executing tests or reported 0 tests (infrastructure failure):"
        printf '  - %s\n' "${CRASHED_PACKAGES[@]}"
        suite_end "test" "$TEST_EXIT"
        exit 1
    fi

    bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"

    # Completeness: every suite that ran a runner must have left an lcov file.
    # A missing file means the suite was skipped, crashed before reporting, or
    # discarded its report - the silent-partial modes this branch exists to
    # prevent. Runs with failing tests are expected to have full coverage too.
    print_header 4 "Verifying every expected suite produced lcov"
    MISSING_LCOV=()
    for PKG_NAME in "${EXPECTED_LCOV_PKGS[@]}"; do
        PKG_COV_DIR="$COVERAGE_REPORT_PATH/packages/$PKG_NAME"
        PKG_LCOV=""
        if [ -d "$PKG_COV_DIR" ]; then
            PKG_LCOV=$(find "$PKG_COV_DIR" -name 'test.lcov.info' -print -quit)
        fi
        # An lcov file with no SF: record is the same as no coverage at all
        # (find-and-move-lcov deletes those, but the assertion must stand alone).
        if [ -n "$PKG_LCOV" ] && grep -q '^SF:' "$PKG_LCOV"; then
            continue
        fi
        MISSING_LCOV+=("$PKG_NAME")
    done

    if [ ${#MISSING_LCOV[@]} -gt 0 ]; then
        print_header 2 "ERROR: ${#MISSING_LCOV[@]} of ${#EXPECTED_LCOV_PKGS[@]} expected suite(s) produced no lcov:"
        printf '  - %s\n' "${MISSING_LCOV[@]}"
        suite_end "test" "$TEST_EXIT"
        exit 1
    fi
    print_header 4 "All ${#EXPECTED_LCOV_PKGS[@]} expected suites produced lcov"

    suite_end "test" "$TEST_EXIT"
else
    # ── Single root test invocation (pre-Nx / non-Lerna eras) ──────────────
    print_header 2 "Running root test suite with coverage"

    suite_start "test" "Running root test dispatch ($ROOT_TEST)"

    TEST_LOG=$(mktemp)

    set +e
    $PM_TEST 2>&1 | tee "$TEST_LOG"
    TEST_EXIT=${PIPESTATUS[0]}
    set -e

    print_header 4 "Validating monorepo test suite execution"

    CLEAN_TEST_LOG=$(mktemp)
    sed -E 's/\x1b\][^\x07]*(\x07|\x1b\\)//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b[()][A-Z0-9]//g; s/\r/\n/g' "$TEST_LOG" > "$CLEAN_TEST_LOG"

    # Generalized check: Verify that packages attempting tests did not crash before reporting test results or report 0 tests on non-zero exit
    CRASHED_PACKAGES=()
    for pkg in $(grep -E "error Command failed with exit code|npm ERR! code ELIFECYCLE" "$CLEAN_TEST_LOG" | grep -oE '^[@a-zA-Z0-9/_-]+:' | tr -d ':' | sort -u); do
        PKG_OUTPUT=$(grep "^${pkg}:" "$CLEAN_TEST_LOG" || true)
        if echo "$PKG_OUTPUT" | grep -qE "Test Files[[:space:]]+no tests|Tests:[[:space:]]+0 total" || \
           ! echo "$PKG_OUTPUT" | grep -qE "([1-9][0-9]* passed|[1-9][0-9]* failed|[1-9][0-9]* passing|[1-9][0-9]* failing|Tests:[[:space:]]+[1-9])"; then
            CRASHED_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#CRASHED_PACKAGES[@]} -gt 0 ]; then
        print_header 2 "ERROR: ${#CRASHED_PACKAGES[@]} package(s) crashed before executing tests or reported 0 tests (infrastructure failure):"
        printf '  - %s\n' "${CRASHED_PACKAGES[@]}"
        rm -f "$TEST_LOG" "$CLEAN_TEST_LOG"
        exit 1
    fi
    rm -f "$TEST_LOG" "$CLEAN_TEST_LOG"

    bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"
    suite_end "test" "$TEST_EXIT"
fi

print_header 1 "opencrvs-core coverage run complete"
