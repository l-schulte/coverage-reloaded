#!/bin/bash

set -e

source /coverage_reloaded/logging.sh
source /coverage_reloaded/has-option.sh

# Raise the V8 heap ceiling for the whole run.  Uwazi's full test suite with
# istanbul coverage instrumentation uses ~2.7 GB of live objects; V8's code
# space (compiled regexes from istanbul) also grows large in --runInBand mode.
# 16 GB gives enough headroom for both old space and code space.
export NODE_OPTIONS="--max-old-space-size=16384"

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

# ── Patch mongodb-memory-server for mongod 4.4+ JSON logging ─────
#
# MMS 6.x expects mongod's plain-text "waiting for connections on port N"
# but mongod 4.4+ outputs JSON: {"msg":"Waiting for connections",...}.
# The readiness regex never matches, so MMS hangs forever.  Relax the
# regex to just "waiting for connections" so it matches both formats.
# Only applies when mongodb-memory-server-core is actually installed.

MMS_INSTANCE_JS="node_modules/mongodb-memory-server-core/lib/util/MongoInstance.js"
if [ -f "$MMS_INSTANCE_JS" ]; then
    if grep -q 'waiting for connections on port' "$MMS_INSTANCE_JS"; then
        print_header 4 "Patching MMS stdout regex for mongod 4.4+ JSON logging"
        sed -i 's|/waiting for connections on port/|/waiting for connections/|' "$MMS_INSTANCE_JS"
    fi
fi

# ── Patch winston to suppress exitOnError ──────────────────────
#
# Winston 3.x defaults exitOnError to true.  When an uncaught exception fires
# during Jest teardown (after all tests pass), the ExceptionHandler's
# setTimeout(gracefulExit, 3000) calls process.exit(1) before Jest can write
# lcov.info.  Disabling exitOnError prevents this without touching process
# internals.  Only applies when winston is actually installed.

WINSTON_LOGGER_JS="node_modules/winston/lib/winston/logger.js"
if [ -f "$WINSTON_LOGGER_JS" ]; then
    if grep -q 'exitOnError = true' "$WINSTON_LOGGER_JS"; then
        print_header 4 "Patching winston exitOnError to prevent premature process.exit(1)"
        sed -i 's/exitOnError = true/exitOnError = false/g' "$WINSTON_LOGGER_JS"
    fi
fi

print_header 2 "Detecting test infrastructure"

TEST_SCRIPT=$(node -p "p=require('./package.json').scripts; (p.test || '')")

print_header 4 "test script:          $TEST_SCRIPT"

if [ -z "$TEST_SCRIPT" ] || echo "$TEST_SCRIPT" | grep -q "Error: no test specified"; then
    print_header 2 "NOT APPLICABLE" "No test script found at this commit, no test infrastructure to run"
    exit 2
fi

# ── Docker-in-Docker for Elasticsearch ─────────────────────────
#
# Uwazi's tests connect to Elasticsearch at localhost:9200 in every era
# (their CI always provisioned it as a service).  We start a nested Docker
# daemon — docker-run.sh passes --privileged via the dind.project label, same
# as rxdb/polkadot-apps — and run ES built from the project's own
# elastic-icu-*.Dockerfile when the commit has one (2022-01-04+), otherwise a
# generic elasticsearch:7.10.1 matching the pre-2022 CI.  Images flow through
# the docker-cache pull-through mirror on mining-net, so the first pull per
# version is fetched from Docker Hub and cached for every later run.

print_header 3 "Starting Docker daemon"
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
    print_header 2 "DOCKER DAEMON FAILED" "Could not start Docker daemon. Check /var/log/dockerd.log for details."
    cat /var/log/dockerd.log
    exit 1
fi

print_header 3 "Starting Elasticsearch"
ELASTIC_DOCKERFILE=""
for f in elastic-icu-*.Dockerfile; do
    if [ -f "$f" ]; then
        ELASTIC_DOCKERFILE="$f"
        break
    fi
done

ES_VERSION=""
if [ -n "$ELASTIC_DOCKERFILE" ]; then
    print_header 4 "Building Elasticsearch from $ELASTIC_DOCKERFILE"
    docker build -t uwazi-es - < "$ELASTIC_DOCKERFILE"
    ES_IMAGE=uwazi-es
    ES_VERSION=$(sed -n 's/^FROM elasticsearch:\([0-9][0-9.]*\).*/\1/p' "$ELASTIC_DOCKERFILE")
