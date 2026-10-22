# sequelize

**Repository:** https://github.com/sequelize/sequelize
**Status:** active

## Test infrastructure

- **Package manager:** npm → yarn@1 → yarn@3 → yarn@4 across history; no package-manager
  overrides in [`config.json`](../../config.json) → `sequelize`.
- **Node strategy:** `node_version_lts_offset_months: 0` and `node_version_delay_months: 0`
  in [`config.json`](../../config.json) → `sequelize`, so the era-current LTS is used
  (bleeding-edge, matching the project's cadence): `yarn@4` commits resolve to Node
  20/22/24 instead of falling back to Node 16.
- **Runners:** `mocha` (all behavioral suites); `c8` (coverage).
- **Eras:**
  - 2020-07 → 2021-11: single package, npm.
  - 2021-11 → 2023-01: single package, yarn@1.
  - 2023-01 → 2023-06: monorepo (`packages/*`, yarn workspaces / lerna), yarn@1.
  - 2023-06 → 2023-10: monorepo, yarn@3 (Berry).
  - 2023-10 → 2025-12: monorepo, yarn@4 (Berry).
  - Dialect/DB version selection is read from the checked-out commit (`dev/<db>/...`
    from 2021-05; root `docker-compose.yml` before that).

## Development style

- **PR merging strategy:** Squash and merge (73.1% of first-parent commits).
- **Merge convention:** `<Title> (#<PR>)`.
- **Direct commits:** Low human (3.2%, 97 commits); moderate bot (23.6%, 707 commits).
- **JS/TS code impact of direct commits:** Minimal — bot commits are automated Semantic Release / dependency updates; human commits are npm publish credentials and meta-package fixes (`meta: set publishConfig.access`).
- **Issue tracking discipline:** High (all features and bugfixes are PR-reviewed with issue links).
- **Workflow notes:** Strictly squashes contributor PRs; releases are automated.

## Coverage collection

- **Suites collected:**
  - Core unit per dialect present at the commit (`test-unit-<dialect>`) for
    `mysql`, `mariadb`, `postgres`, `mssql`, `sqlite`/`sqlite3`, `db2`, `ibmi`,
    `snowflake`, `oracle`.
  - Core integration per locally-viable dialect (`test-integration-<dialect>`),
    including `postgres-native`: Postgres over the native `pg-native`/libpq binding
    instead of the pure-JS `pg` driver. It shares the `postgres` server but exercises a
    distinct driver/query path (`packages/postgres/src/connection-manager.ts`
    `native` branches, `query.js` libpq error handling), so it is collected separately.
  - Core smoke per dialect (`test-smoke`), whenever the checked-out commit defines it
    (from 2022-02-24): at the repo root during the single-package era, under
    `packages/core` after the monorepo split.
  - Root ESM export-parity suite (`test-unit-esm`), whenever the checked-out commit
    defines it.
  - Sibling package `test-unit` for every `packages/*` that defines it.
- **Suites excluded:**
  - **`integration-ibmi`** — DB2 for IBM i. IBM i (formerly AS/400, then i5/OS) is an
    IBM operating system on Power Systems with an integrated database, "DB2 for i". The
    dialect reaches it over ODBC via the `odbc` driver and requires a remote IBM i
    host; no local container image exists for it. Only `unit-ibmi` is collected.
  - **`integration-snowflake`** — Snowflake cloud data warehouse; requires account
    credentials and has no local backend. Only `unit-snowflake` is collected.
  - **`test-typings`** — TypeScript type checking (`tsc`; `dtslint` and `expect-type`
    in earlier eras). No runtime behavior.
  - **`lint` / `lint-docs`** — ESLint and Markdownlint style checks (early and mid
    eras); superseded by `test:format` (ESLint + Prettier) in later eras.
  - **`docs`** — API documentation generation (`typedoc` in later eras, `esdoc`
    earlier).
  - **`test-exports`** — verifies that generated public export entrypoints are
    current via `dev/sync-exports.mjs --check-outdated`; a static consistency check
    that exits 1 when the generated files are outdated.
  - **`teaser`** — a harness step (`test/teaser.ts`; `test/teaser.js` earlier) run
    before the unit and integration suites to validate `DIALECT` and print a banner;
    it emits no assertions.
  - **`sscce`** — standalone "Short, Self Contained, Correct Example" reproduction
    scripts (`sscce.ts`; `sscce.js` earlier) for manual debugging, not a test suite.
- **Coverage tool / config:** `c8 --reporter=lcovonly` (V8 coverage) via the pinned
  WayPack snapshot `$WAYPACK_REGISTRY_CURRENT`. c8 is used uniformly because nyc
  (Istanbul) cannot instrument native ESM, and `packages/cli` is ESM.
- **LCOV production:** one `lcov.info` per suite from c8, moved by
  `find-and-move-lcov.sh <suite> true <exit_code>` (PREPEND_PATHS=true namespaces
  paths as `packages/<pkg>/...` in the monorepo).

## Checklist

- [x] 100 done (1000 commits processed in first verification run, 95.7 % coverage-producing)
- [x] failed tests doublechecked (non-zero exit runs inspected and classified)
- [x] complete run (3007 commits processed, 96.8 % coverage-producing)
- [x] complete test failure check (100.0% of failure detections and runs labeled; 0 problematic/unclear)
- [x] complete JEV test failure check (Jev audit is current in `label_analysis/jev_audit.md`; 0 pipeline defects)

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 15:55).

