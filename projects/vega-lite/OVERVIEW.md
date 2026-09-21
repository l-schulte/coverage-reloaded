# vega-lite

**Repository:** https://github.com/vega/vega-lite
**Status:** active

## Test infrastructure

- **Package manager:** npm, yarn (see [`config.json`](../../config.json) → `vega-lite`)
- **Node strategy:** default
- **Runners:** `jest`, `vitest`
- **Eras:** jest from 2020-05 to 2025-02; vitest from 2025-03 onward

## Coverage collection

- **Suites collected:**
  - `unit` (test/): jest (`--collectCoverage test/`) in jest era; vitest (`vitest run test/ --coverage`) in vitest era
  - `examples` (examples/): jest (`--collectCoverage examples/`) in jest era; vitest (`vitest run examples/ --coverage`) in vitest era
- **Suites excluded:** the runtime suite (`test-runtime/`, browser via `@vitest/browser-playwright` / puppeteer), which covers visual/selection behavior rather than behavioral coverage
- **Coverage tool / config:** runner-native coverage (jest built-in Istanbul; vitest `@vitest/coverage-v8`)
- **LCOV production:** runner coverage output is collected by `find-and-move-lcov.sh`

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (genuine errors)
- [x] complete run
- [x] complete test failure check (3 commits doublechecked, genuine schema errors)

## Results

Source: `stats_output/report.txt` (generated 2026-09-21 10:55).

| Metric | Value |
|---|---|
| Commits processed | 1664 |
| Without test failures | 1661 |
| With test failures | 3 |
| Not applicable | 0 |
| Hard errors | 0 |
| Coverage produced | 100.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `examples/specs/bar_negative_horizontal_label.vl.json › should produce valid Vega` | acceptable | Valid coverage (exit code 1) | Genuine schema validation error introduced in PR #7144 (`c4b2458b75`, `c7b541d570`, `734e0b894f`) and fixed in PR #7147 (`59aace73f`). |

## Environment / setup fixes

- Exported `PUPPETEER_SKIP_DOWNLOAD=true` and `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` in `install-and-run.sh` and `Dockerfile` to prevent Chromium downloads in the network-isolated container during install.
- Added `libjpeg-dev` and `libgif-dev` to `Dockerfile` for `node-canvas` source build fallback via `node-gyp`.
- Removed `--minWorkers=1` from vitest invocations in `install-and-run.sh` (rejected as an unknown option by vitest 4).

## Known gaps

The runtime suite (`test-runtime/`) is intentionally not collected (visual/browser tests).