else
    # Match the Elasticsearch version the project's own CI pinned for this era
    # instead of a hardcoded generic image.  Scan GitHub Actions first, then
    # CircleCI (Uwazi used CircleCI before migrating to GitHub Actions).
    CI_ES_IMAGE=""
    for wf in .github/workflows/ci_*unit*test*.yml .github/workflows/*.yml .circleci/config.yml; do
        [ -f "$wf" ] || continue
        CI_ES_IMAGE=$(grep -E "image:.*elasticsearch" "$wf" | head -1 | sed 's/.*image:[[:space:]]*//')
        if [ -n "$CI_ES_IMAGE" ]; then
            break
        fi
    done
    if [ -n "$CI_ES_IMAGE" ]; then
        ES_IMAGE=$CI_ES_IMAGE
        ES_VERSION=$(basename "$CI_ES_IMAGE" | sed 's/.*:\([0-9][0-9.]*\).*/\1/')
        print_header 4 "No elastic-icu Dockerfile at this commit — using CI-pinned $CI_ES_IMAGE"
        docker pull "$CI_ES_IMAGE"
    else
        # No CI config found — use a reasonable default.  ES 7.10.1 is the
        # last 7.x release; for older eras that pinned 7.4.x via CircleCI,
        # the detection loop above should have matched.
        print_header 4 "No elastic-icu Dockerfile or CI ES image at this commit — using generic elasticsearch:7.10.1"
        docker pull elasticsearch:7.10.1
        ES_IMAGE=elasticsearch:7.10.1
        ES_VERSION=7.10.1
    fi
fi

# bootstrap.system_call_filter was removed in Elasticsearch 8 (ES 8.18 from the
# project's own elastic-icu Dockerfile dies at startup if it is set), so gate it
# to the ES 7.x line.  Missing version means an unknown/unparsed image — assume
# the ES 7 flag for safety (all pre-2022 eras are 7.x).
ES_MAJOR=$(echo "${ES_VERSION:-7}" | cut -d. -f1)

# xpack.security.enabled defaults to false on ES 7 and is fatal on the OSS
# flavor (no xpack module — the CI-pinned 2021-era images crash at startup).
# ES 8 enables security by default, so the flag is only needed there — matching
# the project's own CI, which passes it for ES 8.18.
ES_DOCKER_FLAGS=(-e discovery.type=single-node)
if [ "$ES_MAJOR" = "8" ]; then
    ES_DOCKER_FLAGS+=(-e xpack.security.enabled=false)
fi
if [ "$ES_MAJOR" = "7" ]; then
    ES_DOCKER_FLAGS+=(-e bootstrap.system_call_filter=false)
fi
ES_DOCKER_FLAGS+=(-e "ES_JAVA_OPTS=-Xms2g -Xmx2g")

docker run -d --name uwazi-es -p 9200:9200 "${ES_DOCKER_FLAGS[@]}" "$ES_IMAGE"

print_header 4 "Waiting for Elasticsearch on localhost:9200 (up to 480s)"
ES_READY=false
for i in $(seq 1 240); do
    if curl -fsS -o /dev/null http://localhost:9200/_cluster/health; then
        print_header 4 "Elasticsearch ready (attempt $i/240)"
        ES_READY=true
        break
    fi
    if (( i % 30 == 0 )); then
        print_header 4 "ES still not ready (attempt $i/240), recent container state:"
        docker ps --filter name=uwazi-es --format '  | {{.Status}}'
        docker logs --tail=3 uwazi-es 2>&1 | sed 's/^/  | /'
    fi
    sleep 2
done
if [ "$ES_READY" != "true" ]; then
    print_header 2 "ELASTICSEARCH NOT READY" "Dumping diagnostics to see where startup stalled"
    print_header 4 "Container state:"
    docker inspect uwazi-es --format '  | Status={{.State.Status}} Running={{.State.Running}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}} Restarts={{.RestartCount}} Error={{.State.Error}}'
    print_header 4 "Final health check (verbose):"
    curl -v --max-time 5 http://localhost:9200/_cluster/health 2>&1 | head -20
    print_header 4 "Last 80 lines of ES log (what it logged before timing out):"
    docker logs --tail=80 uwazi-es 2>&1 | sed 's/^/  | /'
    print_header 2 "NOTE" "ES-dependent suites will fail (partial coverage). Full ES log kept by docker, dump via: docker logs uwazi-es"
fi

# ── MinIO (S3) ─────────────────────────────────────────────────
#
# Uwazi's S3 storage tests (Aug 2022+, files/specs/storage.spec.ts and
# files.v2/.../S3FileStorage.spec.ts) connect to MinIO at localhost:9000 with
# minioadmin/minioadmin and create the 'uwazi-development' bucket themselves.
# Their CI always provisions a minio service alongside ES.  We only start it
# when the checked-out commit actually has S3 storage infrastructure, to avoid
# pulling the image for older eras that never use it.

print_header 3 "Detecting S3 storage tests"
if test -f app/api/files/S3Storage.ts \
   || test -f app/api/files.v2/infrastructure/S3FileStorage.ts \
   || test -f app/api/core/infrastructure/files/S3FileStorage.ts; then
    print_header 4 "S3 storage present at this commit — starting MinIO"
    docker run -d --name uwazi-minio -p 9000:9000 \
        -e MINIO_ROOT_USER=minioadmin \
        -e MINIO_ROOT_PASSWORD=minioadmin \
        minio/minio server /data --console-address :9001
    print_header 4 "Waiting for MinIO on localhost:9000 (up to 120s)"
    MINIO_READY=false
    for i in $(seq 1 60); do
        if curl -fsS -o /dev/null http://localhost:9000/minio/health/live; then
            print_header 4 "MinIO ready (attempt $i/60)"
            MINIO_READY=true
            break
        fi
        if (( i % 15 == 0 )); then
            print_header 4 "MinIO still not ready (attempt $i/60)"
            docker ps --filter name=uwazi-minio --format '  | {{.Status}}'
        fi
        sleep 2
    done
    if [ "$MINIO_READY" != "true" ]; then
        print_header 2 "MINIO NOT READY" "S3-dependent suites will fail (partial coverage)."
        docker inspect uwazi-minio --format '  | Status={{.State.Status}} ExitCode={{.State.ExitCode}} Error={{.State.Error}}'
        docker logs --tail=30 uwazi-minio 2>&1 | sed 's/^/  | /'
    fi
