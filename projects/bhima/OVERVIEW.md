# bhima

**Repository:** https://github.com/third-culture-software/bhima
**Status:** active

## Test infrastructure

- **Package manager:** npm (`package_manager_version_overwrite = "npm"`; see
  [`config.json`](../../config.json) → `bhima`).
- **Node strategy:** default.
- **Runners:** `mocha` under `c8` (server and integration suites); Karma with
  `karma-coverage` and Chromium (client suite).
- **Eras:**
  - `server-unit` — `sh/server-unit-tests-node.sh` when present, otherwise direct
    `mocha`; the era is chosen from the checked-out tree.
  - `client-unit` — always the `harness/karma.sidecar.conf.js` sidecar.
  - `integration` / `integration-stock` — enabled only when the commit's
    `package.json` defines `test:integration` / `test:integration:stock`; the
    stock suite additionally requires `build:stock`.

## Development style

- **PR merging strategy:** Merge commit (86.0% of first-parent commits; 89.2% overall).
- **Merge convention:** `Merge #<PR>` (2021–2023); standard `Merge pull request #<PR> from <branch>` (2024–2025).
- **Direct commits:** Low (10.9% human direct commits, 200 commits).
- **JS/TS code impact of direct commits:** Low — direct commits by lead maintainer are dependency bumps, stylelint setup, CI updates, and occasional translation/hotfixes.
- **Issue tracking discipline:** High (PRs track feature and bugfix branches).
- **Workflow notes:** Strictly branch-merge driven, preserving full feature branch histories.

## Coverage collection

- **Suites collected:**
  - `server-unit` → output suite `server` — `mocha` + `c8`.
  - `client-unit` → output suite `coverage_client_client` — Karma +
    `karma-coverage`.
  - `integration` → output suite `integration` — `mocha` + `c8` against a live
    Express server with MySQL and Redis.
  - `integration-stock` → output suite `integration_stock` — `mocha` + `c8`
    after a `build:stock` database reseed; the server is killed between the two
    integration suites.
- **Suites excluded:** none.
- **Coverage tool / config:** `c8` (installed as a fallback when absent) and the
  `karma-coverage` sidecar. No project coverage config and no coverage gate apply
  to the collected suites.
- **LCOV production:** `c8 --reporter=lcov` for the mocha suites; the Karma
  sidecar writes `harness/output/lcov.info`, which is rejected when it is empty,
  has no non-zero `DA` entry, or shows AngularJS dependency-injection failures.
  Chromium runs with `--no-sandbox`.

## Checklist

- [x] 100 done (96/100)
- [x] failed tests doublechecked (100-commit sample reviewed; non-zero-exit runs
  classified)
- [x] complete run (4386 commits processed; 0 unprocessed; 298 hard errors;
  93.2% coverage)
- [x] complete test failure check (all 77 fingerprints and 208 failing runs
  labeled)
- [x] complete JEV test failure check (77 of 77 fingerprints evaluated; 0
  pipeline issues)

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 20:13).

| Metric | Value |
|---|---|
| Commits processed | 4386 |
| Without test failures | 3880 |
| With test failures | 208 |
| Not applicable | 0 |
| Hard errors | 298 |
| Coverage produced | 93.2% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py bhima --stats` (window `min`, run 2026-10-21)
and `stats_output/report.txt` (generated 2026-10-21 20:13). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 208 |
| Failing runs (label DB) | 208 |
| Fingerprints (min / max) | 77 / 88 |
| Labeled fingerprints | 77 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 77 |
| reevaluated_acceptable | 0 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 29 / 48 |
| Labeled detections (min) | 488/488 (100.0%) |
| Labeled runs (min) | 208/208 (100.0%) |
| Jev pipeline issues | 0 |

**State:** complete.

On 2026-10-21 the failure patterns were extended with a chai diff anchor
(`^\s*\+ expected - actual$`) and the ISO-timestamp exclusion was narrowed to
`errors #interceptor()` lines. Detection rose from 435 to 593 hits and from 49 to
77 fingerprints, so every failing run now carries at least one fingerprint; the
28 new families were labeled and re-checked with Jev the same day. The previous
patterns are kept as
[`failure_patterns.json.bak`](label_analysis/failure_patterns.json.bak).

## Environment / setup fixes

- **MySQL 8.0 instead of MariaDB 10.5** (`Dockerfile`): MariaDB's
  stored-procedure and charset behaviour breaks the `build:db` seed.
- **MySQL server configuration** (`install-and-run.sh`):
  `--sql-mode="STRICT_ALL_TABLES,NO_UNSIGNED_SUBTRACTION"`, `utf8mb4` server
  charset and collation, and a `mysql_native_password` user, replicating the
  project's CI; the app's `mysql@^2.16` client cannot authenticate with
  `caching_sha2_password` over TCP.
- **Redis and Chromium** (`install-and-run.sh`): `redis-server --daemonize yes`
  and `--no-sandbox` for Chromium and Puppeteer.
- **Karma harness** (`Dockerfile`, `install-and-run.sh`): `karma-coverage` and
  Babel packages are installed in `/coverage_reloaded/harness` and symlinked into
  the project's `node_modules`.
- **libfaketime** (`helper/fake-time-node.js`): wraps `build:db`, `build:stock`,
  `integration`, and `integration-stock` at the commit timestamp.
- **Timeout-sensitive integration suite:** the `coral` PDF-rendering timeouts were
  cleared by re-running the affected commits; those runs are archived under
  [`archive/pre_pdf_timeout_retry/`](archive/pre_pdf_timeout_retry/) (logs only,
  no README, so no counts are restated here).

## Known gaps

298 commits hard-errored (exit code > 1 or no `lcov.info`), so their coverage is
missing. Cause per `.error` log:

| Cause | Commits |
|---|---|
| `ETARGET` — declared dependency range unresolvable in the author-date WayPack snapshot | 242 |
| Client build produced no `bhima.min.js` | 15 |
| `build:stock` seed failure (foreign-key `stock_movement__period`, column-count mismatch) | 14 |
| `build:db` seed failure (e.g. no fiscal year for the provided date, seed SQL drift) | 13 |
| `server` suite aborted (`ERR_REQUIRE_ESM` for `chai`) and emitted no `lcov.info` | 9 |
| Redis connection refused | 3 |
| `karma-coverage` produced no `lcov.info` | 2 |

The `ETARGET` group is the faithful "un-buildable at author date" reconstruction
described in [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §1; the top missing
packages are `@ima-worldhealth/coral`, `@uirouter/core`, `release-it`, and
`express-handlebars`.

The `integration` suite renders PDFs through `@ima-worldhealth/coral` and is
sensitive to host contention against mocha's 30 s per-test timeout. Re-running
affected commits cleared the timeouts, so a fresh timeout family in this suite is
a contention candidate before it is labeled `problematic`.
