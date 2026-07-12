#!/bin/bash
set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

# ── Install dependencies ──────────────────────────────────────
print_header 2 "Installing dependencies"

npm install --no-fund

# These are needed for require() hooks during c8 instrumentation
npm install @babel/register --no-fund
npm install source-map-support --no-fund
npm install mocha-multi --no-fund

# ── Detect & patch mocha config (CRITICAL: disable bail) ──────
# The project's .mocharc.js/.mocharc.cjs has `bail: true` across
# the entire history. We MUST override it. The CLI --no-bail flag
# is not sufficient — mocha config file `bail` takes precedence
# in some versions. We create a patched copy with bail=false.
print_header 2 "Patching mocha config (disable bail)"

if [ -f "./config/.mocharc.cjs" ]; then
    MOCHA_CONFIG_SRC="./config/.mocharc.cjs"
    BASE_NAME=".mocharc.cjs"
    PATCHED_CONFIG="./config/.mocharc.patched.cjs"
elif [ -f "./config/.mocharc.js" ]; then
    MOCHA_CONFIG_SRC="./config/.mocharc.js"
    BASE_NAME=".mocharc.js"
    PATCHED_CONFIG="./config/.mocharc.patched.js"
else
    echo "  No mocha config found — tests may fail without one."
    PATCHED_CONFIG=""
fi

if [ -n "$PATCHED_CONFIG" ]; then
    cat > "$PATCHED_CONFIG" <<EOF
const base = require('./${BASE_NAME}');
const merged = Object.assign({}, base, {
  bail: false,
  timeout: Math.max(base.timeout || 10000, 60000),
});
// If the base config defines \`spec\`, mocha UNIONS it with any positional test
// file we pass on the CLI (running extra/other files). Since each variant runs
// an explicit file, drop spec so the CLI file is authoritative.
delete merged.spec;
module.exports = merged;
EOF
    echo "  Patched ${BASE_NAME} → bail=false, timeout>=60000, spec stripped"
fi

# ── Detect which test scripts exist at this commit ────────────
print_header 2 "Detecting test scripts"

detect_script() {
    if node -e "process.exit(require('./package.json').scripts['$1'] ? 0 : 1)" 2>/dev/null; then
        local script
        script=$(node -p "require('./package.json').scripts['$1']")
        print_header 4 "Detected script '$1': $script" >&2
        echo "true"
    else
        echo "false"
    fi
}

HAS_NODE_MEMORY=$(detect_script "test:node:memory")
HAS_NODE_DEXIE=$(detect_script "test:node:dexie")
HAS_NODE_LOKIJS=$(detect_script "test:node:lokijs")
HAS_NODE_POUCHDB=$(detect_script "test:node:pouchdb")
HAS_NODE_DEXIE_WORKER=$(detect_script "test:node:dexie-worker")
HAS_NODE_MEMORY_VALIDATION=$(detect_script "test:node:memory-validation")
HAS_NODE_CUSTOM=$(detect_script "test:node:custom")
HAS_NODE_REMOTE=$(detect_script "test:node:remote")
HAS_NODE_FOUNDATIONDB=$(detect_script "test:node:foundationdb")
HAS_NODE_MONGODB=$(detect_script "test:node:mongodb")
HAS_CORE=$(detect_script "test:core")
HAS_FULL=$(detect_script "test:full")

echo "  memory=$HAS_NODE_MEMORY  dexie=$HAS_NODE_DEXIE  lokijs=$HAS_NODE_LOKIJS  pouchdb=$HAS_NODE_POUCHDB"
echo "  dexie-worker=$HAS_NODE_DEXIE_WORKER  memory-validation=$HAS_NODE_MEMORY_VALIDATION"
echo "  custom=$HAS_NODE_CUSTOM  remote=$HAS_NODE_REMOTE  foundationdb=$HAS_NODE_FOUNDATIONDB  mongodb=$HAS_NODE_MONGODB"
echo "  core=$HAS_CORE  full=$HAS_FULL"

