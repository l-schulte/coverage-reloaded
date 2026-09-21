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
- [x] complete test failure check (922 fingerprints: 728 acceptable, 192 reevaluated_acceptable, 2 problematic, 0 unclear)

## Results

Source: `stats_output/report.txt` (generated 2026-09-21 19:10).

| Metric | Value |
|---|---|
| Commits processed | 16406 |
| Without test failures | 15875 |
| With test failures | 433 |
| Not applicable | 0 |
| Hard errors | 98 |
| Coverage produced | 99.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Commits Affected | Coverage Impact | Action |
|---|---|---|---|---|
| `Module @vue/vue2-jest in the transform option was not found` / `Cannot resolve "@vue/vue2-jest"` | Developer-facing | 29 | 0% (hard error) | Documented. 28 commits on Vue 3 branch (`5d0698afbf`..`2de759cc11`, June 2025) had `@vue/vue3-jest` in `package.json` but left `@vue/vue2-jest` in `jest.config.js` (fixed upstream in [`2f1bb6f64a`](https://github.com/nextcloud/spreed/commit/2f1bb6f64a276a041322de015e45b0995636a09f)); 1 commit ([`d9d0a4c1e6`](https://github.com/nextcloud/spreed/commit/d9d0a4c1e6f0ea47a54e0490eda90caef5c13436)) bumped `@vue/cli-plugin-unit-jest` without newly required peer dep `@vue/vue2-jest`. |
| `Test environment jest-environment-jsdom cannot be found` | Developer-facing | 3 | 0% (hard error) | Documented. Intermediate commits during Vitest migration ([`da973c3c13`](https://github.com/nextcloud/spreed/commit/da973c3c1343ed0ed6cdf35a47744c2199d4e017), [`409c76d108`](https://github.com/nextcloud/spreed/commit/409c76d10803fd55cd84a519f51aaf4fd750fd58), [`2de759cc11`](https://github.com/nextcloud/spreed/commit/2de759cc114ee62efd38b72bb0c382dbdb722307), August 2025) where Jest dependencies were uninstalled before `jest.config.js` and `"test": "jest"` were replaced (fixed upstream in [`176c837c8e`](https://github.com/nextcloud/spreed/commit/176c837c8e95504a6de0b16aa347b80710a5bce1)). |
| `Module ts-jest in the transform option was not found` | Developer-facing | 1 | 0% (hard error) | Documented. Commit [`ec9e5d9ec5`](https://github.com/nextcloud/spreed/commit/ec9e5d9ec560dd72a29bb23a6c9dfd1c198d617c) configured `ts-jest` in `jest.config.js` without adding `ts-jest` to `package.json`. |
| `Vue packages version mismatch (vue 2.7 vs vue-template-compiler 2.6)` | Developer-facing | 3 | 0% (hard error) | Documented. Dependabot PRs (`a82250b687`, `4d86436d77`, `75851760a0`, July–August 2022) bumped `vue` to `^2.7.x` without installing or bumping `vue-template-compiler` to match. |
| `Jest child process worker crash (Call retries were exceeded / 4 child process exceptions)` | Pipeline setup artifact (`problematic`) | 7 | Valid coverage produced (~331KB to 520KB), exit code 1 | Documented. Jest/vue-cli-service child process worker crash on specific heavy suites (`conversationsService.spec.js`, `Reactions.spec.js`). Unaffected by worker concurrency bounds; non-bailed test runs produced complete LCOV coverage. |
| Developer-facing test failures (syntax errors, missing imports, unmocked Pinia, TS errors) | Developer-facing (`acceptable` / `reevaluated_acceptable`) | 433 | Valid coverage produced | All 433 test-failing runs classified across 920 fingerprints. 192 fingerprints re-assessed as `reevaluated_acceptable` (including 40 TypeScript compiler errors, unmocked Pinia setups, and unmerged PR syntax errors); 728 fingerprints verified as `acceptable`. |

## Environment / setup fixes

- Removed unused `npm install -g nyc` from `install-and-run.sh` which previously failed on missing `electron-to-chromium` in Verdaccio tarball cache. 5 affected commits and 2 transient timeout commits re-ran successfully (archived in `archive/fix_nyc_install/`).

## Known gaps

- **Author timestamp vs dependency release skew (62 commits):** Commits authored on long-lived branches requiring packages published after the author date (56 commits requiring `@vue/cli-service@^4.5.9+`, 5 commits requiring `vue-eslint-parser@^8.0.1`, and 1 commit requiring `@nextcloud/vue@^4.2.0`). Under the author-timestamp snapshotting policy ([`STUDY_DECISIONS.md §1`](../../STUDY_DECISIONS.md)), WayPack excludes post-author-date releases, causing `npm install --force` to skip them.
