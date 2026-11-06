# prebid

**Repository:** https://github.com/prebid/Prebid.js
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `prebid`)
- **Node strategy:** Node 12 baseline; Node 16 override (2024-01-30 to 2024-06-14); Node 20 override (2024-06-14 to 2024-06-16) to align with CircleCI container upgrades prior to `.nvmrc` updates
- **Runners:** Karma, Mocha, Chai, Sinon, Webpack
- **Eras:**
  - 2021-01 to 2022-08: Node 12, `@jsdevtools/coverage-istanbul-loader` instrumenter
  - 2022-08 to 2024-01: Node 12, `babel-plugin-istanbul` instrumenter (PR #8819)
  - 2024-01 to 2024-06: Node 16 (overridden), `babel-plugin-istanbul`
  - 2024-06 to present: Node 20, chunked coverage (`build_coverage_chunks_*`)

## Development style

- **PR merging strategy:** Squash and merge
- **Merge convention:** `Title (#<PR>)`
- **Direct commits:** Minimal / bot-only (dependency bumps, release versions)
- **JS/TS code impact of direct commits:** Negligible
- **Issue tracking discipline:** High (PR-gated)
- **Workflow notes:** Standard feature branch PR workflow with automated CircleCI gates and required peer reviews.

## Coverage collection

- **Suites collected:** `unit` (`build_unit`, `build_coverage_chunks_*`) → Karma / Mocha via `npx gulp test-coverage`
- **Suites excluded:** `e2e` (`gulp e2e-test`) → BrowserStack / WebdriverIO cloud device testing requiring external credentials
- **Coverage tool / config:** Istanbul via `babel-plugin-istanbul` / `@jsdevtools/coverage-istanbul-loader` configured in `karma.conf.maker.js`
- **LCOV production:** Emitted by Karma `karma-coverage` reporter to `build/coverage/lcov.info`

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (11 failing runs inspected; all developer-facing assertion/mock failures)
- [x] complete run (5972/5972 processed)
- [x] complete test failure check (322/322 fingerprints labeled: 292 acceptable, 30 reevaluated_acceptable, 0 problematic)
- [x] complete JEV test failure check (343/343 labeled, 0 pipeline issues; audit: [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-11-06 10:35).

| Metric | Value |
|---|---|
| Commits processed | 5972 |
| Without test failures | 5299 |
| With test failures | 543 |
| Not applicable | 10 |
| Hard errors | 120 |
| Coverage produced | 98.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py prebid --stats` (window `min`, run 2026-11-06) and `stats_output/report.txt` (generated 2026-11-06 10:35). Labels: [`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv) (diagnostic window). These CSVs are the single source of truth; this section reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 543 |
| Failing runs (label DB) | 542 |
| Fingerprints (min / max) | 322 / 855 |
| Labeled fingerprints | 322 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 292 |
| reevaluated_acceptable | 30 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 39 / 283 |
| Labeled detections (min) | 1695/1695 (100.0%) |
| Labeled runs (min) | 542/542 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 0 flagged rows |
| Jev audit | current ([`jev_audit.md`](label_analysis/jev_audit.md)) |

**State:** complete.

## Environment / setup fixes

- **Chromium root sandbox wrapper:** Added `RUN touch /.dockerenv` and wrapped `/usr/bin/chromium` with `--no-sandbox` in [`Dockerfile`](Dockerfile) to ensure rootless Podman execution works cleanly with Karma.
- **Node version override:** Configured temporal override in [`config.json`](../../config.json) mapping commits from Jan 30, 2024 to June 16, 2024 to Node 16 and Node 20 to eliminate syntax errors (`??`) when running modern karmaRunner scripts.
- **Self-expiring timestamp sed patch:** Added line patch in [`install-and-run.sh`](install-and-run.sh) replacing expired timestamp `1768600800000` (expired Jan 16, 2026) with `4102444800000` (year 2100) in `test/spec/modules/invibesBidAdapter_spec.js` (fixed upstream in PR #14355).
- **PhantomJS WayPack proxy:** Added `PHANTOMJS_CDNURL` through WayPack request proxy and `--max-http-header-size=80000` in [`install-and-run.sh`](install-and-run.sh) to resolve Bitbucket binary downloads.
- **Chrome Headless disconnect timeout archive (`chrome_headless_disconnect_timeout`):** Archived 5 commits (`d632c95b`, `28ccb4eb`, `668f2fec`, `78a27e7a`, `65fd43d2`) where Karma browser disconnected after 5 attempts under 20-worker load; re-ran cleanly ([`archive/chrome_headless_disconnect_timeout/README.md`](archive/chrome_headless_disconnect_timeout/README.md)).
- **Karma chunk assertion guard (`assert_suite_ran`):** Added chunk validation in [`install-and-run.sh`](install-and-run.sh) and [`helper/assert-suite-ran.sh`](../../helper/assert-suite-ran.sh) asserting all chunks finish with >0 tests. Aborts with exit 1 if any chunk reports 0 tests or fails to finish, preventing partial coverage leaks.
- **Zero tests completed archive (`zero_tests_completed`):** Archived 2 commits (`705c1d767`, `adf81ba022`) where Chunk 5 hit an uncaught `ReferenceError` in `greenbidsBidAdapter_spec.js` and completed 0 tests; correctly converted to hard errors ([`archive/zero_tests_completed/README.md`](archive/zero_tests_completed/README.md)).
- **Flaky early suite completion archive (`flaky_early_suite_completion`):** Archived 87 monolithic runs (including `3529b591`, `f48fa6f9`, `2bcba397`) that suffered premature Mocha test suite truncation (~50% tests run, line coverage ~50–62% due to unhandled async timer callbacks) to [`archive/flaky_early_suite_completion/`](archive/flaky_early_suite_completion/) for clean re-run.
- **Chunking introduction single-pass backport (`chunking_single_pass_backport`):** Backported upstream commit `e953c2f91` (PR #13234) forcing `TEST_CHUNKS: '1'` during `testCoverage` in `install-and-run.sh` for the 56-commit window between `36d7454ca` and `e953c2f91~1` (including `ab1ddb939ba6`) before multi-chunk coverage merging was added upstream in PR #13483. 56 affected runs archived to [`archive/chunking_single_pass_backport/`](archive/chunking_single_pass_backport/) for clean re-run.
- **dgkeyword fake timers backport (`dgkeyword_fake_timer_backport`):** Backported upstream commit `df6cda5e2` (PR #13464) using `sinon.useFakeTimers()` in `test/spec/modules/dgkeywordRtdProvider_spec.js` to freeze the clock during real-time timeout tests, eliminating orphaned `request.respond()` timer collisions that prematurely truncated Mocha suites. 9 affected commits archived to [`archive/dgkeyword_fake_timer_backport/`](archive/dgkeyword_fake_timer_backport/) for clean re-run.

## Known gaps

- **Upstream instrumentation breakage (Aug 3–15, 2022, 54 commits):** 12-day window between commit `db2a333f2` and PR #8819 (`902cfc087`) where upstream `gulp test-coverage` crashed with `coverage-istanbul-loader` (`merge-source-map` index error); resolved upstream by switching to `babel-plugin-istanbul`.
- **Upstream build macro error window (July 28–29, 2025, 34 commits):** PR #13685 introduced build-time macro errors (`$$PREBID_GLOBAL$$` deprecation) in adapter specs; resolved upstream next day in PR #13688 (`f66e4c493`).
- **Committed spec syntax errors (22 commits):** Direct developer commits introducing parse/syntax errors in spec files (e.g. unterminated regex `/` in `conversantBidAdapter_spec.js` at `78fb35f5c3`).
- **Uncaught global pollution in short-lived submodule commits (May 2021, 2 commits):** Commits `e97db76c92` and `59b0fc9c03` introduced `dgkeywordRtdProvider_spec.js` with global `pbjs` state mutation that threw `TypeError: Cannot read properties of undefined (reading 'adUnits')` in subsequent tests (`openxAnalyticsAdapter_spec.js`), halting the suite at test #5,309 (~63.9% coverage). Both commits broke upstream CI and were immediately reverted in git history within hours (`c78238e8d` and `b5f15cf6a`). Left unpatched as authentic developer breakage.
- **Missing adapter imports / deleted files (3 commits):** Upstream commits referencing deleted spec helpers or invalid polyfills (`prebidjs-polyfill/includes.js`, reverted upstream 4 hours later).
- **Transient network timeouts (3 commits):** Heavy 20-worker concurrent load package registry timeouts.