# Detect if --expose-gc is used across any test script.
# --expose-gc is a V8 flag; mocha only forwards it to the test process via the
# --v8- prefix. Bare --expose-gc is parsed as a spec pattern ("No test files found"),
# and NODE_OPTIONS rejects it before Node 20.18/22.3.
# Detect across ALL scripts (not just test:node:memory) and pass --v8-expose-gc
# to every mocha invocation — exposing gc to a suite that doesn't call global.gc()
# is harmless.
EXPOSE_GC_FLAG=""
if node -p "Object.values(require('./package.json').scripts||{}).some(s => (s||'').includes('--expose-gc'))" 2>/dev/null | grep -q true; then
    EXPOSE_GC_FLAG="--v8-expose-gc"
    echo "  project uses --expose-gc → passing --v8-expose-gc to mocha"
fi

# ── Run transpile once ────────────────────────────────────────
# All test scripts call transpile internally. Run it once to
# avoid redundant work across storage variants.
if npm run | grep -q "^  transpile"; then
    print_header 2 "Running transpile"
    npm run transpile
elif npm run | grep -q "^  pretest"; then
    print_header 2 "Running pretest"
    npm run pretest
fi

# ── Verify transpile output ───────────────────────────────────
print_header 2 "Verifying transpile output"
echo "  Node version: $(node -v)"
echo "  c8 version: $(npx --registry=$VERDACCIO_REGISTRY c8 --version 2>&1 || echo 'unknown')"
if [ -d "./test_tmp" ]; then
    FILE_COUNT=$(find ./test_tmp -type f | wc -l)
    echo "  test_tmp/ EXISTS — $FILE_COUNT files"
    echo "  test_tmp/unit.test.js exists: $([ -f ./test_tmp/unit.test.js ] && echo 'YES' || echo 'NO')"
    echo "  test_tmp/unit/ directory exists: $([ -d ./test_tmp/unit ] && echo 'YES' || echo 'NO')"
    echo "  test_tmp/unit/core.node.js exists: $([ -f ./test_tmp/unit/core.node.js ] && echo 'YES' || echo 'NO')"
    echo "  test_tmp/unit/full.node.js exists: $([ -f ./test_tmp/unit/full.node.js ] && echo 'YES' || echo 'NO')"
    echo ""
    echo "  Top-level files in test_tmp/:"
    ls -la ./test_tmp/ 2>&1 | head -20
    echo ""
    echo "  Files in test_tmp/unit/ (first 30):"
    ls ./test_tmp/unit/ 2>&1 | head -30
else
    echo "  test_tmp/ DOES NOT EXIST"
fi
if [ -f .transpile_state.json ]; then
    echo "  .transpile_state.json exists (cached state from previous run)"
    echo "  Size: $(wc -c < .transpile_state.json) bytes"
fi

