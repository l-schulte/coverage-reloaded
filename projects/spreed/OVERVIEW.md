# spreed

**Repository:** https://github.com/nextcloud/spreed
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `spreed`); `min_pm_version.npm = 8`.
- **Node strategy:** default.
- **Runners:** `jest`, `vitest`, `vue-cli-service`.
- **Eras:** `test:unit` used `vue-cli-service` initially and later `jest`. The `test`
  script replaced `test:unit` and moved from `jest` to `vitest`.

## Coverage collection

- **Suites collected:** `test:unit`, then `test`. The runners are called directly with
  coverage parameters appended.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage; the project does not use
  `testrunner` parameters.
- **LCOV production:** runner coverage output is collected by `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (92/100)
- [x] failed tests doublechecked (fails rarely)
- [x] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 11:49).

| Metric | Value |
|---|---|
| Commits processed | 16406 |
| Without test failures | 15844 |
| With test failures | 447 |
| Not applicable | 0 |
| Hard errors | 115 |
| Coverage produced | 99.3% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

None documented beyond rare failures. The test suite is small and only improved
around 2020-04.

## Environment / setup fixes

None.

## Known gaps

None documented.
