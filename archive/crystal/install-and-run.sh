#!/bin/bash
# ── Crystal (PostGraphile) — install-and-run.sh ──────────────
#
# Detects test infrastructure from the checked-out commit's
# package.json scripts and config files. Wraps each workspace's
# test suite with coverage instrumentation.
#
# Coverage injection:
#   Jest:   --coverage --coverageReporters=lcov (built-in)
#   Mocha:  c8 --reporter=lcov npm test
#   Node test runner: c8 --reporter=lcov npm test
#
# ──────────────────────────────────────────────────────────────

export NODE_OPTIONS="--max-old-space-size=8192"  # 8GB
export GRAPHILE_ENV=development

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

set -e

REPOPATH="/coverage_reloaded/repo"
cd "$REPOPATH"

# ══════════════════════════════════════════════════════════════
# 1. Start PostgreSQL
# ══════════════════════════════════════════════════════════════

print_header 1 "Starting PostgreSQL"

PG_BIN="/usr/lib/postgresql/14/bin"
PG_DATA="/tmp/postgres_data"

# Initialize database cluster if it doesn't exist
if [ ! -f "$PG_DATA/PG_VERSION" ]; then
    print_header 3 "Initializing PostgreSQL cluster"
    mkdir -p "$PG_DATA"
    chown postgres:postgres "$PG_DATA"
    su - postgres -c "$PG_BIN/initdb -D $PG_DATA -E UTF-8 --locale=C"

    # Enable WAL for logical replication
    cat > "$PG_DATA/postgresql.conf" <<EOF
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
EOF

    # Allow passwordless local connections for root (needed by scripts/pretest)
    cat > "$PG_DATA/pg_hba.conf" <<EOF
local all all trust
host all all 127.0.0.1/32 trust
host all all ::1/128 trust
EOF
fi

# Start PostgreSQL
su - postgres -c "$PG_BIN/pg_ctl -D $PG_DATA -l /tmp/postgres.log start"

print_header 3 "Waiting for PostgreSQL to accept connections"
for i in $(seq 1 30); do
    if pg_isready -h localhost -U postgres -q; then
        print_header 4 "PostgreSQL is ready"
        break
    fi
    sleep 1
done

if ! pg_isready -h localhost -U postgres -q; then
    print_header 4 "ERROR: PostgreSQL failed to start"
    cat /tmp/postgres.log
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 2. Install dependencies
# ══════════════════════════════════════════════════════════════

print_header 1 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install
elif $IS_NPM_MAIN_PM; then
    npm install
fi

# ══════════════════════════════════════════════════════════════
# 3. Set up database and build (repo-native yarn pretest)
# ══════════════════════════════════════════════════════════════

print_header 1 "Running yarn pretest (tsc + database setup)"

# Set TERM for clear command in scripts/pretest
export TERM=xterm

# Set timezone for consistent snapshot timestamps (snapshots expect CET)
export TZ=Europe/Berlin
# Also set at system level — Node.js reads /etc/localtime, not $TZ
ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime 2>/dev/null || true

export PGUSER=postgres
export PGPASSWORD=
export PGHOST=localhost

# Detect which version of scripts/pretest is checked out
# Old (pre-Oct 2024): requires TEST_DATABASE_URL, LDS_TEST_DATABASE_URL
# New (Oct 2024+): uses OWNER_DATABASE with psql -d flag
if [ -x "scripts/pretest" ] && grep -q 'TEST_DATABASE_URL' scripts/pretest; then
    print_header 3 "Old-style pretest detected — setting TEST_DATABASE_URL"
    export TEST_DATABASE_URL="postgres://postgres@localhost:5432/postgres"
    export LDS_TEST_DATABASE_URL="postgres://postgres@localhost:5432/lds_test"
    export TEST_SIMPLIFY_DATABASE_URL="postgres://postgres@localhost:5432/pg_simplify_inflectors"
else
    export OWNER_DATABASE=postgres
fi

# yarn pretest does: tsc -b && ./scripts/pretest && yarn workspaces foreach --topological run pretest
# Run these individually so a broken scripts/pretest doesn't block the build steps.

# Step 1: TypeScript compilation
print_header 3 "Step 1: tsc -b"
set +e
if $IS_YARN_MAIN_PM; then
    yarn tsc -b
elif $IS_NPM_MAIN_PM; then
    npx tsc -b
fi
TSC_EXIT=$?
set -e
if [ $TSC_EXIT -ne 0 ]; then
    print_header 4 "WARNING: tsc -b failed with exit code $TSC_EXIT"
fi

