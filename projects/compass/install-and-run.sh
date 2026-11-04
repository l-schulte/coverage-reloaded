#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/resolve-and-pin.sh
source /coverage_reloaded/na-if-focus-marker.sh

resolve_and_pin "d2va9gm4j17fy9.cloudfront.net"

# Hosts that failed to resolve in the 2026-10/11 re-run (see logs/*.error):
#   downloads.mongodb.org     - mongodb-download-url version manifest (mongodb-runner 4.x)
#   fastdl.mongodb.org        - mongod tarball (mongodb-runner 4.x downloads unconditionally)
#   release-assets.githubusercontent.com - prebuild-install release assets (native rebuilds)
#   www/artifacts.electronjs.org - electron download metadata
# github.com is already pinned in execute.sh; the mongodb-runner 5.x / compass-test-server
# path does not need the mongodb.org hosts at all because install-and-run.sh seeds that
# downloader's cache below (presence of .artifact_info short-circuits it).
resolve_and_pin "downloads.mongodb.org"
resolve_and_pin "fastdl.mongodb.org"
resolve_and_pin "release-assets.githubusercontent.com"
resolve_and_pin "api.github.com"
resolve_and_pin "www.electronjs.org"
resolve_and_pin "artifacts.electronjs.org"

# Deterministic DNS answers for the three test-only names this suite resolves.
# A normally-configured resolver answers all of them immediately; the container
# resolver intermittently times out (EAI_AGAIN), which turns fast, *expected* DNS
# failures into mocha timeouts and exact-string assertion mismatches:
#   my.ssh-server.com                - real domain, NXDOMAIN (verified with `host`)
#   nonexistent-ssh-server.test     - RFC 2606 reserved TLD, can never exist
#   compass-tests.fakehost.localhost - test fixture; every era's spec accepts ENOTFOUND
# Only these exact names are intercepted; every other lookup is delegated untouched.
# The file is written here but ACTIVATED only for the test phase (see the export just
# before the first suite_start): installation and compilation must resolve real hosts
# (registry, GitHub, mongodb downloads) with the container's own resolver, and a bug in
# the interceptor must not be able to break installs.
cat > /tmp/compass-dns-interceptor.js <<'COMPASS_DNS_EOF'
'use strict';
var dns = require('dns');
var originalLookup = dns.lookup;
var hasOwn = Object.prototype.hasOwnProperty;

var NOT_FOUND = {
  'my.ssh-server.com': true,
  'nonexistent-ssh-server.test': true,
  // Test fixture. The 2022 spec asserts ENOTFOUND only; the 2024+ spec accepts ENOTFOUND
  // *or* ECONNREFUSED 127.0.0.1:22. ENOTFOUND is therefore the only answer valid across
  // every era, so this name must NOT be mapped to loopback.
  'compass-tests.fakehost.localhost': true
};

function reply(callback, args) {
  process.nextTick(function () { callback.apply(null, args); });
}

if (typeof originalLookup === 'function') {
  dns.lookup = function (hostname, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    } else if (typeof options === 'number') {
      options = { family: options };
    }
    if (typeof callback !== 'function') {
      return originalLookup.call(this, hostname, options, callback);
    }
    if (typeof hostname === 'string') {
      var name = hostname.toLowerCase();
      if (hasOwn.call(NOT_FOUND, name)) {
        var err = new Error('getaddrinfo ENOTFOUND ' + hostname);
        err.errno = -3008;
        err.code = 'ENOTFOUND';
        err.syscall = 'getaddrinfo';
        err.hostname = hostname;
        return reply(callback, [err]);
      }
    }
    return originalLookup.call(this, hostname, options, callback);
  };
}
COMPASS_DNS_EOF

export NODE_OPTIONS="${NODE_OPTIONS:-} --max-old-space-size=8192"