| Metric | Value |
|---|---|
| Commits processed | 3007 |
| Without test failures | 123 |
| With test failures | 2789 |
| Not applicable | 0 |
| Hard errors | 95 |
| Coverage produced | 96.8% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py sequelize --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 15:55). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 2789 |
| Failing runs (label DB) | 2789 |
| Fingerprints (min / max) | 87 / 111 |
| Labeled fingerprints | 87 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 85 |
| reevaluated_acceptable | 2 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 17 / 70 |
| Labeled detections (min) | 58985/58985 (100.0%) |
| Labeled runs (min) | 2789/2789 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 5 flagged rows |
| Jev audit | current |

**State:** complete.

## Environment / setup fixes

- **Re-run MySQL transaction deadlock flake:** isolated timing race in concurrent transaction test (`[MYSQL] Transaction row locking supports for share`, `test/integration/transaction.test.js:861`). 1 run archived to [`archive/rerun_mysql_deadlock_flake/`](archive/rerun_mysql_deadlock_flake/) and re-run cleanly.
- **Per-test DB-reset timeout raised (`SEQ_TEST_CLEANUP_TIMEOUT=2min`):** the project's
  own `clearDatabase()` restores the schema after every test via `dropAllTables()`, which
  removes each foreign key and each table one at a time; on mssql/db2/mysql that chatty
  sequence can exceed the test-support default 10 s `CLEANUP_TIMEOUT` and be logged as
  *"Could not clear database … this test crashed the DB"*. It is a slow cleanup, not a
  dead container — the suite continues and produces full coverage — and only a reset that
  runs in a `beforeAll` (the `smoke-mssql` case) escalates to a zero-test abort.
  `install-and-run.sh` therefore sets the project's own `SEQ_TEST_CLEANUP_TIMEOUT`
  override to 120 000 ms (2 min) for every suite — well under the 20 min the project's
  own CI used for this variable (`1200000`, `.github/workflows/ci.yml`, `4443d2af1`);
  a genuinely hung DB still fails, just later. The 102 runs that hit the 10 s timeout
  (11 of them the generic slow-reset stalls, 90 inside the experimental-DB2 window above,
  1 the `smoke-mssql` abort) were archived to
  [`archive/raise_db_cleanup_timeout/`](archive/raise_db_cleanup_timeout/) and re-run to completion
  (101 coverage-producing, 1 Tedious query timeout).
- **Docker-in-Docker:** `LABEL dind.project="true"` + `docker.io` to run the era's
  database servers as nested containers.
- **Docker Compose v2 plugin (pinned `v5.0.2`) + `docker-compose` shim:** the repo's
  `dev/*/start.sh` scripts use both the v1 (`docker-compose`) and v2 (`docker compose`)
  CLIs across history.
- **`sudo` installed:** the db2 start scripts of the 2021-12 → 2023-07 window
  (`4443d2af1` → `c59011cad`) invoke `sudo docker …`; with no `sudo` they exited 127.
  We run as root, so installing the `sudo` package (which simply re-execs as root) is a
  faithful, flag-safe fix.