# Step 2: Database setup via scripts/pretest (skip if it references missing files)
PRETEST_BROKEN=false
if [ -x "scripts/pretest" ]; then
    while IFS= read -r sql_file; do
        if [ ! -f "$sql_file" ]; then
            print_header 4 "scripts/pretest references missing file: $sql_file — skipping"
            PRETEST_BROKEN=true
            break
        fi
    done < <(grep -v '^\s*#' scripts/pretest | grep -oP '(?<=-f )\S+\.sql')
fi

if [ "$PRETEST_BROKEN" = false ]; then
    print_header 3 "Step 2: Database setup (scripts/pretest)"
    set +e
    if [ -x "scripts/pretest" ] && grep -q 'TEST_DATABASE_URL' scripts/pretest; then
        scripts/pretest
    fi
    set -e
else
    print_header 3 "Step 2: scripts/pretest skipped (references missing SQL files)"
fi

# Step 3: Workspace-level pretests (builds, DB setup per-package)
print_header 3 "Step 3: Workspace pretest (topological)"
set +e
if $IS_YARN_MAIN_PM; then
    yarn workspaces foreach --topological run pretest
elif $IS_NPM_MAIN_PM; then
    npm run pretest
fi
WORKSPACE_PRETEST_EXIT=$?
set -e
if [ $WORKSPACE_PRETEST_EXIT -ne 0 ]; then
    print_header 4 "WARNING: workspace pretest failed with exit code $WORKSPACE_PRETEST_EXIT"
fi

# ══════════════════════════════════════════════════════════════
# 3b. Build ruru bundle if missing (required by grafserv tests)
# ══════════════════════════════════════════════════════════════

if [ ! -f "grafast/ruru/bundle/ruru.min.js" ] && [ -d "grafast/ruru" ]; then
    print_header 3 "Building ruru bundle (missing ruru.min.js)"
    (cd grafast/ruru && npx --registry=$WAYPACK_NPM_REGISTRY webpack --mode=production) || \
        print_header 4 "WARNING: ruru bundle build failed — grafserv tests may not run"
fi

# ══════════════════════════════════════════════════════════════
# 4. Enumerate workspaces with tests
# ══════════════════════════════════════════════════════════════

print_header 1 "Enumerating workspaces with tests"

WORKSPACES_WITH_TESTS=()

while IFS= read -r -d '' pkg_file; do
    dir=$(dirname "$pkg_file")

    # Skip root and node_modules
    if [ "$dir" = "." ] || echo "$dir" | grep -q "node_modules"; then
        continue
    fi

    # Read test script
    test_script=$(node -p "require('./$pkg_file').scripts?.test || ''")

    # Skip packages with no test, or test = "true" (no-op)
    if [ -z "$test_script" ] || [ "$test_script" = "true" ] || [ "$test_script" = "undefined" ]; then
        continue
    fi

    WORKSPACES_WITH_TESTS+=("$dir")

    print_header 4 "Found: $dir"
    print_header 4 "  test: $test_script"

done < <(find . -name "package.json" -not -path "*/node_modules/*" -print0 | sort -z)

print_header 3 "Total workspaces with tests: ${#WORKSPACES_WITH_TESTS[@]}"

