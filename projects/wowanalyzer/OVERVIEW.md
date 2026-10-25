# wowanalyzer

**Repository:** https://github.com/wowanalyzer/wowanalyzer
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `wowanalyzer`).
  The `Dockerfile` Node strategy is disabled.
- **Node strategy:** `min_node_version = 12`.
- **Runners:** `jest`, `react-app-rewired`, `vitest`.
- **Eras:** `react-app-rewired` (jest) until the vitest migration
  (`bd58e15539`, 2024-04-10). Until 2022-09-05 the repository shipped
  `integrationTests/*.test.ts` files; these were deleted by `1409e34b3a`
  (2022-09-05, "reorganize back into a mono-package").

## Development style

- **PR merging strategy:** Transitioned (Merge commit 2021–2023 → Squash and merge 2024–2025).
- **Merge convention:** `Merge pull request #<PR> from <branch>` (2021–2023, 64–92%); `<Title> (#<PR>)` (2024–2025, 77–86%).
- **Direct commits:** Low (5.9% human direct commits, 177 commits).
- **JS/TS code impact of direct commits:** Low — CI labeler updates, game expansion branch setup (Midnight), and metric upload filters by lead maintainer.
- **Issue tracking discipline:** High (community theorycrafting PRs tracked via GitHub).
- **Workflow notes:** Shifted from long-standing merge-commit history to Squash & Merge in 2024.

## Coverage collection

- **Suites collected:** the main `test` script. It is a strict superset of the
  sub-suites in every era, so no sub-suite is needed. `test:interface` and
  `test:parser` exclude integration tests via
  `--testPathIgnorePatterns integrationTests`, and `test:integration` is a
  path-filtered view.
- **Suites excluded:** `test:integration` (removed with the vitest migration).
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done
- [x] failed tests doublechecked
- [x] complete run
- [x] complete test failure check
- [x] complete JEV test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-10-25 16:39).

| Metric | Value |
|---|---|
| Commits processed | 10666 |
| Without test failures | 9857 |
| With test failures | 714 |
| Not applicable | 0 |
| Hard errors | 95 |
| Coverage produced | 99.1% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py wowanalyzer --stats` (window `min`, run 2026-10-25) and `stats_output/report.txt` (generated 2026-10-25 16:39). Labels: [`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv) (diagnostic window). These CSVs are the single source of truth; this section reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 714 |
| Failing runs (label DB) | 714 |
| Fingerprints (min / max) | 29076 / 34606 |
| Labeled fingerprints | 29076 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 24358 |
| reevaluated_acceptable | 4688 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 30 |
| Manual / auto-propagated labels | 47 / 29029 |
| Labeled detections (min) | 122563/122563 (100.0%) |
| Labeled runs (min) | 714/714 (100.0%) |
| Jev mode | dedup-keyword |
| Jev pipeline issues | 11 flagged rows (families in dedup-keyword mode) |
| Jev audit | current ([`label_analysis/jev_audit.md`](label_analysis/jev_audit.md)) |

**State:** complete.

## Environment / setup fixes

- **Monorepo analysis directory coverage (`include_analysis_coverage`):** Prior to the 2022-09-05 monorepo reorganization (commit `1409e34b3a`), the core class analysis packages lived in the root-level `analysis/` folder outside `src/`. Create React App's default `collectCoverageFrom` glob (`src/**/*.{js,jsx,ts,tsx}`) strictly ignored `analysis/`, omitting over 1,700 source files (~65% of the codebase) from LCOV across the entire pre-split era. Fixed in `install-and-run.sh` by dynamically injecting `--collectCoverageFrom="{src,analysis}/**/*.{js,jsx,ts,tsx}"` into `react-app-rewired test` when `analysis/` exists. All 3,722 affected runs were archived to [`archive/include_analysis_coverage/`](archive/include_analysis_coverage/) to permit a clean re-run.

- **Strip-ansi via npx registry fallback (`fix_strip_ansi_npx_registry`):** npm 6's `npx` (node 12/14 commits) silently ignores `--registry=$VERDACCIO_REGISTRY` and falls back to the configured registry — WayPack's time-scoped snapshot, which predates `strip-ansi-cli@3.0.0` (published 2021-04-16) for every older commit. The `jest_check_executed` summary check then died with `ETARGET: No matching version found for strip-ansi-cli@3.0.0` *after* all tests had passed, discarding valid coverage for every pre-2021-04-16 commit. Fixed in `install-and-run.sh` by installing once via `npm install -g --registry="$VERDACCIO_REGISTRY" strip-ansi-cli@3.0.0` (plain `npm install` honors `--registry` even on npm 6, unlike `npx`) and invoking the `strip-ansi` binary directly. All 402 affected runs were archived to [`archive/fix_strip_ansi_npx_registry/`](archive/fix_strip_ansi_npx_registry/) to permit a clean re-run.

- **Node 16 override for vega-lite nullish assignment (`node16_vega_lite_syntax_error`):** Commits between `1673624560` and `1674253981` (Jan 13–20, 2023) pulled `vega-lite@5.6.0`, which contained nullish assignment operators (`??=`) requiring Node >= 15. The pipeline ran these commits on Node 14 (due to default LTS offset and no explicit `engines` field in `package.json`), causing Jest to crash with `SyntaxError: Unexpected token '??='` before executing tests. Project CI used Node 16 (`.github/workflows/build.yml: node-version: '16.x'`). Fixed by adding `node_version_overrides` in `config.json` setting Node 16 for timestamp range `1673624560..1674253981`. All 110 affected commits were archived to [`archive/node16_vega_lite_syntax_error/`](archive/node16_vega_lite_syntax_error/) and re-run, producing 100% valid coverage (109 passed with exit 0, 1 genuine test failure with exit 1).

## Known gaps

The `test:integration` sub-suite is not collected; the main `test` script covers the
same behavioral code.