- **loader + Mocha globals preloaded for the era's DB start checks:** the pre-monorepo
  `dev/<db>/<ver>/start.sh` scripts end with `DIALECT=<db> node check.js`, and `check.js`
  loads the commit's test-support under **plain `node`**. That support imports the library
  by package name (the `sequelize` → `dist` alias) and/or is TypeScript, and in the
  2022-04..2022-06 window it also calls the Mocha globals (`afterEach`/`before`/
  `beforeEach`) unguarded at module scope. None of that works in plain `node`: the
  2021-11-18 → 2022-04-18 commits (`support.js`) need the loader's alias/`.ts` hook, and
  the 2022-04-18 → 2022-06-08 commits (`support.ts`) additionally need the Mocha globals.
  `install-and-run.sh` runs the DB start script under a generated preload shim (scoped to
  that command) that defines no-op Mocha globals and then requires the project's own
  `test/registerEsbuild`. This is exactly what upstream later did itself on 2022-06-09
  (`#14608`: it replaced `check.js` with a ts-node `check-connection.ts` — and commented
  *"'support' is requested by dev/check-connection, which is not a mocha context"* — after
  guarding those globals in `test/support.ts`). Upstream CI never saw the bug because it
  started those DBs via Actions `services:` and never ran these scripts. Active while
  `test/registerEsbuild.js` and a `dev/**/check.js` both exist (2021-11-18 → 2022-06-08,
  474 commits).
- **glibc 2.36 (bookworm libc):** the DB2 clidriver required by `ibm_db >= 3.3.0`
  needs GLIBC 2.32–2.34; the bullseye base ships 2.31.
- **Era-aware DB provisioning:** the commit's own `start-<db>*` script selects the
  database version; the 65 pre-`dev/` commits (2020-07 → 2021-04) fall back to the
  root `docker-compose.yml`.
- **MSSQL 2022 image pinned (floating-tag drift):** the floating
  `mcr.microsoft.com/mssql/server:2022-latest` moved `sqlcmd` from
  `/opt/mssql-tools/bin` (tools 17) to `/opt/mssql-tools18/bin` (tools 18) at CU14.
  Compose files written before the project adopted the tools-18 path (2024-09-04,
  `b2e0d69c3`) still call the tools-17 path, so with the drifted image their
  healthcheck can never pass and the container never reports healthy. `install-and-run.sh`
  rewrites those composes to `2022-CU13-ubuntu-22.04`, the last tools-17-bearing 2022
  CU. (Compose files already using the tools-18 path are left unchanged.)
- **DB2 clidriver pinned per era:** `v11.5.4` for `ibm_db < 3.3.0`, `v12.1.0` for
  `ibm_db >= 3.3.0`, selected by the project's own SQL0803N message-format
  discriminator. Clidriver is fetched outside npm/WayPack, so it is pinned explicitly.
- **`pg-native` installed at runtime:** for commits that define
  `test-integration-postgres-native`, `pg-native` (the libpq binding, which is not a
  declared dependency) is installed via the package manager
  (`npm install --no-save` / `yarn add --dev`). `libpq-dev` is present in the image.
- **`docker-multi-cache`: added `icr.io`** upstream so DB2 images are cached.
- **DB health-wait / healthcheck relaxed:** the DB composes' healthchecks use
  `timeout: 1s`, which kills `sqlcmd` / `mysqladmin` / `pg_isready` before it can return
  under load, so a container can never report `healthy` and the start script times out
  (`Timeout of 20s exceeded … sequelize-{mssql,mysql}-…`). At runtime
  `install-and-run.sh` rewrites every healthcheck `timeout:` to `30s` (all
  `dev/**/docker-compose.yml` + root compose) and extends the pre-2024
  `dev/wait-until-healthy.sh` (20s → 120s); the 2024+ helper already waits ~170s. Both
  abort loudly if a file has an unexpected layout. Note: this relaxation does **not**
  address the recurring `Timeout of 20s exceeded … sequelize-{mssql,mysql}-…` hard
  errors, whose dominant cause is the host async-I/O budget (see the next entry).
- **DB start script retry on startup races:** in `dev` era, database startup scripts
  (notably Db2 during its internal autoconfiguration restart `DB2STOP` → `DB2START`) can
  intermittently flap or reject connection probes on premature healthy status.
  `install-and-run.sh` adds a 10s sleep and a single retry to the start script invocation
  if the initial attempt exits non-zero.
- **c8 replaces nyc:** ESM-safe and avoids the `__coverage__` global (which tripped
  mocha `check-leaks`).