if [ ${#WORKSPACES_WITH_TESTS[@]} -eq 0 ]; then
    print_header 4 "ERROR: No workspaces with tests found"
    exit 1
fi

# ══════════════════════════════════════════════════════════════
# 5. Run tests with coverage
# ══════════════════════════════════════════════════════════════

print_header 1 "Running tests with coverage"

OVERALL_EXIT=0

for workspace in "${WORKSPACES_WITH_TESTS[@]}"; do
    suite_name=$(echo "$workspace" | sed 's|^\./||' | sed 's|/|_|g')

    # Read test script and config for this workspace
    cd "$workspace"

    TEST_SCRIPT=$(node -p "require('./package.json').scripts?.test || ''")
    HAS_JEST_CONFIG=$(node -p "!!require('fs').existsSync('./jest.config.js') || !!require('fs').existsSync('./jest.config.cjs')")
    HAS_MOCHA_CONFIG=$(node -p "!!require('fs').existsSync('./.mocharc.yml') || !!require('fs').existsSync('./.mocharc.js')")

    cd "$REPOPATH"

    print_header 2 "Workspace: $workspace"
    print_header 4 "  test: $TEST_SCRIPT"
    print_header 4 "  jest.config: $HAS_JEST_CONFIG, .mocharc: $HAS_MOCHA_CONFIG"

    # Determine coverage strategy based on package.json scripts and config files
    if echo "$TEST_SCRIPT" | grep -qE "\bjest\b"; then
        # Check if there are any test files before running
        TEST_FILES=$(cd "$workspace" && npx --registry=$WAYPACK_NPM_REGISTRY jest --listTests 2>/dev/null)
        if [ -z "$TEST_FILES" ]; then
            print_header 4 "No test files found in $workspace — skipping"
            cd "$REPOPATH"
            continue
        fi

        # Extract pre-steps from test script (e.g. "yarn test:install-schema" from
        # "yarn test:install-schema && jest -i") and run them before jest.
        PRE_STEPS=$(echo "$TEST_SCRIPT" | sed -n 's/\(.*\)&&\s*jest.*/\1/p' | sed 's/\s*$//')
        if [ -n "$PRE_STEPS" ]; then
            print_header 4 "Running pre-test steps: $PRE_STEPS"
            set +e
            (cd "$workspace" && eval "$PRE_STEPS")
            PRE_STEP_EXIT=$?
            set -e
            if [ $PRE_STEP_EXIT -ne 0 ]; then
                print_header 4 "WARNING: pre-test steps failed with exit code $PRE_STEP_EXIT"
            fi
        fi

        # Jest — inject --coverage (works with or without jest.config)
        suite_start "$suite_name" "Running Jest with coverage in $workspace"
        set +e
        (cd "$workspace" && npx --registry=$WAYPACK_NPM_REGISTRY jest --coverage --coverageReporters=lcov --maxWorkers=2)
        EXIT=$?
        set -e
        # Only collect coverage if tests actually ran (coverage file exists with data)
        if [ -f "$workspace/coverage/lcov.info" ] && [ -s "$workspace/coverage/lcov.info" ]; then
            bash ../find-and-move-lcov.sh "$suite_name" "false" "$EXIT"
        else
            print_header 4 "No coverage produced for $workspace (tests may not have run)"
        fi
        suite_end "$suite_name" "$EXIT"

    elif echo "$TEST_SCRIPT" | grep -qE "\bmocha\b" || [ "$HAS_MOCHA_CONFIG" = "true" ]; then
        # Mocha — wrap with c8 from Verdaccio
        suite_start "$suite_name" "Running Mocha with c8 coverage in $workspace"
        set +e
        (
            cd "$workspace"

            # Fix for vendored graphql-js ESM/CJS conflict:
            # .mocharc.yml uses --loader=ts-node/esm/transpile-only which fails because
            # ts-node's ESM loader classifies .ts files as CJS (no "type":"module" in
            # package.json), skips transformation, and raw TS hits Node's CJS loader.
            # Replace with --require=ts-node/register/transpile-only (CJS register hook)
            # which transforms all .ts files regardless of module classification.
            if grep -q "loader=ts-node/esm" .mocharc.yml 2>/dev/null; then
                cp .mocharc.yml .mocharc.yml.bak
                sed -i 's|loader=ts-node/esm/transpile-only|require=ts-node/register/transpile-only|' .mocharc.yml
            fi

            npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov npx --registry=$WAYPACK_NPM_REGISTRY npm test
        )
        EXIT=$?
        set -e

        # Restore original .mocharc.yml if we patched it
        [ -f "$workspace/.mocharc.yml.bak" ] && mv "$workspace/.mocharc.yml.bak" "$workspace/.mocharc.yml"
        bash ../find-and-move-lcov.sh "$suite_name" "false" "$EXIT"
        suite_end "$suite_name" "$EXIT"

    elif echo "$TEST_SCRIPT" | grep -qE "node\s+--experimental-strip-types\s+--test"; then
        # Node.js test runner — wrap with c8
        suite_start "$suite_name" "Running Node.js test runner with c8 coverage in $workspace"
        set +e
        (cd "$workspace" && npx --registry=$VERDACCIO_REGISTRY c8 --reporter=lcov npx --registry=$WAYPACK_NPM_REGISTRY npm test)
        EXIT=$?
        set -e
        bash ../find-and-move-lcov.sh "$suite_name" "false" "$EXIT"
        suite_end "$suite_name" "$EXIT"

    fi

    # Track overall exit code (0/1 = ok, >1 = crash)
    if [ $EXIT -gt 1 ]; then
        OVERALL_EXIT=$EXIT
    fi
done

# ══════════════════════════════════════════════════════════════
# 6. Summary
# ══════════════════════════════════════════════════════════════

print_header 1 "Test run complete"
print_header 3 "Workspaces with tests: ${#WORKSPACES_WITH_TESTS[@]}"
print_header 3 "Overall exit code: $OVERALL_EXIT"

exit $OVERALL_EXIT
