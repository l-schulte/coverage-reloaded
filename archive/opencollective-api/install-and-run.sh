#!/bin/bash
# ── Open Collective API — install-and-run.sh ──────────────────
#
# Mocha + nyc (Babel istanbul plugin) coverage collection.
# Requires PostgreSQL for test database.
#
# ──────────────────────────────────────────────────────────────

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

set -e

REPOPATH="/coverage_reloaded/repo"
cd "$REPOPATH"

# ══════════════════════════════════════════════════════════════
# 1. Start PostgreSQL
# ══════════════════════════════════════════════════════════════

print_header 1 "Starting PostgreSQL"

PG_BIN="/usr/lib/postgresql/16/bin"
PG_DATA="/tmp/postgres_data"

export PATH="$PG_BIN:$PATH"

# Initialize database cluster if it doesn't exist
if [ ! -f "$PG_DATA/PG_VERSION" ]; then
    print_header 3 "Initializing PostgreSQL cluster"
    mkdir -p "$PG_DATA"
    chown postgres:postgres "$PG_DATA"
    su - postgres -c "$PG_BIN/initdb -D $PG_DATA -E UTF-8 --locale=C"

    # Trust auth for local connections (project uses passwordless connections)
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
# 2. Create PostgreSQL user
# ══════════════════════════════════════════════════════════════

print_header 1 "Creating PostgreSQL user"

su - postgres -c "psql -c \"CREATE USER opencollective WITH SUPERUSER;\"" 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# 2b. PostgreSQL connection environment
# ══════════════════════════════════════════════════════════════

print_header 3 "Configuring PostgreSQL connection environment"

# maintenancedb URL has no username; pg uses PGUSER as fallback so point it at the initdb superuser
export PGUSER=postgres
export PG_USERNAME=opencollective
export PG_HOST=127.0.0.1
export PG_PORT=5432

# ══════════════════════════════════════════════════════════════
# 3. Install dependencies
# ══════════════════════════════════════════════════════════════

print_header 1 "Installing dependencies"

# Skip postinstall — different eras check different variables:
#   2020 era:  NODE_ENV=ci or NODE_ENV=circleci
#   2021+ era: OC_ENV=ci
#   2025+ era: SKIP_POSTINSTALL=1
# Set all three during npm install, then unset before running project scripts
# to prevent OC_ENV=ci from contaminating NODE_CONFIG_ENV (see server/env.js).
export OC_ENV=ci
export SKIP_POSTINSTALL=1
export HUSKY=0
# For 2020 era postinstall (checks NODE_ENV=ci) — pass via subshell to avoid
# polluting the parent shell's NODE_ENV.
(env NODE_ENV=ci npm install) || { print_header 4 "ERROR: npm install failed"; exit 1; }

# Unset postinstall skip vars — they must NOT be visible to project scripts
# (migrations, tests) because server/env.js uses OC_ENV to set NODE_CONFIG_ENV,
# which would cause Sequelize to load config/ci.json (opencollective_dvl) instead
# of config/test.json (opencollective_test).
unset OC_ENV
unset SKIP_POSTINSTALL

# ══════════════════════════════════════════════════════════════
# 3b. Conditional Sequelize downgrade for ARRAY(ENUM) sync bug
# ══════════════════════════════════════════════════════════════

SEQUELIZE_VERSION=$(node -p "require('./node_modules/sequelize/package.json').version" 2>/dev/null || echo "0")
SEQUELIZE_MAJOR=$(echo "$SEQUELIZE_VERSION" | cut -d. -f1)
SEQUELIZE_MINOR=$(echo "$SEQUELIZE_VERSION" | cut -d. -f2)

