# Condo Test Setup Strategy for `install-and-run.sh`

> Based on analysis of 55 diffs of `.github/workflows/nodejs.condo.test.yml` (2021-02-14 → 2024-06-30).

---

## 1. Guiding Principle

The CI workflow evolved significantly across 5 eras. Our `install-and-run.sh` must work across **all commits** in the study window. The strategy is:

1. **Always-safe actions** — do unconditionally, they're harmless if unused
2. **Feature-detected actions** — probe the commit's state, branch accordingly
3. **Branching factors to minimize** — things that differ across commits but we can collapse into a single path

---

## 2. Always-Safe Actions (Do Unconditionally)

These can be set/run at every commit without harm. They're either no-ops if unused or provide defensive defaults.

### 2.1 Environment Variables

Set these **before anything else**. They're referenced by the app code conditionally — setting them when not needed is harmless.

```bash
# ── Core app env ─────────────────────────────────────────────────────────
export NODE_ENV=test                    # Used from Era 1 onward
export DISABLE_LOGGING=true             # Present in first .env.example
export DATABASE_URL="postgresql://postgres:postgres@127.0.0.1/main"

# ── Notification/worker config ───────────────────────────────────────────
export NOTIFICATION__SEND_ALL_MESSAGES_TO_CONSOLE=true   # Added Era 1 (2021-05-04)
export NOTIFICATION__DISABLE_LOGGING=true                # Added Era 1 (2021-08-03)
export WORKER_CONCURRENCY=50                             # Added Era 1 (2021-05-04)

# ── Test helpers ─────────────────────────────────────────────────────────
export FAKE_ADDRESS_SUGGESTIONS=true     # Added Era 2 (2022-06-13)
export TESTS_LOG_REQUEST_RESPONSE=true   # Added Era 2 (2022-07-03)

# ── Memory ───────────────────────────────────────────────────────────────
export NODE_OPTIONS="--max-old-space-size=12288"  # Era 2+ used 4096, we use 12288 for safety

# ── Feature flags (safe defaults) ────────────────────────────────────────
export DISABLE_CAPTCHA=true
export USE_LOCAL_FEATURE_FLAGS=true

# ── Metabase (referenced in code, safe fake value) ───────────────────────
export METABASE_CONFIG='{"url": "https://metabase.example.com", "secret": "4879960c-a625-4096-9add-7a81d925774a"}'

# ── News items (added Era 4, safe default) ───────────────────────────────
export NEWS_ITEMS_SENDING_DELAY_SEC=2
export NEWS_ITEM_SENDING_TTL_SEC=2

# ── Database pool ────────────────────────────────────────────────────────
export DATABASE_POOL_MAX=10
```

**Rationale:** All these are either read from `process.env` with fallbacks, or only used when a specific code path is triggered. None will cause a crash if set when the feature doesn't exist.

### 2.2 File System Setup

```bash
# Copy .env.example → .env (done from Era 1, commit 073814913)
if [ ! -f .env ]; then
    cp .env.example .env
fi

# Ensure dist/admin exists (Keystone checks for it in non-dev mode)
# Added Era 3 (2023-02-24), harmless before that
mkdir -p ./apps/condo/dist/admin
```

### 2.3 Python Dependencies

```bash
# Django + psycopg2 for kmigrator.py — present from Era 1 onward
pip3 install django psycopg2-binary
```

### 2.4 Docker Compose Service Start