# Node 22.18+ enables --experimental-strip-types by default. Mocha 10's
# requireOrImport() then imports .ts test-bootstrap files as ESM, where `require`
# is undefined, so any suite whose bootstrap calls require() crashes before a
# single test runs (upstream COMPASS-10162). Upstream worked around it in
# mocha-config-compass >= 1.7.x via 'node-option': ['no-experimental-strip-types'];
# replicate that for commits predating the fix. The probe keeps this inert on
# Node < 22.18, where the flag does not exist and would abort with "bad option".
if node --no-experimental-strip-types -e '' >/dev/null 2>&1; then
    export NODE_OPTIONS="${NODE_OPTIONS} --no-experimental-strip-types"
fi

export NX_PARALLEL=1
export CI=false
export ELECTRON_EXTRA_LAUNCH_ARGS="--no-sandbox"

cd /coverage_reloaded/repo

HAS_WORKSPACES=$(node -p "!!((require('./package.json').workspaces))" 2>/dev/null || echo false)
if [ "$HAS_WORKSPACES" != "true" ]; then
    not_applicable "Pre-workspaces era (unintegrated monorepo plugins, June 2021 and earlier; see OVERVIEW.md)"
fi

na_if_focus_marker --runner mocha --exclude 'packages/compass-e2e-tests' packages

# Neutralize keytar timebomb test (compares Date.now() to May 2024 deadline, multi-line)
node -e '
  const fs = require("fs");
  const path = require("path");
  function walk(dir) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, e.name);
      if (e.isDirectory() && e.name !== "node_modules") walk(full);
      else if (e.isFile() && full.includes("connection-storage") && full.endsWith(".spec.ts")) {
        let s = fs.readFileSync(full, "utf8");
        if (s.includes("reminds us to remove keytar") || s.includes("endOfKeytarDate") || s.includes("new Date()")) {
          s = s.replace(/expect\(\s*new Date\(\)\s*,/g, "expect(testDate,");
          fs.writeFileSync(full, s);
        }
      }
    }
  }
  if (fs.existsSync("packages")) walk("packages");
' 2>/dev/null || true

# Redirect GA debug endpoint to WayPack mock (see OVERVIEW.md)
for ga_file in $(find packages -name "*ga.js" 2>/dev/null); do
    sed -i "s|return format(this.baseUrl, this.debug ? '/debug' : '');|return 'http://waypack:3000/local/ga-debug.json?';|g" "$ga_file"
    sed -i "s|https://www.google-analytics.com%s/collect?|http://waypack:3000/local/ga-debug.json?|g" "$ga_file"
done

# Redirect AWS IP ranges endpoint to WayPack request proxy
for f in $(grep -rl "https://ip-ranges.amazonaws.com/ip-ranges.json" packages/ 2>/dev/null); do
    sed -i 's|https://ip-ranges.amazonaws.com/ip-ranges.json|http://waypack:3000/request/https://ip-ranges.amazonaws.com/ip-ranges.json|g' "$f"
done

# Redirect cloud CIDRs to WayPack request proxy
for f in $(grep -rl "https://raw.githubusercontent.com/mongodb-js/mongodb-cloud-info/main/cidrs.json" packages/ node_modules/ 2>/dev/null); do
    sed -i 's|https://raw.githubusercontent.com/mongodb-js/mongodb-cloud-info/main/cidrs.json|http://waypack:3000/request/https://raw.githubusercontent.com/mongodb-js/mongodb-cloud-info/main/cidrs.json|g' "$f"
done

# compass-web's tr46 polyfill spec fetches the WPT toascii.json in a `before` hook. The URL
# is content-addressed by commit SHA, so proxying it through WayPack caches an immutable
# artifact and removes a GitHub round-trip from every test run; when that round-trip
# transiently failed the suite died with `TypeError: fetch failed` (66 of 4,408 runs, one
# per affected day). Only the static prefix is rewritten, so the ${wptSHA} template stays.
for f in $(grep -rl "https://raw.githubusercontent.com/web-platform-tests/wpt/" packages/ 2>/dev/null); do
    sed -i 's|https://raw.githubusercontent.com/web-platform-tests/wpt/|http://waypack:3000/request/https://raw.githubusercontent.com/web-platform-tests/wpt/|g' "$f"
