# bhima

**Repository:** https://github.com/third-culture-software/bhima
**Status:** active

## Test infrastructure

- **Package manager:** npm (`package_manager_version_overwrite = "npm"`; see
  [`config.json`](../../config.json) → `bhima`).
- **Node strategy:** default.
- **Runners:** `mocha`, `c8`, Karma, Chromium.
- **Eras:** four suites run against a full-stack hospital information system
  (Node.js/Express backend with MySQL and Redis, AngularJS client). The client
  bundle is built via `build` / `build:client` / `compile`, detected dynamically.

## Coverage collection

- **Suites collected:**
  - `server-unit` — `mocha` + `c8`. Two eras:
    `sh/server-unit-tests-node.sh` (shell script) and direct `mocha`.
  - `client-unit` — Karma with a `karma-coverage` harness sidecar. Coverage is
    validated for non-zero `DA` entries and AngularJS DI failures.
  - `integration` — `mocha` + `c8` against a live Express server. Requires MySQL
    (`build:db`), Redis, and Chromium.
  - `integration-stock` — same as `integration`, but requires a separate
    `build:stock` database seed. Runs after the main integration suite; the server
    is killed between suites.
- **Suites excluded:** none.
- **Coverage tool / config:** `c8` (installed as a fallback when absent).
- **LCOV production:** `c8` `lcov` reporter for the mocha suites; the
  `karma-coverage` sidecar writes the client `lcov`. Chromium runs with
  `--no-sandbox`.

## Checklist

- [x] 100 done (96/100)
- [x] failed tests doublechecked (52 `acceptable`; 0 `problematic`/`unclear` —
  coral-PDF timeout family re-ran clean)
- [x] complete run (all 4386 commits processed; 298 hard errors, 93.2% coverage)
- [x] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-16 08:58).

| Metric | Value |
|---|---|
| Commits processed | 4386 |
| Without test failures | 3880 |
| With test failures | 208 |
| Not applicable | 0 |
| Hard errors | 298 |
| Coverage produced | 93.2% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

52 labeled rows in [`failure_labels_project.csv`](failure_labels_project.csv)
(all `acceptable`); per-commit logs under [`logs/`](logs/).
[`failure_labels_collapsed_problematic_unclear.csv`](failure_labels_collapsed_problematic_unclear.csv)
lists no `problematic`/`unclear` families.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `integration` `AssertionError`: HTTP status mismatches (expected 2xx/4xx, got 4xx/5xx) | acceptable | valid partial | none |
| `integration` `AssertionError`: response key-set mismatches | acceptable | valid partial | none |
| `integration` `AssertionError`: numeric / array-length / count mismatches (payroll, purchases, `staffingIndices`, inventory) | acceptable | valid partial | partly date-sensitive; none |
| `integration` UTF-8 mojibake (`RemunÃ©ration` vs `Remunération`) | acceptable | valid partial | locale/DB collation; none |
| `integration` `SyntaxError: Invalid regular expression: missing /` | acceptable | valid partial | none |
| `server` `TypeError: job.nextDate(...).format is not a function` | acceptable | valid partial | none |
| `server` `TypeError: coral is not a function` / `require(...) is not a function` | acceptable | valid partial | none |
| `server` SQL `Error: ER_*` (e.g. `ER_WRONG_VALUE_COUNT_ON_ROW`) and `Error: A callback is required!` | acceptable | valid partial | none |

**Resolved (2026-09-16):** the earlier `problematic` mocha-timeout family
(5000 ms `pdf.spec.js` / `account_report.js`, 30000 ms
`reports/finance/cash.receipt.js`) was a container-contention flake, not a
deterministic failure. All five affected commits
(`1691933532_d9238c94`, `1707063237_2f77b170`, `1709541076_55f1ecae`,
`1715548551_bdc18457`, `1718473127_39ada258`) were re-run and every suite passed
(`exit_code=0`, zero timeout lines); the old logs are archived under
`archive/pre_pdf_timeout_retry/`. The `439ec8f6ef51` auto-classify rule is
retained as `problematic` as a regression tripwire.

## Environment / setup fixes

- MySQL 8.0 from the official APT repo (MariaDB 10.5's stored-procedure and
  charset behaviour breaks `build:db`).
- MySQL server started with
  `--sql-mode="STRICT_ALL_TABLES,NO_UNSIGNED_SUBTRACTION"` and a
  `mysql_native_password` user, replicating bhima's CI.
- Redis daemon and Chromium `--no-sandbox`.
- `karma-coverage` / babel harness symlinked into `node_modules` for the client
  sidecar config.
- Timeouts are contention-sensitive: the `integration` suite drives
  `@ima-worldhealth/coral` PDF rendering, which is CPU-bound. Re-running the
  five affected commits with `--max-workers 1` cleared every timeout, so lower
  worker counts are preferred for this project.

## Known gaps

298 commits hard-errored (exit code > 1 or no `lcov.info`), so their coverage is
missing. Causes, from the `.error` logs:

| Cause | Commits |
|---|---|
| `ETARGET` — declared dependency range unresolvable in the author-date WayPack snapshot | 242 |
| Client build produced no `bhima.min.js` | 15 |
| `build:stock` seed foreign-key constraint failure | 14 |
| `build:db` failed | 12 |
| `server` suite emitted empty `lcov.info` | 9 |
| Redis connection refused | 3 |
| `karma-coverage` produced no `lcov.info` | 2 |
| Build DB column-count mismatch | 1 |

The `ETARGET` group is the faithful "un-buildable at author date" reconstruction
described in [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §1; the top missing
packages are `@ima-worldhealth/coral`, `@uirouter/core`, `release-it`, and
`express-handlebars`.