else
    print_header 4 "No S3 storage at this commit — skipping MinIO"
fi

# ── MongoDB ────────────────────────────────────────────────────
#
# mongodb-memory-server era (until Aug 2022): tests spawn their own mongod on
# random ports via MONGOMS_SYSTEM_BINARY.  The system 7.0 mongod cannot be
# brought up by those memory-server versions, so we point them at a bundled
# MongoDB 4.4.8 binary instead.  MMS 6.x's readiness regex is patched
# (see post-install block above) because mongod 4.4+ outputs JSON logs
# instead of the plain-text format MMS expects.
#
# Real-mongod era (Aug 2022+): tests connect to localhost:27017 and use
# transactions, so mongod must run as a replica set.  We initialize a
# single-node set, mirroring the script in the project's own .github/ci/Dockerfile.

print_header 3 "Starting MongoDB"
mkdir -p /tmp/mongodb
mongod --dbpath /tmp/mongodb --logpath /tmp/mongodb/mongod.log --fork --replSet uwazi_replica_set
print_header 4 "MongoDB started"

print_header 3 "Initializing MongoDB replica set"
MONGO_URI="mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=30000"
for i in $(seq 1 5); do
    mongosh "$MONGO_URI" --quiet --eval 'rs.initiate({_id: "uwazi_replica_set", members: [{_id: 0, host: "127.0.0.1:27017"}]})' && break
    print_header 4 "rs.initiate not confirmed (attempt $i), retrying"
    sleep 2
done
for i in $(seq 1 30); do
    if mongosh "$MONGO_URI" --quiet --eval 'db.hello().isWritablePrimary' | grep -q true; then
        print_header 4 "MongoDB replica set PRIMARY (attempt $i)"
        break
    fi
    sleep 1
done

# Tell mongodb-memory-server to use the bundled 4.4.8 binary instead of
# downloading its own (old 4.x binaries are no longer on the CDN).
export MONGOMS_SYSTEM_BINARY=/usr/local/bin/mongod-4.4.8
export MONGOMS_DISABLE_POSTINSTALL=1

print_header 3 "Starting Redis"
# The downloadRedis jest global setup (Oct 2021 – Sep 2022 era) compiles
# redis-stable from source and aborts the whole run when that make fails
# (flaky).  Drop a redis-server binary where it expects it so it early-returns.
if [ -f app/api/utils/downloadRedis.js ]; then
    print_header 4 "downloadRedis era — dropping redis-server binary for the global setup, no global daemon"
    mkdir -p redis-bin/redis-stable/src
    cp "$(command -v redis-server)" redis-bin/redis-stable/src/redis-server
    # This era's tests manage their own redis instances (RedisServer spawns
    # redis-bin/redis-stable/src/redis-server --port <p> and asserts on
    # "unavailable -> comes back").  A pre-bound daemon on 6379 breaks that
    # control, so we deliberately do NOT start one here — same as the project's
    # own CI, which ran no redis service in this era.
else
    # Later eras connect to config.redis (localhost:6379) directly; their CI
    # provisioned a redis service container.  A local daemon is our equivalent.
    print_header 4 "No downloadRedis global setup — starting redis on 6379 (CI service equivalent)"
    redis-server --daemonize yes
fi
print_header 4 "Redis started"

# ── Run tests with Jest coverage ───────────────────────────────
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
# --maxWorkers=10 caps parallel workers to avoid PID exhaustion and port
# conflicts, while still isolating V8's compilation-cache per worker process.
# --runInBand is intentionally avoided: it forces all ~460 suites into a single
# V8 heap, where a Node 16-19 compilation-cache leak (jest#12820) accumulates
# unbounded and OOMs at ~3 GB.
# --forceExit makes Jest terminate even if a suite
# leaves open handles (ES/mongo/redis connections) so the lcov report is
# written instead of the run hitting the 90-minute timeout.

suite_start "unit" "Running unit/integration tests with Jest coverage"

set +e
node $COMPILATION_CACHE_FLAG ./node_modules/.bin/jest --coverage --coverageReporters=lcov --maxWorkers=10 --forceExit --testTimeout=60000
TEST_EXIT=$?
set -e

bash /coverage_reloaded/find-and-move-lcov.sh "unit" "false" "$TEST_EXIT"
suite_end "unit" "$TEST_EXIT"

print_header 1 "Uwazi coverage run complete"