done

if [ ! -f package.json ]; then
    not_applicable "No package.json at this commit, no test infrastructure to run"
fi

CI_MONGO_VER=""
if [ -f .evergreen/print-compass-env.sh ]; then
    CI_MONGO_VER=$(grep -E '^[[:space:]]*export[[:space:]]+MONGODB_DEFAULT_VERSION=' .evergreen/print-compass-env.sh 2>/dev/null | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
fi

if [ -z "$CI_MONGO_VER" ] && [ -f .evergreen.yml ]; then
    CI_MONGO_VER=$(node -e "
        const fs = require('fs');
        const txt = fs.readFileSync('.evergreen.yml', 'utf8');
        const m1 = txt.match(/MONGODB_VERSION=\\\${mongodb_version\|([^}]+)\}/);
        if (m1) console.log(m1[1]);
    " 2>/dev/null || true)
fi

if [ -z "$CI_MONGO_VER" ]; then
    for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
        if [ -f "$wf" ]; then
            CI_MONGO_VER=$(node -e "
                const fs = require('fs');
                const txt = fs.readFileSync('$wf', 'utf8');
                const m = txt.match(/MONGODB_VERSION:\s*['\"]?([^\s'\"]+)/);
                if (m) console.log(m[1]);
            " 2>/dev/null || true)
            if [ -n "$CI_MONGO_VER" ]; then break; fi
        fi
    done
fi

if [ -z "$CI_MONGO_VER" ]; then
    CI_MONGO_VER=$(node -e "
        function getDeps(f) {
            try { const p = require(f); return Object.assign({}, p.dependencies, p.devDependencies); } catch(e) { return {}; }
        }
        const deps = Object.assign({}, getDeps('./package.json'), getDeps('./packages/data-service/package.json'));
        const v = deps.mongodb || '';
        const m = v.match(/\d+/);
        if (m) {
            const maj = m[0];
            if (maj === '3') console.log('4.4');
            else if (maj === '4') console.log('5.0');
            else if (maj === '5' || maj === '6') console.log('6.0');
            else if (maj === '7') console.log('7.0');
            else if (maj >= '8') console.log('8.0');
        }
    " 2>/dev/null || true)
fi

if [ -z "$CI_MONGO_VER" ]; then
    CI_MONGO_VER="4.4"
fi

NORMALIZED_MONGO_VER="${CI_MONGO_VER%-enterprise}"
print_header 4 "Detected MongoDB version from project CI/manifest: $CI_MONGO_VER (normalized: $NORMALIZED_MONGO_VER)"
if [[ "$NORMALIZED_MONGO_VER" =~ ^4 ]]; then
    ln -sf /opt/mongodb/4.4/bin/mongod /usr/local/bin/mongod
    export MONGODB_VERSION="4.4.29"
elif [[ "$NORMALIZED_MONGO_VER" =~ ^5 ]]; then
    ln -sf /opt/mongodb/5.0/bin/mongod /usr/local/bin/mongod
    export MONGODB_VERSION="5.0.28"
elif [[ "$NORMALIZED_MONGO_VER" =~ ^6 ]]; then
    ln -sf /opt/mongodb/6.0/bin/mongod /usr/local/bin/mongod
    export MONGODB_VERSION="6.0.20"
elif [[ "$NORMALIZED_MONGO_VER" =~ ^7 ]]; then
    ln -sf /opt/mongodb/7.0/bin/mongod /usr/local/bin/mongod
    export MONGODB_VERSION="7.0.14"
else
    ln -sf /opt/mongodb/8.0/bin/mongod /usr/local/bin/mongod
    export MONGODB_VERSION="8.0.4"
fi
export MONGODB_RUNNER_VERSION="$MONGODB_VERSION"

# compass-test-server (2024+) delegates to mongodb-runner 5.x, which downloads its own
# mongod tarball instead of using a binary on PATH: @mongodb-js/mongodb-downloader
# resolves the artifact via https://downloads.mongodb.org/full.json and then fetches
# the tarball from https://fastdl.mongodb.org. Runtime DNS in the container is
# unreliable (getaddrinfo EAI_AGAIN), so the mocha `before all` hooks die before any
# test runs. The downloader short-circuits when <dir>/bin/.artifact_info exists, so
# seed that directory from the mongod already pre-cached above. The directory name is
# reproduced exactly as the library builds it: sha256(EVERGREEN_TASK_ID || '')[:12],
# then a character filter that also strips the dots from the version (8.0.4 -> 804).
node -e '
  const os = require("os"), path = require("path"), fs = require("fs"), crypto = require("crypto");
  const hash = crypto.createHash("sha256").update(process.env.EVERGREEN_TASK_ID || "").digest("hex").slice(0, 12);
  const base = path.join(os.tmpdir(), `compass-tests-${hash}`);
  const specs = new Set(["*"]);
  if (process.env.MONGODB_VERSION) specs.add(process.env.MONGODB_VERSION);
  const prefix = `mongodb-${process.platform}-${process.env.DISTRO_ID || "none"}-${process.arch}`;
  for (const spec of specs) {
    const dir = path.join(base, `${prefix}-${spec}-community`.replace(/[^a-zA-Z0-9_-]/g, ""));
    fs.mkdirSync(path.join(dir, "bin"), { recursive: true });
    const info = path.join(dir, "bin", ".artifact_info");
    if (!fs.existsSync(info)) fs.writeFileSync(info, "{}");
    const target = path.join(dir, "bin", "mongod");
    if (!fs.existsSync(target)) fs.symlinkSync("/usr/local/bin/mongod", target);
    // mongodb-runner'"'"'s sharded topology (data-service, 2025-11+) spawns <binDir>/mongos;
    // without it the spawn fails with ENOENT and the runner reports
    // "TypeError: Cannot read properties of undefined (reading '"'"'some'"'"')".
    const mtarget = path.join(dir, "bin", "mongos");
    if (!fs.existsSync(mtarget) && fs.existsSync("/usr/local/bin/mongos"))
      fs.symlinkSync("/usr/local/bin/mongos", mtarget);
    console.log(`Seeded mongodb-runner download cache: ${dir}`);
  }
'

print_header 2 "Starting Xvfb"
export DISPLAY=:99
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
sleep 2

print_header 2 "Installing dependencies"

if [ "$IS_NPM_MAIN_PM" != "true" ]; then
    print_header 2 "ERROR: unsupported package manager for compass" "expected npm, got '$package_manager'"
    exit 1
fi

export ELECTRON_MIRROR="http://waypack:3000/request/https://github.com/electron/electron/releases/download/"

CHROMEDRIVER_VERSION=$(node -p "
  try {
    const l = require('./package-lock.json');
    ((l.dependencies||{})['electron-chromedriver']||{}).version ||
    (((l.packages||{})['node_modules/electron-chromedriver']||{}).version) || ''
  } catch(e) { '' }
" 2>/dev/null || true)

if [ -n "$CHROMEDRIVER_VERSION" ]; then
    print_header 4 "Pre-seeding electron-chromedriver cache (v$CHROMEDRIVER_VERSION)"
    export ELECTRON_CACHE="$HOME/.cache/electron"
    mkdir -p "$ELECTRON_CACHE"
    curl -fsSL "http://waypack:3000/request/https://github.com/electron/electron/releases/download/v${CHROMEDRIVER_VERSION}/chromedriver-v${CHROMEDRIVER_VERSION}-linux-x64.zip" \
        -o "$ELECTRON_CACHE/chromedriver-v${CHROMEDRIVER_VERSION}-linux-x64.zip" || true
    curl -fsSL "http://waypack:3000/request/https://github.com/electron/electron/releases/download/v${CHROMEDRIVER_VERSION}/SHASUMS256.txt" \
        -o "$ELECTRON_CACHE/SHASUMS256.txt-${CHROMEDRIVER_VERSION}" || true
fi

if ! command -v nyc >/dev/null 2>&1; then
    NODE_MAJ=$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 18)
    if [ "$NODE_MAJ" -le 12 ]; then
        print_header 4 "Installing global nyc@14 for Node 12"
        npm install -g nyc@14 --registry "$WAYPACK_REGISTRY_CURRENT"
    else
        print_header 4 "Installing global nyc from WayPack Current registry"
        npm install -g nyc --registry "$WAYPACK_REGISTRY_CURRENT"
    fi
fi

if [ -f .npmrc ]; then
    # Point registry to WayPack to avoid querying live npmjs.org at runtime
    sed -i '/^registry[[:space:]]*=/d' .npmrc
    # Compass package.json accidentally declared node: ">=16.15.1" until July 2024 (commit fed1b54026)
    # even though CI and some devDependencies (e.g. @octokit/auth-token@4) already required Node 18.
    # While use_first selects Node 16 based on engines, engine-strict=true would cause npm to abort
    # on non-test release dependencies. Relaxing engine-strict lets npm warn instead of aborting.
    sed -i '/^engine-strict[[:space:]]*=/d' .npmrc
fi

print_header 2 "Patching test scripts to collect coverage and enforce --no-bail"
node /coverage_reloaded/patch-coverage.js

print_header 4 "Installing dependencies and compiling workspaces"
npm install --unsafe-perm --ignore-scripts
# Ensure electron/path.txt exists so require('electron') in Node-based unit tests
# does not throw "Electron failed to install correctly"
for p in $(find . -path '*/node_modules/electron' -type d 2>/dev/null); do
    if [ ! -f "$p/path.txt" ]; then
        printf '%s' "electron" > "$p/path.txt"
    fi
done

HAS_NODE_REBUILD=$(node -p "!!((require('./package.json').scripts||{})['node-rebuild'])" 2>/dev/null || echo false)
if [ "$HAS_NODE_REBUILD" = "true" ]; then
    print_header 4 "Running upstream native module rebuild: npm run node-rebuild"
    npm run node-rebuild
fi

if [ -d "node_modules/os-dns-native" ]; then
    npm rebuild os-dns-native --unsafe-perm
fi

# mongodb-client-encryption is an (optional) dependency of data-service and of the
# mongodb driver, but `npm install --ignore-scripts` above suppresses its
# prebuild-install/node-gyp step, so no mongocrypt.node is produced. The upstream
# node-rebuild script does not cover it. Without the addon the driver raises
# "Auto-encryption requested, but the module is not installed" (driver v6) or
# "Could not locate the bindings file" (driver v4, where data-service requires the
# module at import time and the whole package suite dies). Guarded on presence so
# it is inert for eras that predate CSFLE.
if [ -d "node_modules/mongodb-client-encryption" ]; then
    print_header 4 "Rebuilding mongodb-client-encryption native addon"
    npm rebuild mongodb-client-encryption --unsafe-perm
fi

print_header 4 "Compiling workspace packages"
npx lerna run bootstrap --stream --concurrency 1 --no-bail



# data-service's connectivity integration suite (present only 2021-08-26 .. 2021-10-11)
# starts a MongoDB through docker-compose. Without a daemon its `before all` hook dies with
# `spawn docker-compose ENOENT`, so start DinD only for commits that still contain that
# spec — every other commit must not pay for a dockerd it never uses.
if [ -f packages/data-service/test/connectivity.spec.ts ]; then
    source /coverage_reloaded/start-dind.sh
    # Prefetch the image the compose file asks for (mongo:${MONGODB_VERSION}) while the
    # registry pull-through proxy env is active, then drop it so it cannot leak into the
    # test processes and change their outbound HTTP behaviour.
    docker pull "mongo:${MONGODB_VERSION}"
    unset HTTP_PROXY HTTPS_PROXY
fi

print_header 2 "Running unit & package test suite"

# Activate the DNS interceptor for the test phase only. The test-only hostnames it
# answers are never resolved during install/compile, and keeping it out of that phase
# means an interceptor bug can only affect tests, never the build.
export NODE_OPTIONS="${NODE_OPTIONS} --require /tmp/compass-dns-interceptor.js"

# In historical monorepo eras, certain packages start mongodb-runner background workers
# during pretest. If a package test fails, posttest is skipped by npm, leaving an
# orphaned mongodb-runner-worker daemon whose stdio keeps Lerna's pipe open indefinitely.
(
    while true; do
        for pid in $(pgrep -f "mongodb-runner-worker" 2>/dev/null); do
            ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d " ")
            if [ "$ppid" = "1" ]; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 3
    done
) &
WATCHDOG_PID=$!
trap "kill -9 $WATCHDOG_PID 2>/dev/null || true; pkill -9 -f mongod 2>/dev/null || true" EXIT

suite_start "test" "Running package test dispatch"

HAS_TEST_CI=$(node -p "!!((require('./package.json').scripts||{})['test-ci'])")

TEST_LOG=$(mktemp)
trap 'rm -f "$TEST_LOG"; kill -9 $WATCHDOG_PID 2>/dev/null || true' EXIT

set +e
if [ "$HAS_TEST_CI" = "true" ]; then
    npm run test-ci -- --stream --no-bail --ignore compass-e2e-tests 2>&1 | tee "$TEST_LOG"
    TEST_EXIT=${PIPESTATUS[0]}
else
    npm run test -- --stream --no-bail --ignore compass-e2e-tests 2>&1 | tee "$TEST_LOG"
    TEST_EXIT=${PIPESTATUS[0]}
fi
set -e

print_header 4 "Validating test suite execution"

if [ "$HAS_LERNA" = "true" ] || [ "$HAS_WORKSPACES" = "true" ]; then
    if ! grep -qE "lerna (success|ERR!) (run Ran npm script|exec Executed command)" "$TEST_LOG"; then
        print_header 2 "ERROR: Lerna execution did not reach completion"
        exit 1
    fi

    # Strip ANSI color sequences before parsing test counts
    CLEAN_TEST_LOG=$(mktemp)
    sed -E 's/\x1b\][^\x07]*(\x07|\x1b\\)//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b[()][A-Z0-9]//g; s/\r/\n/g' "$TEST_LOG" > "$CLEAN_TEST_LOG"

    # Assert that tests actually executed across packages (guarding against silent 0-passing runs)
    TESTS_RAN_COUNT=$(grep -E "[1-9][0-9]* passing|Tests:[[:space:]]+[1-9][0-9]* passed" "$CLEAN_TEST_LOG" | wc -l)

    if [ "$TESTS_RAN_COUNT" -eq 0 ]; then
        rm -f "$CLEAN_TEST_LOG"
        print_header 2 "ERROR: Zero tests were executed across all packages in this run"
        exit 1
    fi

    # Generalized check: Verify that packages attempting tests did not crash before reporting test results.
    # npm >= 10 reports a failed lifecycle script as "npm ERR! Lifecycle script `x` failed with error:",
    # while npm <= 9 reported "npm ERR! code ELIFECYCLE". Both phrasings must be matched, otherwise this
    # check silently passes on npm 10 (exactly how the compass-schema-validation COMPASS-10162 crash went
    # unnoticed for 436 runs). lerna --stream prefixes every line with "<pkg>: ", so the package name sits
    # on the SAME line as the npm error, not on the preceding one.
    CRASHED_CANDIDATES=$(grep -oE '^[@a-zA-Z0-9/_-]+: npm ERR! (code ELIFECYCLE|Lifecycle script)' "$CLEAN_TEST_LOG" | sed 's/: npm ERR!.*//' | sort -u)
    if [ -z "$CRASHED_CANDIDATES" ]; then
        # Fallback for non-streamed output, where the package name precedes the error line
        CRASHED_CANDIDATES=$(grep -B 1 "npm ERR! code ELIFECYCLE" "$CLEAN_TEST_LOG" | grep -oE '^[@a-zA-Z0-9/_-]+:' | tr -d ':' | sort -u)
    fi
    CRASHED_PACKAGES=()
    for pkg in $CRASHED_CANDIDATES; do
        PKG_OUTPUT=$(grep "^${pkg}:" "$CLEAN_TEST_LOG" || true)
        if ! echo "$PKG_OUTPUT" | grep -qE "([1-9][0-9]* passing|[1-9][0-9]* failing|Tests:[[:space:]]+[1-9])"; then
            CRASHED_PACKAGES+=("$pkg")
        fi
    done
    rm -f "$CLEAN_TEST_LOG"

    if [ ${#CRASHED_PACKAGES[@]} -gt 0 ]; then
        print_header 2 "ERROR: ${#CRASHED_PACKAGES[@]} packages crashed before executing tests (infrastructure failure):"
        printf '  - %s\n' "${CRASHED_PACKAGES[@]}"
        exit 1
    fi
    echo "  [OK] Sanity check passed: Lerna completed run, $TESTS_RAN_COUNT package test tallies verified, 0 infrastructure crashes"
else
    # Era 1: Single package mocha
    CLEAN_TEST_LOG=$(mktemp)
    sed -E 's/\x1b\][^\x07]*(\x07|\x1b\\)//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1b[()][A-Z0-9]//g; s/\r/\n/g' "$TEST_LOG" > "$CLEAN_TEST_LOG"
    if ! grep -qE "[1-9][0-9]* passing" "$CLEAN_TEST_LOG"; then
        rm -f "$CLEAN_TEST_LOG"
        print_header 2 "ERROR: Zero tests were executed in single-package suite"
        exit 1
    fi
    rm -f "$CLEAN_TEST_LOG"
    echo "  [OK] Sanity check passed: single-package test tally verified"
fi

bash /coverage_reloaded/find-and-move-lcov.sh "test" "true" "$TEST_EXIT"

if [ "$HAS_LERNA" = "true" ] || [ "$HAS_WORKSPACES" = "true" ]; then
    # Refine per-package exit codes from Lerna output so passing workspaces report exit_code: 0,
    # while packages with test failures or lifecycle errors record their actual exit code.
    node -e '
      const fs = require("fs");
      const path = require("path");
      const testLog = fs.readFileSync(process.argv[1], "utf8");
      const covDir = process.env.COVERAGE_REPORT_PATH;
      if (!covDir || !fs.existsSync(covDir)) process.exit(0);

      const logLines = testLog.split("\n");

      function checkDir(d) {
        for (const e of fs.readdirSync(d, { withFileTypes: true })) {
          const full = path.join(d, e.name);
          if (e.isDirectory()) checkDir(full);
          else if (e.name === "test.exit_code") {
            const relDir = path.relative(covDir, path.dirname(full));
            const pkgJson = path.join(relDir, "package.json");
            let pkgName = "";
            try { pkgName = JSON.parse(fs.readFileSync(pkgJson, "utf8")).name; } catch(err) {}
            if (pkgName) {
              const prefix = pkgName + ":";
              let failCount = 0;
              let hasError = false;
              for (const line of logLines) {
                if (!line.startsWith(prefix)) continue;
                const mFail = line.match(/:\s+(\d+)\s+failing\b/);
                if (mFail) failCount += parseInt(mFail[1], 10);
                const mKarma = line.match(/Failed with exit code:\s*(\d+)/);
                if (mKarma) failCount += parseInt(mKarma[1], 10);
                if (line.includes("npm ERR! Lifecycle script") && (line.includes("`test") || line.includes("`check"))) {
                  hasError = true;
                }
              }
              if (failCount > 0) {
                fs.writeFileSync(full, Math.min(failCount, 255) + "\n");
              } else if (hasError) {
                fs.writeFileSync(full, "1\n");
              } else {
                fs.writeFileSync(full, "0\n");
              }
            }
          }
        }
      }
      checkDir(covDir);
    ' "$TEST_LOG" 2>/dev/null || true
fi

rm -f "$TEST_LOG"
suite_end "test" "$TEST_EXIT"

print_header 1 "Compass coverage run complete"