- **PREPEND_PATHS=true:** namespaces monorepo package coverage paths.
- **Host async-I/O budget raised (temporary, host-level):** the recurring DB-start hard
  errors (`Timeout of 20s exceeded … sequelize-{mssql,mysql}-…`) are caused by the host
  kernel exhausting its native-AIO budget, not by slow startup. Each database container
  reserves ~17 408 AIO events (≈68 I/O threads × 256 on this 256-CPU host); with the
  kernel default `fs.aio-max-nr = 65536` and ~26 688 events held by long-lived services,
  a third concurrent instance overflows the budget and the engine aborts at boot
  (`InnoDB: io_setup() failed with EAGAIN`; SQL Server `Unable to create a new
  asynchronous I/O context`), after which the health check can never pass. Mitigated by
  raising the host value to `1048576`. This is a **host-wide, temporary** adjustment —
  see [Host system prerequisites](../../OVERVIEW.md#host-system-prerequisites) for the
  command, scope, and revert.
- **InnoDB native AIO disabled in mysql/mariadb composes:** complementary to the host
  limit above. The standalone script
  [`disable-innodb-native-aio.js`](disable-innodb-native-aio.js) rewrites every
  `dev/**/docker-compose.yml` and the root `docker-compose.yml`, adding
  `command: ["--innodb-use-native-aio=0"]` to each `mysql`/`mariadb` service. Those
  engines then use simulated AIO and never call `io_setup()` (their reservation drops
  from ~17 408 to 0). The option is valid in every engine version in range (MySQL
  5.7–8.4, MariaDB 10.3–11.6), and both official entrypoints prepend the server binary
  when the first argument starts with `-` (`set -- mysqld "$@"` / `set -- mariadbd "$@"`).
- **`disable-innodb-native-aio.js` implementation:** it parses each compose with
  `js-yaml` (YAML 1.2 schema, so it does not coerce scalars such as `Y`→boolean or
  `a:b`→integer). The project `Dockerfile` installs `js-yaml@4` under
  `/opt/aio-patch/node_modules` and copies the script there; `install-and-run.sh` runs
  `node /opt/aio-patch/disable-innodb-native-aio.js`. The script is idempotent, rewrites
  a file only when it actually changes it, and reports (does not silently skip) a service
  that already defines a different `command:`. It covers only mysql/mariadb; SQL Server
  has no equivalent knob and still relies on the host limit.
- **Rootcompose-era mssql config neutralized (port mismatch):** the 21 commits of
  2021-01-15..17 ship `test/config/mssql.json`, which `test/config/config.js` prefers
  over the environment. It hard-codes port 1433 (and `SA`/`Password12!`), while the root
  `docker-compose.yml` publishes mssql as `8970:1433` with `SA_PASSWORD:
  yourStrong(!)Password` and the harness passes `SEQ_MSSQL_PORT=8970`; the
  `integration-mssql` suite therefore dials 1433 and trips the "ZERO tests" guard.
  `install-and-run.sh` renames the file aside (`…co_re_disabled`) in the rootcompose era
  only, so `config.js` falls back to the env, which matches the compose. It is a no-op in
  the dev era and in the 42 later rootcompose commits (2021-01-18 → 2021-04-04), where
  the file is absent.

## Known gaps

- **Suite-coverage audit (one-time, offline):** every `test*` script defined at any of the
  3007 commits was classified against what the harness runs. The only behavioral suite
  previously skipped was single-package `test-smoke` (2022-02-24 → 2023-01-15), now run;
  all other non-executed scripts are aggregates covered via their components or
  static/style checks (`test-typings`, `test-exports`, `test:format*`).
- Smoke suites are upstream-broken from 2022-05-23 through 2026-09-17 (stale across the
  entire portion of the study range in which they exist — see above); retained by policy
  (all accessible unit/integration suites are run).
- Pre-`dev/` era (65 commits) uses the root compose best-effort, including a floating
  `mssql:latest` tag.
- **Smoke import typo makes the suite unloadable (67 commits, 2022-02-24 → 2022-03-29):**
  the smoke suite was added (`04607c4b8`) about one hour after the project renamed its
  package from `sequelize` to `@sequelize/core` (`ac6bc26fc`), but
  `test/smoke/smoketests.test.js` still imports the old name
  (`require('sequelize/lib/data-types')`; the other 188 test files use `@sequelize/core`).
  No `sequelize` alias exists, so the module does not resolve and the suite cannot load
  (`Cannot find module 'sequelize/lib/data-types'` → "ZERO tests"). This is an **upstream
  defect** — a developer running `test-smoke` at these commits hits it too — and it was
  fixed upstream on 2022-03-29 (`ac89aac7f`, "normalize imports in tests"). Because the
  harness aborts a run when a suite cannot load, all 67 commits are recorded as hard
  errors and lose the coverage their unit and integration suites had already produced.
  The ≥ 90 % inclusion criterion is still met overall (96.8 %), so no harness adjustment
  was made for this window.
