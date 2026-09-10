# yari

**Repository:** https://github.com/mdn/yari
**Status:** active

## Test infrastructure

- **Package manager:** npm, root plus `package.json` workspaces (see
  [`config.json`](../../config.json) → `yari`).
- **Node strategy:** `use_exact_node_version = true`; override Node 18 → `18.17`
  for epoch `1676043161`–`1692619152`.
- **Runners:** `jest`, `react-scripts test` (jest-based).
- **Eras:** workspace-specific `test` scripts use either `jest` or
  `react-scripts test`; `test:testing` is jest-based but runs end-to-end tests.

## Coverage collection

- **Suites collected:** workspace `test` scripts. The harness enters each
  workspace and calls the available script with coverage parameters appended.
- **Suites excluded:** end-to-end tests (`test:testing`).
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (looks great)
- [x] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 12:13).

| Metric | Value |
|---|---|
| Commits processed | 9082 |
| Without test failures | 8378 |
| With test failures | 284 |
| Not applicable | 0 |
| Hard errors | 420 |
| Coverage produced | 95.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

None documented.

## Environment / setup fixes

None.

## Known gaps

None documented. A separate content repository is checked out at a
timestamp-matched commit (see `install-and-run.sh`).
