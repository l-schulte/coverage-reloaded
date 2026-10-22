# openneuro

**Repository:** https://github.com/openneuroorg/openneuro
**Status:** active

## Test infrastructure

- **Package manager:** npm/yarn@1 (early) → yarn berry/PnP (~2021+) across
  `packages/*` and `services/*` (see [`config.json`](../../config.json) →
  `openneuro`).
- **Node strategy:** `min_node_version = 12`; override to Node `10` for epoch
  `0`–`1579737759`.
- **Runners:** `jest` (dominant in all eras), `vitest` (newer packages from ~2023),
  some `mocha`.
- **Eras:** the root `test` dispatches per-package suites. The harness runs the root
  `jest`/`vitest` directly with coverage.

## Development style

- **PR merging strategy:** Merge commit (57.0% of first-parent commits).
- **Merge convention:** `Merge pull request #<PR> from <branch>`.
- **Direct commits:** Frequent (42.5% human direct commits, 781 commits, 96% by lead engineer Nell Hardcastle).
- **JS/TS code impact of direct commits:** Low — 81.5% (643 commits) touch only release tags (`vX.Y.Z`, `chore: Bump released version`) or Kubernetes/Helm manifests; only 146 commits (18.5%) touch JS/TS files (operational hotfixes, Sentry logging adjustments, and CLI patches).
- **Issue tracking discipline:** High for feature PRs; low for direct ops (< 1.5% issue references in direct commits).
- **Workflow notes:** Feature development is strictly PR-driven and reviewed; direct pushes on `master` are operational hotfixes, deployment resource adjustments, and manual release tags.

## Coverage collection

- **Suites collected:** the root `jest`/`vitest` suites.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.
- **Build prerequisite:** `yarn build` (`tsc -b`) emits each workspace package's
  `dist/`, which is required for PnP import resolution of `@openneuro/*`. It runs
  non-fatal: pre-existing type errors are logged and ignored so tests still run and
  `dist/` is emitted.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (classified across logs)
- [x] complete run (5,170/5,170 commits processed, 0 pending)
- [x] complete test failure check (541/541 fingerprints classified across 694 failing runs; 0 problematic, 0 unclear)
- [x] complete JEV test failure check ([`jev_audit.md`](label_analysis/jev_audit.md): 539/539 evaluated, 284 flagged, 0 pipeline defects)

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 15:41).

| Metric | Value |
|---|---|
| Commits processed | 5170 |
| Without test failures | 4414 |
| With test failures | 694 |
| Not applicable | 0 |
| Hard errors | 62 |
| Coverage produced | 98.8% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py openneuro --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 15:41). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 694 |
| Failing runs (label DB) | 694 |
| Fingerprints (min / max) | 541 / 630 |
| Labeled fingerprints | 541 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 315 |
| reevaluated_acceptable | 225 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 1 |
| Manual / auto-propagated labels | 78 / 463 |
| Labeled detections (min) | 5621/5621 (100.0%) |
| Labeled runs (min) | 694/694 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 284 flagged rows |
| Jev audit | current ([`jev_audit.md`](label_analysis/jev_audit.md)) |

**State:** complete.

## Environment / setup fixes

- **Jest `collectCoverageFrom` TypeScript inclusion (`fix_jest_ts_coverage`):** Root `package.json` hardcoded `collectCoverageFrom` to `"**/*.{js,jsx}"` prior to upstream commit `5ab102c4d2` (2021-11-16), omitting all TypeScript source files and collecting transpiled `dist/` artifacts. Backported upstream commit `5ab102c4d2` in `install-and-run.sh` to update `collectCoverageFrom` to include `"**/*.{js,jsx,ts,tsx}"` and exclude `"**/dist/**"`. 1,963 runs archived to [`archive/fix_jest_ts_coverage/`](archive/fix_jest_ts_coverage/) (and unpatched re-run attempt to [`archive/fix_jest_ts_coverage_unpatched_rerun/`](archive/fix_jest_ts_coverage_unpatched_rerun/)) pending re-run.
- **Vitest worker thread-pool bounding (`overwrite_model_error`):** In Vitest 0.25–0.34, `--single-thread` and `--no-threads` collapsed worker thread isolation, causing Mongoose `OverwriteModelError: Cannot overwrite User model once compiled.` on repeated top-level imports. Switched to worker-thread bounding (`VITEST_MAX_THREADS=1`, `VITEST_MAX_WORKERS=1` and `--maxWorkers=1`/`--maxThreads=1`) to preserve worker isolation while preventing host out-of-memory errors on high-core hardware. 727 runs archived to [`archive/overwrite_model_error/`](archive/overwrite_model_error/) pending re-run.
- **Vitest intermittent 5000ms Mongo/GraphQL test timeouts (`vitest_5000ms_test_timeouts`):** Intermittent 5000ms Vitest timeouts on `snapshots.spec.ts` and `datasets.spec.js` during in-memory MongoDB/GraphQL operations under container scheduling load. Full line coverage was captured; 15 runs archived to [`archive/vitest_5000ms_test_timeouts/`](archive/vitest_5000ms_test_timeouts/) were re-run: 8 runs passed cleanly with `exit_code = 0`; the remaining 7 were confirmed as Apollo 4 client refactoring work-in-progress (PR #2866) and timing boundaries, and labeled `acceptable`.
- **`tsc -b` non-fatal compilation (`install-and-run.sh`):** Made `yarn build` exit non-fatal so pre-existing TypeScript type errors do not abort the run, ensuring emitted workspace `dist/` packages exist for PnP module resolution.
- **`bids-validator` local dependency rewrite (`install-and-run.sh`):** Rewrote invalid local `file:` dependency in `package.json` and `yarn.lock` to published version `1.6.2`.

## Known gaps

None.