if [ "$SEQUELIZE_MAJOR" -ge 6 ] && [ "$SEQUELIZE_MINOR" -ge 20 ]; then
    HAS_ARRAY_ENUM=$(grep -rl "ARRAY.*ENUM\|DataTypes\.ARRAY.*ENUM" server/models/ --include="*.js" --include="*.ts" 2>/dev/null | head -1)
    if [ -n "$HAS_ARRAY_ENUM" ]; then
        print_header 3 "Downgrading Sequelize to 6.29.1 (cyclic FK + ENUM sync bug — sequelize#15522)"
        npm install --no-save sequelize@6.29.1
    fi
fi

# ══════════════════════════════════════════════════════════════
# 4. Create test database for db:setup
# ══════════════════════════════════════════════════════════════

print_header 1 "Creating test database"

# Create the empty database. db_setup.js (sequelize.sync force:true) handles
# all schema creation — pg_restore is not needed and causes enum-drop conflicts.
DBNAME="opencollective_test"
DBUSER="opencollective"

su - postgres -c "dropdb --if-exists $DBNAME" 2>/dev/null || true
su - postgres -c "createdb -O $DBUSER $DBNAME"

# Enable PostGIS extension (project's db_restore.sh does this unconditionally)
su - postgres -c "psql -d $DBNAME -c \"CREATE EXTENSION IF NOT EXISTS postgis;\"" 2>/dev/null || true

# Create role (db_setup.js uses this to connect as the application user)
su - postgres -c "psql -d $DBNAME -c \"CREATE ROLE $DBUSER WITH login SUPERUSER;\"" 2>/dev/null || true
su - postgres -c "psql -d $DBNAME -c \"ALTER DATABASE $DBNAME OWNER TO $DBUSER;\""

# Enable extensions required by the project
su - postgres -c "psql -d $DBNAME -c \"CREATE EXTENSION IF NOT EXISTS btree_gist;\""
su - postgres -c "psql -d $DBNAME -c \"CREATE EXTENSION IF NOT EXISTS pg_trgm;\""

# Pre-create enum types — _syncModelsWithCyclicReferences creates tables before
# enum types, causing "type does not exist". Creating them here ensures Pass 1 works.
print_header 3 "Pre-creating PostgreSQL enum types"

# Find all ENUM('...') definitions in model files.
# Matches: ENUM('a','b'), ARRAY(ENUM('a','b')), ENUM({ values: ['a','b'] })
# Extracts quoted string values and builds CREATE TYPE statements.
find server/models/ -name '*.ts' -o -name '*.js' | while read -r f; do
    tbl=$(basename "$f" | sed 's/\.\(ts\|js\)$//')
    grep -oP "ENUM\([^)]*\)" "$f" 2>/dev/null | while read -r enum_def; do
        vals=$(echo "$enum_def" | grep -oP "'[^']+'" | tr -d "'" | paste -sd, -)
        [ -z "$vals" ] && continue
        # Column name: look at line above for "colName: {"
        col=$(grep -B1 "$enum_def" "$f" 2>/dev/null | grep -oP '^\s*\w+' | head -1 | xargs)
        [ -z "$col" ] && col="unknown"
        type="enum_${tbl}_${col}"
        su - postgres -c "psql -d $DBNAME -c \"CREATE TYPE IF NOT EXISTS \\\"public\\\".\\\"${type}\\\" AS ENUM(${vals});\"" 2>/dev/null || true
    done
done

# ══════════════════════════════════════════════════════════════
# 5. Set up database schema
# ══════════════════════════════════════════════════════════════

print_header 1 "Setting up database schema"

NODE_ENV=test npm run db:setup

# ══════════════════════════════════════════════════════════════
# 6. Run tests with coverage
# ══════════════════════════════════════════════════════════════

print_header 1 "Running tests with coverage"

suite_start "unit" "Running test suite with coverage"

set +e

# The test runner is always mocha (configured via .mocharc.json).
# Wrap with nyc --all for consistent coverage measurement across all eras.
NODE_ENV=test TZ=UTC npx --registry="$WAYPACK_REGISTRY_CURRENT" nyc --all node_modules/.bin/mocha

TEST_EXIT=$?

set -e

bash ../find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

suite_end "unit" "$TEST_EXIT"