The CI always starts `postgresdb` and `redis`. The service names are stable across all eras (postgresdb was renamed from mongodb on 2021-02-15, but that's before our study window if we start from the first CI commit).

```bash
# Start core services — always present in docker-compose.yml
docker compose up -d postgresdb redis
```

### 2.5 Wait for PostgreSQL

```bash
# PostgreSQL is always the primary database from Era 1 onward
for i in $(seq 1 30); do
    if docker compose exec postgresdb pg_isready -U postgres &>/dev/null; then
        break
    fi
    sleep 2
done
```

---

## 3. Feature-Detected Actions (Branch on Commit State)

These need detection because they may or may not exist at a given commit.

### 3.1 Infrastructure Services

| Service | Detection | Action |
|---------|-----------|--------|
| **NATS** | `grep -q 'nats:' docker-compose.yml` | `docker compose up -d nats` |
| **PostgreSQL replica** | `grep -q 'postgresdb-replica' docker-compose.yml` | `docker compose up -d postgresdb-replica` |
| **Valkey cluster** | `grep -q 'valkey-cluster' docker-compose.yml` | `docker compose up -d valkey-cluster` |
| **Docker profiles** | `grep -q 'profiles' docker-compose.yml` | Use `docker compose --profile dbs up -d` instead of individual services |

**Strategy:** Start `postgresdb` and `redis` unconditionally (they're always there). Then probe for extras. This keeps branching minimal — only 3 binary checks.

### 3.2 Build Steps

| Step | Detection | Action |
|------|-----------|--------|
| **Turbo install** | `jq -e '.devDependencies.turbo' package.json` | `npm i -g turbo` |
| **Turbo build deps** | `jq -e '.scripts["build:deps"]' apps/condo/package.json` | `yarn workspace @app/condo build:deps` OR `turbo build --filter=condo^...` |
| **Admin UI build** | `jq -e '.scripts.build' apps/condo/package.json` | `yarn workspace @app/condo build` |

**Strategy:** Try turbo build first (Era 4+), fall back to direct build. The Admin UI build (`yarn workspace @app/condo build`) is present from Era 1.

### 3.3 Migration & Schema Steps

| Step | Detection | Action |
|------|-----------|--------|
| **prepare.js** | `test -f bin/prepare.js` | `node bin/prepare.js -f condo` (with `-r` and `-c` flags if supported) |
| **Direct migrate** | `jq -e '.scripts.migrate' apps/condo/package.json` | `yarn workspace @app/condo migrate` |
| **Migration check** | `jq -e '.scripts.makemigrations' apps/condo/package.json` | `yarn workspace @app/condo makemigrations --check` |
| **Schema validation** | `test -f bin/validate-db-schema-ts-to-match-graphql-api.sh` | `source bin/validate-db-schema-ts-to-match-graphql-api.sh` |

**Strategy:** Prefer `prepare.js` if it exists (it handles everything). Otherwise fall back to direct `migrate`.

### 3.4 Server Start & Wait

| Step | Detection | Action |
|------|-----------|--------|
| **wait-apps-apis.js** | `test -f bin/wait-apps-apis.js` | `node bin/wait-apps-apis.js -f condo -s 3000 -t 120000` |
| **waitForLocalhostApiReady.sh** | `test -f .github/workflows/waitForLocalhostApiReady.sh` | `bash .github/workflows/waitForLocalhostApiReady.sh` |
| **Curl polling** | (fallback) | Curl loop on `localhost:3000/admin/api` checking for `appVersion` |

**Strategy:** Try `wait-apps-apis.js` first (newest), then `waitForLocalhostApiReady.sh`, then curl fallback.

### 3.5 Worker Start

| Detection | Action |
|-----------|--------|
| `jq -e '.scripts.worker' apps/condo/package.json` | `yarn workspace @app/condo worker &` |

**Strategy:** Always start the worker if the script exists. The worker is needed for task processing during tests.

### 3.6 Post-Test Steps

| Step | Detection | Action |
|------|-----------|--------|
| **Keystone package tests** | `jq -e '.scripts.test' packages/keystone/package.json` | `yarn jest ./packages/keystone --maxWorkers=2` |
| **Lint schema** | `jq -e '.["lint-schema"]' apps/condo/package.json` | `yarn workspace @app/condo lint-schema` |

---

## 4. Branching Factors to Minimize

These are the dimensions where the CI workflow varied across commits. We want to collapse them into as few code paths as possible.

### 4.1 Test Suite Organization — THE BIG ONE

The CI went through 4 distinct test organization patterns:

| Era | Pattern | # of `yarn test` calls |
|-----|---------|----------------------|
| 1 | Single monolithic `yarn workspace @app/condo test` | 1 |
| 2 | Split by domain pattern (sequential) | 10 (5 test + 5 spec) |
| 3 | Same as Era 2, with `--workerIdleMemoryLimit` | 10 |
| 4 | 4 parallel jobs, each with 2-4 test calls | 2-4 per job |
| 5 | Delegated to reusable workflow | N/A in this file |

**Our strategy:** Run **one single `yarn workspace @app/condo test`** with `--runInBand --forceExit --testTimeout=30000`. This is:
- **Correct** for Era 1 (that's exactly what they did)
- **Correct** for Eras 2-4 (running all tests together is equivalent to running them split — same tests, same coverage)
- **Simpler** than replicating the split logic
- **Slower** but that's acceptable for our offline study

**Why this is safe:** The split was a **performance optimization** (parallelism within a single CI job, or parallel CI jobs), not a correctness requirement. The `--testPathPattern` flags just partition the same test suite. Running them all in one invocation produces the same coverage.

### 4.2 Test Flags

The flags evolved as follows. We pick the **union** that works across all eras:

| Flag | Eras | Include? |
|------|------|----------|
| `--coverage` | 1-2 (removed Era 2) | **YES** — we need coverage |
| `--silent` | 1 (removed Era 2) | No — use `--silent=false --verbose` |
| `--testTimeout=15000` | 1+ | **YES** — but increase to 30000 for safety |
| `--forceExit` | 1+ | **YES** — Keystone has open handles |
| `--detectOpenHandles` | 1-2 (replaced by `--runInBand`) | No — `--runInBand` supersedes |
| `--runInBand` | 2+ | **YES** — avoids parallel test issues |
| `--maxWorkers=1` | 2 (briefly) | No — `--runInBand` is equivalent |
| `--maxWorkers=2` | 2 (briefly) | No — `--runInBand` is safer |
| `--bail` | 2+ | **NO** — forbidden by AGENT.md §7 |
| `--workerIdleMemoryLimit="50%"` | 4+ | **YES** — helps with OOM |
| `--silent=false --verbose` | 2+ | **YES** — useful for debugging |

**Final test command:**

```bash
yarn workspace @app/condo test \
    --coverage \
    --runInBand \
    --forceExit \
    --testTimeout=30000 \
    --workerIdleMemoryLimit="50%" \
    --silent=false \
    --verbose
```

### 4.3 Package Manager Flags

| Era | Install command |
|-----|----------------|
| 1 | `yarn` |
| 2 | `yarn install --frozen-lockfile` |
| 3+ | `yarn install --immutable` |

**Our strategy:** Use `yarn install --no-immutable` (as the current script does). This works because:
- Yarn 1: `--no-immutable` is ignored (not a valid flag, treated as a positional arg, yarn ignores unknown flags in v1)
- Yarn 3+: `--no-immutable` explicitly allows lockfile mutations (needed for WayPack registry URL patching)

### 4.4 Node.js Version

The CI used 14.x, 15.x, 16.10, and 16.x across eras. Our Dockerfile builds with a parameterized `NODE_VERSION` — we use the version from `commits.csv` for each commit. This is already handled by the pipeline.

### 4.5 Docker Compose Version

Early commits used `docker-compose` (v1), later ones use `docker compose` (v2 plugin). Our script already handles this with a compat shim.

---

## 5. Complete Flow Diagram

```
┌─────────────────────────────────────────────┐
│ 1. ALWAYS-SAFE                              │
│    ├─ Export all env vars (§2.1)            │
│    ├─ cp .env.example .env                  │
│    ├─ mkdir -p apps/condo/dist/admin        │
│    ├─ pip3 install django psycopg2-binary   │
│    └─ Start dockerd (Docker-in-Docker)      │
├─────────────────────────────────────────────┤
│ 2. START DATABASES                          │
│    ├─ docker compose up -d postgresdb redis │
│    ├─ [detect] nats? → up -d nats           │
│    ├─ [detect] replica? → up -d replica     │
│    ├─ [detect] valkey? → up -d valkey       │
│    └─ Wait for pg_isready                   │
├─────────────────────────────────────────────┤
│ 3. INSTALL & BUILD                          │
│    ├─ yarn install --no-immutable           │
│    ├─ [detect] turbo? → npm i -g turbo      │
│    ├─ [detect] build:deps? → run it         │
│    └─ yarn workspace @app/condo build       │
├─────────────────────────────────────────────┤
│ 4. MIGRATE & VALIDATE                       │
│    ├─ [detect] prepare.js? → run it         │
│    │   └─ else: yarn workspace @app/condo migrate
│    ├─ [detect] makemigrations? → check      │
│    └─ [detect] validate script? → source it │
├─────────────────────────────────────────────┤
│ 5. START SERVICES                           │
│    ├─ yarn workspace @app/condo start &     │
│    ├─ Wait for API ready                    │
│    │   ├─ [detect] wait-apps-apis.js        │
│    │   ├─ [detect] waitForLocalhostApiReady │
│    │   └─ fallback: curl polling            │
│    └─ [detect] worker? → start worker &     │
├─────────────────────────────────────────────┤
│ 6. RUN TESTS (single invocation)            │
│    └─ yarn workspace @app/condo test        │
│       --coverage --runInBand --forceExit     │
│       --testTimeout=30000                   │
│       --workerIdleMemoryLimit="50%"          │
│       --silent=false --verbose              │
├─────────────────────────────────────────────┤
│ 7. CLEANUP                                  │
│    ├─ Kill worker + server                  │
│    ├─ [detect] keystone pkg tests? → run    │
│    ├─ [detect] lint-schema? → run           │
│    ├─ docker compose down --volumes         │
│    └─ Stop dockerd                          │
├─────────────────────────────────────────────┤
│ 8. COLLECT COVERAGE                         │
│    └─ bash ../find-and-move-lcov.sh         │
└─────────────────────────────────────────────┘
```

---

## 6. Key Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| **`--bail` not used** | Tests continue after failure, may produce partial coverage | Acceptable — partial coverage is better than no coverage. The pipeline validates lcov output. |
| **Single test invocation vs split** | May hit memory limits on large test suites | `--workerIdleMemoryLimit="50%"` + `NODE_OPTIONS="--max-old-space-size=12288"` |
| **Missing env var causes crash** | Test setup fails | All env vars in §2.1 are either optional or have safe defaults in the app code |
| **Docker-in-Docker fails** | No database, tests fail | The pipeline already handles this — error logs are captured |
| **Service name changes** | `docker compose up` fails | Feature detection for service names; `postgresdb` and `redis` are stable across all eras |
| **prepare.js changes API** | Migration fails | Feature-detect flags (`--filter`, `--replicate`, `--cluster`) before passing them |
