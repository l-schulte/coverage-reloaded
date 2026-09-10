# material-ui

**Repository:** https://github.com/mui/material-ui
**Status:** active

## Test infrastructure

- **Package manager:** npm and pnpm across root and workspaces (see
  [`config.json`](../../config.json) → `material-ui`). The `pnpm-lock.yaml` Node
  strategy is disabled, and the exact Node version is used.
- **Node strategy:** `use_exact_node_version = true`; override `20.18` for
  `2025-08-05`–`2025-09-08` (epoch `1754389274`–`1757319331`).
- **Runners:** `jest`, `mocha`, `lerna`, `pnpm`.
- **Eras:** early commits run `jest` under `test`; later commits run lint and
  `test:coverage`. `test:coverage` wraps `mocha` in `nyc` and reports in `txt`;
  `test:coverage:ci` wraps `mocha` in `nyc` and reports in `lcov`.

## Coverage collection

- **Suites collected:** `test:coverage` when present, followed by `nyc` to emit
  `lcov`; fallback is `test` during the `jest` era.
- **Suites excluded:** none.
- **Coverage tool / config:** `nyc`.
- **LCOV production:** `nyc` with an `lcov` reporter.

## Checklist

- [x] 100 done (95/100)
- [x] failed tests doublechecked
- [ ] complete run (work in progress)
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-09 17:27).

| Metric | Value |
|---|---|
| Commits processed | 11882 |
| Without test failures | 5998 |
| With test failures | 1445 |
| Not applicable | 0 |
| Hard errors | 4439 |
| Coverage produced | 62.6% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Error: Command failed: git rev-parse next` | acceptable | none | Fixed. |
| Pending tests appear intermittently | acceptable | none | None. |
| Rare `Timeout of 10000/20000ms exceeded` in `@mui/envinfo` (`packages/{material-ui-,}mui-envinfo/envinfo.test.js`) | problematic | none; file is outside the `nyc` include set, so coverage stays valid (exit 1, warning) | None. The test shells out to `npx --package <build> envinfo --json` (2021–2024) or installs a fresh React+MUI fixture via `npm install` in its `before` hook (2024); both intermittently exceed the test's own generous per-test timeout under the container. |

## Environment / setup fixes

None.

## Known gaps

None documented.
