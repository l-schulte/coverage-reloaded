# Condo CI Test Setup Evolution Report

> Generated from 55 diffs of `.github/workflows/nodejs.condo.test.yml` spanning **2021-02-14 → 2024-06-30**.

---

## Table of Contents

1. [Era 1: Single-Job Monolith (2021-02-14 → 2022-05-24)](#era-1-single-job-monolith-2021-02-14--2022-05-24)
2. [Era 2: Split Test Suites (2022-05-25 → 2022-07-07)](#era-2-split-test-suites-2022-05-25--2022-07-07)
3. [Era 3: Parallel CI Jobs (2022-07-08 → 2023-04-11)](#era-3-parallel-ci-jobs-2022-07-08--2023-04-11)
4. [Era 4: Multi-Job Matrix (2023-04-12 → 2023-10-14)](#era-4-multi-job-matrix-2023-04-12--2023-10-14)
5. [Era 5: Docker Image Build + Reusable Workflow (2023-10-15 → 2024-06-30)](#era-5-docker-image-build--reusable-workflow-2023-10-15--2024-06-30)
6. [Summary of Key Parameters](#summary-of-key-parameters)

---

## Era 1: Single-Job Monolith (2021-02-14 → 2022-05-24)

**Commits:** 073814913 → a78afc71f (17 diffs)

### Initial Setup (2021-02-14)

The very first CI workflow was created with a single `build` job:

```yaml
name: RUN DEMO TESTS
on: [push, pull_request] → master
```

**Steps:**
1. `actions/checkout@v2`
2. `cp .env.example .env`
3. `docker-compose up -d mongodb` (later changed to `postgresdb`)
4. `actions/setup-node@v1` with Node 14.x
5. Install: `yarn`, `pip3 install django`, `pip3 install psycopg2-binary`
6. Run tests:
   - Migrate DB if PostgreSQL: `yarn workspace @app/condo migrate`
   - Start dev server: `yarn workspace @app/condo dev &`
   - Wait for API: curl loop on `localhost:3000/admin/api` checking for `appVersion`
   - Run tests: `yarn workspace @app/condo test`
7. **Env vars:** `DATABASE_URL`, `NODE_ENV=development`, `DISABLE_LOGGING=true`

### Key Changes in Era 1

| Date | Diff | Change |
|------|------|--------|
| 2021-02-15 | 11df697e9 | MongoDB → **PostgreSQL** (`docker-compose up -d postgresdb`) |
| 2021-02-18 | 395ddcb51 | Renamed workflow to **"RUN CONDO TESTS"**; added `tr -d ' \n'` to curl health check; increased sleep to 2s; added `--silent` to test |
| 2021-02-19 | 3404024bf | Node **14.x → 15.x**; sleep 2s → 3s |
| 2021-03-04 | 41dbfe249 | Added **`--coverage`** flag to test command |
| 2021-03-26 | f27bfe287 | Node **15.x → 14.x** |
| 2021-03-29 | 9ecfd7fc4 | Inline curl loop replaced by **`bash ./.github/workflows/waitForLocalhostApiReady.sh`** |
| 2021-03-30 | 3f16cda95 | Sleep after API ready: 1s → **3s** |
| 2021-04-05 | 25cc2ac14 | Added **frontend build step** (`yarn workspace @app/condo build`) — placed before tests |
| 2021-04-21 | 7f60fe70a | Added **Redis** to docker-compose; moved frontend build to **after tests** with production `.env`; docker-compose down before build |
| 2021-05-04 | 32f0d5dbc | **Major restructure:** separated steps with blank lines; added `NODE_ENV=test`, `NOTIFICATION__SEND_ALL_MESSAGES_TO_CONSOLE=true`, `WORKER_CONCURRENCY=50`; added **worker process** (`yarn workspace @app/condo worker &`); checks background processes count (`[[ $(jobs | wc -l) != '2' ]] && exit 2`); added `--testTimeout=15000 --forceExit --detectOpenHandles`; kills background processes after tests; runs **`yarn jest ./packages/@core.keystone`** separately |
| 2021-06-29 | b66b77ee4 | Added **migration check**: `yarn workspace @app/condo makemigrations --check` |
| 2021-07-27 | c1f6bb2bc | Added `IN_CI: true` env var (removed in next commit) |
| 2021-08-03 | 879ce59ae | Added `NOTIFICATION__DISABLE_LOGGING=true`; migration check silenced (`&> /dev/null`); removed `IN_CI` |
| 2021-09-15 | 5666b7fc1 | Added **`yarn workspace @app/condo lint-schema`** after tests |
| 2022-04-01 | 5ef210e73 | `yarn` → **`yarn install --frozen-lockfile`**; `--detectOpenHandles` → **`--maxWorkers=2`** (for both condo tests and `@core.keystone`) |
| 2022-04-12 | bfecfcb6c | `--maxWorkers=2` → **`--maxWorkers=1`** (comment: "tests with non-linear logic") |
| 2022-04-18 | fa0cb135b | `--maxWorkers=1` → **`--detectOpenHandles`** (reverted back) |
| 2022-05-17 | a78afc71f | Added `FILE_FIELD_ADAPTER=local` to build env |

---

## Era 2: Split Test Suites (2022-05-25 → 2022-07-07)

**Commits:** c91f6719c → d3361b990 (6 diffs)

### Key Change: Test Suite Splitting

The monolithic test run was broken into **multiple sequential `yarn workspace @app/condo test` invocations** with `--testPathPattern`:

**Initial split (2022-05-25):**
- Removed frontend build step entirely
- Dev/worker logs redirected to files: `condo.dev.log`, `condo.worker.log`
- Test output redirected to `condo.test.log`
- Added `--silent=false --verbose` for verbose output
- Added **log artifact upload** on failure (`actions/upload-artifact@v3`)

**First test split (2022-05-26):**
- Added **`--bail`** flag (stops on first failure)
- Tests split into 5 groups:
  1. `/domains/organization/`
  2. `/domains/user/`
  3. `/domains/acquiring/|/domains/billing/`
  4. `/domains/ticket/|/domains/meter/|/domains/contact/`
  5. Everything else (via `--testPathIgnorePatterns`)

**Refined patterns (2022-05-27):**
- `--runInBand` replaces `--detectOpenHandles`
- Removed `--coverage` flag
- Patterns refined to match `(.*)[.]test.js$` suffix

**Further split (2022-05-29):**
- Added **SPECS** as separate test groups (`.spec.js` files)
- 5 test groups + 5 spec groups = **10 sequential test runs**

**Reorganized (2022-05-30):**
- Consolidated into numbered groups:
  - **TESTS:** `condo.{1-5}.test.{name}.log`
  - **SPECS:** `condo.{1-4}.spec.{name}.log`
- Added `(.*)[.]test.js$` catch-all for non-schema tests
- `@core.keystone` → **`packages/keystone`** (renamed package)

**New env vars added:**
- `DISABLE_LOGGING=false` (2022-05-26)
- `FAKE_ADDRESS_SUGGESTIONS=true` (2022-06-13)
- `TESTS_LOG_REQUEST_RESPONSE=true` (2022-07-03)

**Docker logs on failure (2022-05-29):**
- Added `jwalton/gh-docker-logs@v1` step to collect Docker logs on failure

---

## Era 3: Parallel CI Jobs (2022-07-08 → 2023-04-11)

**Commits:** 5228a554c → 711f6fac3 (6 diffs)

### Key Change: Submodules & Immutable Installs

**Submodules (2022-08-22):**
- `actions/checkout@v2` → added `fetch-depth: 0`, `submodules: recursive`, `ssh-key`
- `yarn install --frozen-lockfile` → **`yarn install --immutable`**

**New test group (2022-09-01):**
- Added explicit group for `analytics|notification|subscription|miniapp` domains
- Added `METABASE_CONFIG` env var

**Memory management (2022-10-31):**
- Added `NODE_OPTIONS="--max_old_space_size=4096"`

**Turbo (2023-01-23):**
- Added `npm i -g turbo` to install step

**Keystone workaround (2023-02-24):**
- Added `mkdir -p ./apps/condo/dist/admin` before dev server start

---

## Era 4: Multi-Job Matrix (2023-04-12 → 2023-10-14)

**Commits:** 867fb16d5 → feedc3f2e (10 diffs)

### Key Change: From Single Job to Multiple Parallel Jobs

The single `build` job was replaced by **4 parallel jobs**:

1. **`test-organization-related-domains`** — organization, user, scope, property
2. **`test-services-related-domains`** — acquiring, billing, miniapp, banking
3. **`test-ticket-related-domains`** — ticket, meter, contact, resident
4. **`test-other-domains`** — everything else + keystone + lint-schema

Each job is **self-contained** with its own:
- `actions/checkout@v3`
- Docker compose (postgresdb + redis)
- `actions/setup-node@v3` with `cache: 'yarn'`
- Full install + build + test pipeline
- Log artifact upload on failure

**Node version:** `16.10` → `16.x`

**New additions:**
- `source bin/validate-db-schema-ts-to-match-graphql-api.sh` (schema validation)
- `--workerIdleMemoryLimit="50%"` added to all test commands (2023-04-14)
- `NEWS_ITEMS_SENDING_DELAY_SEC=2` env var (2023-05-15)
- **Turbo build step:** `turbo build --filter=condo^...` (2023-07-02)
- `actions/setup-node@v1` → **`@v3`** with `cache: 'yarn'` (2023-09-25)
- `printenv` added for debugging (2023-09-25), removed later (2023-10-03)
- `workflow_dispatch` trigger added (2023-09-26), removed (2023-10-03)

---

## Era 5: Docker Image Build + Reusable Workflow (2023-10-15 → 2024-06-30)

**Commits:** 4eca8e349 → 9cb1b3830 (16 diffs)

### Key Change: Complete Architectural Overhaul

The workflow was **completely rewritten** (2023-10-15) to use a **two-phase architecture**:

#### Phase 1: `build-image` Job
- Builds a Docker image (`condo.tests.Dockerfile`) and pushes to SberCloud registry
- Uses `docker/build-push-action@v5`
- Caching: `type=gha` (GitHub Actions cache)
- Yarn cache injected via `buildkit-cache-dance`

#### Phase 2: `domains-tests-job` (Reusable Workflow)
- Delegates to **`.github/workflows/_nodejs.condo.core.tests.yml`**
- Matrix of 15 domains: organization, user, scope, property, acquiring, billing, miniapp, banking, ticket, meter, contact, resident, notification, common, others
- `fail-fast: false` for debugging

### Subsequent Refinements

| Date | Diff | Change |
|------|------|--------|
| 2023-10-16 | feedc3f2e | Cache target: `/app/.yarn/berry` → `/app/.yarn/cache`; added `runs-on: doma-runners-cluster` |
| 2023-10-17 | 4480f703d | Yarn cache steps **commented out**; cache: `type=gha` → `type=registry` with SberCloud registry |
| 2023-10-24 | 8bc7b3a5e | Yarn cache **restored**; cache target: `/root/.yarn/cache`; added debug `ls -lahtr` steps |
| 2023-10-25 | b6b22ebe7 | Cache target: `/root/.yarn/cache` (kept); debug steps kept |
| 2023-10-26 | 9c8ace828 | **Major rework:** `runs-on: doma-runners-cluster`; added `install deps` (git); docker buildx context setup; yarn cache steps **re-commented out**; debug steps removed |
| 2023-11-08 | 2fa0f6397 | **Reverted to Era 4 style** (single-machine multi-job) with `NODE_OPTIONS="--max_old_space_size=6144"` |
| 2023-11-10 | 63c1f1117 | **Back to Docker image build** with `concurrency` group + `cancel-in-progress`; `runs-on: runners-dind-set-cpu5-ram10`; `actions/checkout@v3` |
| 2024-04-03 | 4373e114a | `actions/checkout@v3` → **`@v4`** |
| 2024-05-06 | 106760bd9 | Registry URL → **`secrets.DOCKER_REGISTRY`** (parameterized); login moved before checkout; buildkit driver-opts added; cache refs use secret; `image` → `image_postfix`; `registry` removed (now in secrets) |
| 2024-05-31 | b6dfcdafa | `actions/checkout@v3` → `@v4` (cleanup) |
| 2024-06-30 | 9cb1b3830 | **File deleted** — workflow fully migrated to reusable workflow `_nodejs.condo.core.tests.yml` |

---

## Summary of Key Parameters

### Test Command Evolution

```
Era 1: yarn workspace @app/condo test --silent --coverage
     → yarn workspace @app/condo test --silent --coverage --testTimeout=15000 --forceExit --detectOpenHandles
     → yarn workspace @app/condo test --coverage --testTimeout=15000 --forceExit --detectOpenHandles --silent=false --verbose

Era 2: yarn workspace @app/condo test --testTimeout=15000 --runInBand --forceExit --silent=false --verbose --bail --testPathPattern=...

Era 3: yarn workspace @app/condo test --workerIdleMemoryLimit="50%" --testTimeout=15000 --runInBand --forceExit --silent=false --verbose --bail --testPathPattern=...

Era 4: (same as Era 3, split across 4 parallel jobs)

Era 5: Delegated to _nodejs.condo.core.tests.yml (reusable workflow)
```

### Node.js Versions Used

| Era | Node Version |
|-----|-------------|
| Era 1 (start) | 14.x |
| Era 1 (mid) | 15.x → 14.x |
| Era 4 | 16.10 → 16.x |
| Era 5 | 16.x |

### Infrastructure Dependencies

| Service | When Added | Notes |
|---------|-----------|-------|
| MongoDB | 2021-02-14 | Replaced by PostgreSQL next day |
| PostgreSQL | 2021-02-15 | Primary database throughout |
| Redis | 2021-04-21 | For worker queue |
| Django + psycopg2 | 2021-02-14 | Python deps for migrations |

### Test Types

| Type | Pattern | When Added |
|------|---------|-----------|
| Schema tests | `**/*.test.js` | Era 1 (initial) |
| Spec tests | `**/*.spec.js` | Era 2 (2022-05-29) |
| Domain-split tests | `domains/<name>/schema/*.test.js` | Era 2 (2022-05-26) |
| Keystone package tests | `yarn jest ./packages/keystone` | Era 1 (2021-05-04) |
| Lint schema | `yarn workspace @app/condo lint-schema` | Era 1 (2021-09-15) |
| Migration check | `yarn workspace @app/condo makemigrations --check` | Era 1 (2021-06-29) |
| DB schema validation | `bin/validate-db-schema-ts-to-match-graphql-api.sh` | Era 4 (2023-04-12) |

### Coverage Configuration

- **`--coverage` flag** added on 2021-03-04
- **Removed** on 2022-05-27 (when `--runInBand` was added)
- Coverage was generated by Jest's built-in coverage reporter (not c8/nyc)
- In Era 5, coverage is handled inside the Docker image / reusable workflow

### Bail Rule Status

- **`--bail`** was introduced on 2022-05-26 and remained present in all subsequent test invocations
- This is a **confound for our study** — tests stop at first failure, meaning later test files don't execute and don't produce coverage
- The `fail-fast: false` in Era 5's matrix only applies across jobs, not within a job's test suites
