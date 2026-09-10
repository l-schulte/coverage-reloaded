# pf2e

**Repository:** https://github.com/foundryvtt/pf2e
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `pf2e`).
- **Node strategy:** `node_version_lts_offset_months = 1`.
- **Runners:** `jest`.
- **Eras:** a single `test` command, always `jest`. No `test` script exists before
  2020-04-22.

## Coverage collection

- **Suites collected:** `test`, with `--coverage` appended.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (97/100)
- [x] failed tests doublechecked (no failures)
- [x] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 11:22).

| Metric | Value |
|---|---|
| Commits processed | 27992 |
| Without test failures | 27900 |
| With test failures | 49 |
| Not applicable | 0 |
| Hard errors | 43 |
| Coverage produced | 99.8% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

None documented.

## Environment / setup fixes

None.

## Known gaps

None documented.
