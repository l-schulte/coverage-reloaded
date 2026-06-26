#!/bin/bash

set -e

source /coverage_reloaded/logging.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

# Increase Node.js heap to prevent OOM during build and Jest coverage collection.
export NODE_OPTIONS="--max-old-space-size=12288"

print_header 2 "Installing dependencies"

CI= yarn install

# Yarn 3's node-modules linker hoists binaries to the root node_modules/.bin,
# but doesn't add it to PATH when running workspace scripts. Add it explicitly.
export PATH="/coverage_reloaded/repo/node_modules/.bin:$PATH"

HAS_WORKSPACES_FOREACH=$(yarn workspaces foreach --help >/dev/null 2>&1 && echo "yes" || echo "no")


print_header 2 "Running tests with coverage"

# nyc can't combine coverage across yarn workspaces, so rely on each workspace's
# own lcov.info and collect them afterwards.

# Restore .env from .env.example so @open-condo/config can load DB/Redis/cookie vars.
# The config loader reads .env but doesn't override existing env vars, so explicit
# exports below take precedence.
if [ -f .env.example ] && [ ! -f .env ]; then
    cp .env.example .env
fi

# Schema tests need Redis for the Bull task queue (imported at module load in jest.setup.js).
print_header 3 "Starting Redis for Bull task queue..."
redis-server --daemonize yes --port 6379
export REDIS_URL=redis://127.0.0.1:6379
export WORKER_REDIS_URL=redis://127.0.0.1:6379

# Schema tests need PostgreSQL for the KeystoneJS adapter.
print_header 3 "Starting PostgreSQL for KeystoneJS adapter..."

# Start PostgreSQL — Debian's pg_ctlcluster handles existing clusters
pg_ctlcluster 13 main start 2>/dev/null || pg_ctlcluster 14 main start 2>/dev/null || pg_ctlcluster 15 main start 2>/dev/null || service postgresql start 2>/dev/null || true

# Wait for PostgreSQL to be ready
for i in $(seq 1 30); do
    if pg_isready -q 2>/dev/null; then break; fi
    sleep 0.5
done

# Set postgres password via Unix socket so TCP connections (used by Keystone) work.
su - postgres -c "psql -c \"ALTER USER postgres PASSWORD 'postgres';\"" || echo "WARNING: could not set postgres password"

# Create database — Knex adapter needs it before keystone.connect() can sync schema.
su - postgres -c "psql -c \"CREATE DATABASE main;\"" 2>/dev/null || su - postgres -c "psql -c \"CREATE DATABASE main WITH OWNER postgres;\"" 2>/dev/null || echo "WARNING: database 'main' may already exist"
export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1/main

# Use fake address suggestions to avoid needing ADDRESS_SUGGESTIONS_CONFIG (serverSideAddressApi.js throws otherwise).
export FAKE_ADDRESS_SUGGESTIONS=true

# Run database migrations — KeystoneJS v5's Knex adapter doesn't auto-create tables,
# so the project uses kmigrator.py (Django-based) to manage the schema.
print_header 3 "Running database migrations..."
yarn workspace @app/condo migrate

# ── Build the Admin UI ──────────────────────────────────────────────────────
# Schema tests connect to a real Keystone server at :3000. The AdminUIApp
# requires built artifacts (dist/admin) which are produced by `keystone build`.
# We run the full project build pipeline to produce them.
print_header 3 "Building Admin UI (keystone build)..."
yarn workspace @app/condo build

# ── Start the Keystone server ───────────────────────────────────────────────
# Start the KeystoneJS server in the background on port 3000.
# The server will serve the GraphQL API and Admin UI that the schema tests
# connect to via HTTP (real client mode).
print_header 3 "Starting Keystone server on port 3000..."
export NODE_ENV=test
export PORT=3000
export SERVER_URL=http://localhost:3000
export COOKIE_SECRET=random
export DISABLE_LOGGING=true

yarn workspace @app/condo start &
KEYSTONE_PID=$!

# Wait for the server to be ready by polling the GraphQL endpoint
print_header 3 "Waiting for Keystone server to be ready..."
for i in $(seq 1 60); do
    if curl -s http://localhost:3000/admin/api >/dev/null 2>&1; then
        print_header 3 "Keystone server is ready"
        break
    fi
    if ! kill -0 $KEYSTONE_PID 2>/dev/null; then
        echo "ERROR: Keystone server died during startup"
        exit 1
    fi
    sleep 2
done

# ── Run tests ───────────────────────────────────────────────────────────────
# Run tests sequentially (--runInBand) — parallel workers cause duplicate key errors.
# Tests connect to the real Keystone server at http://localhost:3000.

# Set environment variables:

export DEFAULT_TEST_USER_IDENTITY="user@example.com"
export DEFAULT_TEST_USER_SECRET="password"

set +e
if [ "$HAS_WORKSPACES_FOREACH" = "yes" ]; then
    print_header 3 "Using yarn workspaces foreach to run tests with coverage..."
    yarn workspaces foreach run test --coverage --runInBand --forceExit
else
    print_header 3 "Using yarn workspaces run to run tests with coverage..."
    # Older yarn lacks 'workspaces foreach'; use 'workspaces run' instead.
    # --runInBand avoids duplicate key errors; --forceExit handles KeystoneJS open handles.
    yarn workspaces run test --coverage --runInBand --forceExit
fi
TEST_EXIT=$?
set -e

# ── Stop the Keystone server ────────────────────────────────────────────────
print_header 3 "Stopping Keystone server..."
kill $KEYSTONE_PID 2>/dev/null || true
wait $KEYSTONE_PID 2>/dev/null || true

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "true" "$TEST_EXIT"

print_header 1 "condo coverage run complete"