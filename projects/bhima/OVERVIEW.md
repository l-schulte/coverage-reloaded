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
- **LCOV production:** `c8` `lcov` reporter. Chromium runs with `--no-sandbox`.

## Checklist

- [x] 100 done (96/100)
- [x] failed tests doublechecked (genuine issues)
- [x] complete run
- [x] complete test failure check (DB switch re-run done)

## Results

Source: `stats_output/report.txt` (generated 2026-09-10 15:32).

| Metric | Value |
|---|---|
| Commits processed | 4386 |
| Without test failures | 4087 |
| With test failures | 230 |
| Not applicable | 0 |
| Hard errors | 69 |
| Coverage produced | 98.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

Example commit `181f69` (`integration` suite, 2 failures):

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| UTF-8 encoding mismatch (`RemunÃ©ration` vs `Remunération`) in `accountFYBalances` and `budget/import` | problematic | valid partial coverage | Likely locale/database collation issue. |
| `ENOENT: bhima-bootstrap.css` (22 occurrences) | acceptable | valid partial coverage | [`head.handlebars`](https://github.com/third-culture-software/bhima/blob/181f6988df8c50988efa0607a608429ad6f05de5/server/lib/template/partials/head.handlebars#L5) references a CSS build artifact (compiled from `client/src/less/bhima-bootstrap.less` via gulp) that does not exist in source. HTML report tests still pass because they assert on JSON rendering. |


## Environment / setup fixes

None.

## Known gaps

None. The `integration` suite's database switch and re-run are complete.
