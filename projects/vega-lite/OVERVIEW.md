# vega-lite

**Repository:** https://github.com/vega/vega-lite
**Status:** active

## Test infrastructure

- **Package manager:** npm, yarn (see [`config.json`](../../config.json) → `vega-lite`)
- **Node strategy:** default
- **Runners:** `jest`, `vitest`
- **Eras:** jest from 2020-05 to 2025-02; vitest from 2025-03 onward

## Development style

- **PR merging strategy:** Squash and merge (70.1% of first-parent commits; 88–92% in 2023+).
- **Merge convention:** `<Title> (#<PR>)`.
- **Direct commits:** Low human (9.0%, 96 commits); moderate bot (20.4%, 218 commits).
- **JS/TS code impact of direct commits:** Minimal — human direct commits are manual release tags (`chore: release v6.4.1`) by core maintainers.
- **Issue tracking discipline:** High (PRs track GitHub issues).
- **Workflow notes:** All feature contributions squashed; releases tagged directly on `main`.

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
- [x] complete test failure check (2 fingerprints, 100% labeled; 3/3 failing runs covered)
- [x] complete JEV test failure check (fingerprint mode, 2 evaluated, 0 flagged; audit current)

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 09:05).

| Metric | Value |
|---|---|
| Commits processed | 1664 |
| Without test failures | 1661 |
| With test failures | 3 |
| Not applicable | 0 |
| Hard errors | 0 |
| Coverage produced | 100.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py vega-lite --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 09:05). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 3 |
| Failing runs (label DB) | 3 |
| Fingerprints (min / max) | 2 / 2 |
| Labeled fingerprints | 2 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 2 |
| reevaluated_acceptable | 0 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 2 / 0 |
| Labeled detections (min) | 6/6 (100.0%) |
| Labeled runs (min) | 3/3 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 0 flagged rows |
| Jev audit | current |

**State:** complete.

## Environment / setup fixes

- Exported `PUPPETEER_SKIP_DOWNLOAD=true` and `PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true` in `install-and-run.sh` and `Dockerfile` to prevent Chromium downloads in the network-isolated container during install.
- Added `libjpeg-dev` and `libgif-dev` to `Dockerfile` for `node-canvas` source build fallback via `node-gyp`.
- Removed `--minWorkers=1` from vitest invocations in `install-and-run.sh` (rejected as an unknown option by vitest 4).

## Known gaps

The runtime suite (`test-runtime/`) is intentionally not collected (visual/browser tests).
