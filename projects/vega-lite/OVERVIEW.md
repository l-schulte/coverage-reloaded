# vega-lite

**Repository:** https://github.com/vega/vega-lite
**Status:** active

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `vega-lite`).
- **Node strategy:** default.
- **Runners:** `jest`, `vitest`.
- **Eras:** jest from 2020-05 to 2025-02; vitest from 2025-03 onward.

## Coverage collection

- **Suites collected:**
  - Jest era: `test` runs jest; a separate `jest` script carries
    `--experimental-vm-modules` for ESM.
  - Vitest era: `test --run` with `@vitest/coverage-istanbul`.
- **Suites excluded:** the `examples` suite and the runtime suite
  (`@vitest/browser-playwright`), which covers visual/selection behavior rather than
  behavioral coverage.
- **Coverage tool / config:** runner-native coverage (`@vitest/coverage-istanbul`
  in the vitest era).
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (genuine errors)
- [x] completed run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 12:06).

| Metric | Value |
|---|---|
| Commits processed | 1664 |
| Without test failures | 1645 |
| With test failures | 3 |
| Not applicable | 0 |
| Hard errors | 16 |
| Coverage produced | 99.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

None documented.

## Environment / setup fixes

None.

## Known gaps

The runtime suite and the `examples` suite are intentionally not collected.