# ── FoundationDB: detect API version & install right combo ────
# The project switched from FDB 6.3.x (apiVersion 630) to FDB 7.3.x
# (apiVersion 720) at commit 66babde21. We detect which version the
# checked-out commit needs and install the matching FDB server DEBs
# + npm package. Both DEB sets are pre-downloaded in the Docker image
# at /opt/; the npm package is installed via Verdaccio at runtime.
if [ "$HAS_NODE_FOUNDATIONDB" = "true" ]; then
    print_header 2 "Detecting FoundationDB API version"

    # Read the foundationDBAPIVersion from the source config.ts at this commit
    FDB_API_VERSION=$(node -e "
        try {
            const fs = require('fs');
            const src = fs.readFileSync('./test/unit/config.ts', 'utf8');
            const m = src.match(/foundationDBAPIVersion\s*=\s*(\d+)/);
            if (m) {
                console.log(m[1]);
            } else {
                console.log('630');
            }
        } catch(e) {
            console.log('630');
        }
    ")
    print_header 4 "Detected foundationDBAPIVersion = $FDB_API_VERSION"

    if [ "$FDB_API_VERSION" -ge 700 ]; then
        print_header 3 "Installing FoundationDB 7.3.x (apiVersion $FDB_API_VERSION)"
        dpkg -i /opt/fdb7-clients.deb 2>&1 || true
        dpkg -i /opt/fdb7-server.deb 2>&1 || true
        print_header 4 "FDB 7.3.x DEBs installed"
        print_header 4 "Installing foundationdb npm package v2.x via Verdaccio"
        npm install --registry=$VERDACCIO_REGISTRY -g foundationdb@2.0.1
        GLOBAL_NM=$(npm root -g)
        ln -sf "$GLOBAL_NM/foundationdb" node_modules/foundationdb
        print_header 4 "Symlinked foundationdb v2 from $GLOBAL_NM/foundationdb"
    else
        print_header 3 "Installing FoundationDB 6.3.x (apiVersion $FDB_API_VERSION)"
        dpkg -i /opt/fdb6-clients.deb 2>&1 || true
        dpkg -i /opt/fdb6-server.deb 2>&1 || true
        print_header 4 "FDB 6.3.x DEBs installed"
        print_header 4 "Installing foundationdb npm package v1.x via Verdaccio"
        npm install --registry=$VERDACCIO_REGISTRY -g foundationdb@1.1.4
        GLOBAL_NM=$(npm root -g)
        ln -sf "$GLOBAL_NM/foundationdb" node_modules/foundationdb
        print_header 4 "Symlinked foundationdb v1 from $GLOBAL_NM/foundationdb"
    fi

    print_header 4 "Verifying foundationdb module resolution"
    node -e "try { console.log('  ✓ foundationdb resolved from ' + require.resolve('foundationdb')); } catch(e) { console.log('  ✗ require.resolve failed: ' + e.message); }" 2>&1 || true
    node -e "try { const m = require('foundationdb'); console.log('  ✓ foundationdb loaded, exports:', Object.keys(m).join(', ')); } catch(e) { console.log('  ✗ require() failed: ' + e.message); }" 2>&1 || true
fi

# If dexie-worker is used, we need webpack workers built
if [ "$HAS_NODE_DEXIE_WORKER" = "true" ]; then
    if npm run | grep -q "^  build:workers"; then
        print_header 2 "Building workers (needed for dexie-worker)"
        npm run build:workers
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Docker-in-Docker: start daemon for external services
# ═══════════════════════════════════════════════════════════════
# MongoDB and FoundationDB both require external services that we
# start via Docker inside the container. The container must be run
# with --privileged (docker-run.sh handles this via LABEL dind.project).
print_header 2 "Starting Docker daemon"
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
# Wait up to 30s for the daemon to be ready
for i in $(seq 1 30); do
    if docker ps > /dev/null 2>&1; then
        print_header 4 "Docker daemon ready (attempt $i)"
        break
    fi
    sleep 1
done
if ! docker ps > /dev/null 2>&1; then
    print_header 2 "DOCKER DAEMON FAILED" "Could not start Docker daemon. Check /var/log/dockerd.log for details."
    cat /var/log/dockerd.log
    exit 1
fi



# ═══════════════════════════════════════════════════════════════
# HELPER: run a storage variant with c8 coverage
# ═══════════════════════════════════════════════════════════════
run_variant() {
    local variant="$1"
    local storage="$2"
    local extra_node_flags="$3"
    local test_file="${4:-./test_tmp/unit.test.js}"

    suite_start "$variant" "Running tests with DEFAULT_STORAGE=$storage"

    local mocha_bin="./node_modules/.bin/mocha"
    local json_out="./test_tmp/.mocha-stats.json"

    rm -f "$json_out"

    set +e
    DEFAULT_STORAGE="$storage" \
    npx --registry="$VERDACCIO_REGISTRY" c8 \
    --require source-map-support/register \
    --require @babel/register \
    --reporter=lcov \
    "$mocha_bin" \
        --no-bail \
        --reporter mocha-multi \
        --reporter-options spec=-,json="$json_out" \
        --config "$PATCHED_CONFIG" \
        $extra_node_flags \
        "$test_file"
    EXIT_CODE=$?
    set -e

    local n_tests
    n_tests=$(node -e "try{process.stdout.write(String(require('$json_out').stats.tests))}catch(e){process.stdout.write('0')}" 2>/dev/null)

    if [ -z "$n_tests" ] || [ "$n_tests" = "0" ]; then
        echo "Mocha behaved unexpectedly: $n_tests reported tests run, exit code $EXIT_CODE."
        exit 1
    fi

    print_header 4 "Variant '$variant' finished: $n_tests tests run."

    bash ../find-and-move-lcov.sh "$variant" "false" "$EXIT_CODE"
    suite_end "$variant" "$EXIT_CODE"
}

# ═══════════════════════════════════════════════════════════════
# RUN STORAGE VARIANTS
# ═══════════════════════════════════════════════════════════════

# Era 5+: memory + dexie (most recent)
if [ "$HAS_NODE_MEMORY" = "true" ]; then
    run_variant "memory" "memory" "$EXPOSE_GC_FLAG"
fi
if [ "$HAS_NODE_DEXIE" = "true" ]; then
    run_variant "dexie" "dexie" "$EXPOSE_GC_FLAG"
fi

# Era 2-4: lokijs
if [ "$HAS_NODE_LOKIJS" = "true" ]; then
    run_variant "lokijs" "lokijs" "$EXPOSE_GC_FLAG"
fi

# Era 2-3: pouchdb
if [ "$HAS_NODE_POUCHDB" = "true" ]; then
    run_variant "pouchdb" "pouchdb" "$EXPOSE_GC_FLAG"
fi

# Era 3-4: dexie-worker (needs build:workers, already done above)
if [ "$HAS_NODE_DEXIE_WORKER" = "true" ]; then
    run_variant "dexie-worker" "dexie-worker" "$EXPOSE_GC_FLAG"
fi

# Era 3-4: memory-validation
if [ "$HAS_NODE_MEMORY_VALIDATION" = "true" ]; then
    run_variant "memory-validation" "memory-validation" "$EXPOSE_GC_FLAG"
fi

# Era 4+: custom
# NOTE: custom-storage.ts is a template placeholder across the
# entire RxDB history:  export const CUSTOM_STORAGE = { name: 'broken' } as any
# It has no getStorage() method, so running it always produces
# 555+ false failures (TypeError: config.storage.getStorage is not a function).
# We skip it unconditionally — the placeholder is never replaced in
# our pipeline, and this script is idempotent by design.
if [ "$HAS_NODE_CUSTOM" = "true" ]; then
    echo "  custom-storage.ts is the RxDB template placeholder — skipping (no real storage implementation in this repo)"
fi

# Era 4+: remote
if [ "$HAS_NODE_REMOTE" = "true" ]; then
    run_variant "remote" "remote" "$EXPOSE_GC_FLAG"
fi

# Era 3+: foundationdb
# Requires the FoundationDB server (installed in Dockerfile via DEB packages).
# Start the FDB server, run tests, then stop it so it doesn't interfere with
# other variants. The 'foundationdb' npm package is pre-installed globally.
if [ "$HAS_NODE_FOUNDATIONDB" = "true" ]; then
    print_header 2 "Starting FoundationDB server"
    # FDB server is installed by the DEB package. Start it in the background.
    # The default config uses /etc/foundationdb/foundationdb.conf with a
    # single-node cluster on 127.0.0.1:4500.
    if [ -f /usr/lib/foundationdb/fdbmonitor ]; then
        /usr/lib/foundationdb/fdbmonitor --daemonize > /tmp/fdb-start.log 2>&1 || true
    else
        # Fallback: start the fdbserver directly
        mkdir -p /var/lib/foundationdb/data
        fdbserver --listen_address 127.0.0.1:4500 --public_address 127.0.0.1:4500 \
            --datadir /var/lib/foundationdb/data \
            --logdir /var/log/foundationdb \
            > /tmp/fdb-start.log 2>&1 &
    fi
    # Wait for FDB to be ready
    for i in $(seq 1 30); do
        if fdbcli --exec "status" > /dev/null 2>&1; then
            print_header 4 "FoundationDB ready (attempt $i)"
            break
        fi
        sleep 1
    done
    echo "  FoundationDB startup log:"
    head -50 /tmp/fdb-start.log 2>/dev/null || echo "  (no log output)"
    run_variant "foundationdb" "foundationdb" "$EXPOSE_GC_FLAG"
    # Stop FDB server
    if [ -f /usr/lib/foundationdb/fdbmonitor ]; then
        pkill fdbmonitor 2>/dev/null || true
    fi
    pkill fdbserver 2>/dev/null || true
fi

# Era 4+: mongodb
# Requires a MongoDB server. Use the project's own mongodb:start script
# (which specifies the image version). Stop it after so other variants
# (e.g. foundationdb) aren't interfered with.
if [ "$HAS_NODE_MONGODB" = "true" ]; then
    print_header 2 "Starting MongoDB container via npm run mongodb:start"
    npm run mongodb:start > /tmp/mongodb-start.log 2>&1 &
    # Wait for MongoDB to be ready
    for i in $(seq 1 30); do
        if docker exec rxdb-mongodb mongosh --eval "db.runCommand({ ping: 1 })" > /dev/null 2>&1; then
            print_header 4 "MongoDB ready (attempt $i)"
            break
        fi
        sleep 1
    done
    echo "  MongoDB startup log (first 100 lines):"
    head -100 /tmp/mongodb-start.log 2>/dev/null || echo "  (no log output)"
    run_variant "mongodb" "mongodb" "$EXPOSE_GC_FLAG"
    npm run mongodb:stop > /dev/null 2>&1 || true
fi

# ═══════════════════════════════════════════════════════════════
# RUN test:core  (core tests without storage plugin)
# ═══════════════════════════════════════════════════════════════
# Uses DEFAULT_STORAGE=pouchdb (the project's default for core tests).
if [ "$HAS_CORE" = "true" ] && [ -f "./test_tmp/unit/core.node.js" ]; then
    run_variant "core" "pouchdb" "$EXPOSE_GC_FLAG" "./test_tmp/unit/core.node.js"
elif [ "$HAS_CORE" = "true" ] && [ ! -f "./test_tmp/unit/core.node.js" ]; then
    print_header 3 "Skipping core since test file is missing"
fi

# ═══════════════════════════════════════════════════════════════
# RUN test:full  (full node tests) — DISABLED
# ═══════════════════════════════════════════════════════════════
#
# Finding: test:full runs test_tmp/unit/full.node.js which contains
# ZERO describe()/it() blocks across the entire project history.
# It is a plain async script (assert.ok, assertThrows, run()) that
# is designed to be SPAWNED AS A CHILD PROCESS by plugin.test.ts:
#
#   test/unit/plugin.test.ts:
#     describe('full.node.ts', () => {
#       it('full.node.ts should run without errors', async () => {
#         ...
#         const promise = spawn('mocha', [getRootPath() + 'test_tmp/unit/full.node.js']);
#
# So "full.node.ts should run without errors" already passes inside
# every storage variant's plugin.test.js suite. Running test:full
# standalone produces "0 passing (0ms)" and fails — it was never
# meant to be invoked directly in CI.
#
# See: coverage-reloaded commit investigation (2026-07-11)
#      "test:full produces 0 tests — spawned as child process by plugin.test.ts"
#
# if [ "$HAS_FULL" = "true" ] && [ -f "./test_tmp/unit/full.node.js" ]; then
#     run_variant "full" "" "$EXPOSE_GC_FLAG" "./test_tmp/unit/full.node.js"
# elif [ "$HAS_FULL" = "true" ] && [ ! -f "./test_tmp/unit/full.node.js" ]; then
#     print_header 3 "Skipping full since test file is missing"
# fi