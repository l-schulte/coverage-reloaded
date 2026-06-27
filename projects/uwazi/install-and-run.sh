#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

cd /coverage_reloaded/repo

if [ ! -f package.json ]; then
    print_header 2 "NOT APPLICABLE" "No package.json at this commit, no test infrastructure to run"
    exit 2
fi

print_header 2 "Installing dependencies"

if $IS_YARN_MAIN_PM; then
    yarn install --ignore-engines
else
    print_header 2 "No main package manager detected... raising error."
    exit 1
fi

print_header 2 "Detecting test infrastructure"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.test || '')")

print_header 4 "test script:          $TEST_SCRIPT"

if [ -z "$TEST_SCRIPT" ] || echo "$TEST_SCRIPT" | grep -q "Error: no test specified"; then
    print_header 2 "NOT APPLICABLE" "No test script found at this commit, no test infrastructure to run"
    exit 2
fi

# ── Start infrastructure services ──────────────────────────────────────
#
# We always start a real mongod (installed in the Dockerfile from the
# official MongoDB 7.0 repo).  Early commits use mongodb-memory-server which
# normally tries to download its own MongoDB 4.x binary — but those old
# binaries are no longer available from MongoDB's CDN (404 / broken archive).
#
# Solution: set MONGOMS_SYSTEM_BINARY to point mongodb-memory-server at the
# system-installed mongod.  This works for both eras:
#   - Early commits: mongodb-memory-server uses the system mongod via this env var
#   - Later commits: tests connect directly to localhost:27017
# The version mismatch (4.x expected vs 7.0 installed) is harmless for the
# test workloads (CRUD operations on temporary databases).

print_header 3 "Starting MongoDB"
mkdir -p /tmp/mongodb
mongod --dbpath /tmp/mongodb --logpath /tmp/mongodb/mongod.log --fork
print_header 4 "MongoDB started"

# Tell mongodb-memory-server to use the system binary instead of downloading
export MONGOMS_SYSTEM_BINARY=/usr/bin/mongod
# Disable postinstall download attempts
export MONGOMS_DISABLE_POSTINSTALL=1

print_header 3 "Starting Redis"
redis-server --daemonize yes
print_header 4 "Redis started"

# ── Run tests with Jest coverage ────────────────────────────────────────
#
# Uwazi uses Jest throughout its entire history.  No c8 or nyc is ever in
# devDependencies.  We use Jest's built-in --coverage with lcov reporter.
#
# The project's own test script evolved as:
#   node ./node_modules/.bin/jest                          (earliest)
#   node --max-http-header-size 20000 ./node_modules/.bin/jest  (Sep 2020–Oct 2022)
#   node ./node_modules/.bin/jest -w=50%                   (Oct 2022–Aug 2023)
#   node --no-experimental-fetch ./node_modules/.bin/jest -w=50%  (Aug 2023+)
#
# We replace -w=50% with --runInBand (serial execution for container stability)
# and add --coverage.  The --max-http-header-size and --no-experimental-fetch
# flags are server/workaround flags not needed for Jest's test execution.
#
# --runInBand avoids PID exhaustion and port conflicts in the constrained
# container environment.

print_header 2 "Running unit/integration tests with Jest coverage"

set +e
node ./node_modules/.bin/jest --coverage --coverageReporters=lcov --runInBand
TEST_EXIT=$?
set -e

print_header 2 "Collecting coverage reports"
bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"

print_header 1 "Uwazi coverage run complete"
