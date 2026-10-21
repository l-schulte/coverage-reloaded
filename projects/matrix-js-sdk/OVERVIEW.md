# matrix-js-sdk

**Repository:** https://github.com/matrix-org/matrix-js-sdk
**Status:** active

## Test infrastructure

- **Package manager:** yarn (`yarn@1`, `yarn.lock`) throughout the study window
  (see [`config.json`](../../config.json) → `matrix-js-sdk`).
- **Node strategy:** default, with a targeted override to Node 16 for epoch
  `1658323000`–`1675957462` (2022-07-20 to 2023-02-09). The override avoids two
  upstream toolchain bugs that only manifest on Node 18: the `@matrix-org/olm`
  ≤ 3.2.12 `fetch(<path>)` WASM loader failure, and the `@sinonjs/fake-timers` 9.x
  `Cannot assign to read only property 'performance'` failure.
- **Runners:** `jest` (26 → 29 → 30 across the window).
- **Eras:**
  - 2021-01-04 to 2021-04-28: `test` = `jest spec/ --coverage` (coverage on by
    default).
  - 2021-04-28 to 2026-01-01: `test` = `jest`; coverage reached via `--coverage`.
  - `spec/unit` and `spec/integ` exist for the whole window.
  - `spec/browserify` exists until 2023-10-03 (removed upstream).
  - The 2026-01-15 switch to Vitest is outside the window.

## Development style

- **PR merging strategy:** Transitioned (Merge commit in 2021 → Squash and merge in early 2022).
- **Merge convention:** `Merge pull request #<PR> from <branch>` (2021, 67%); `<Title> (#<PR>)` (2022–2025, 84–91%).
- **Direct commits:** Minimal (3.9% human direct commits, 111 commits).
- **JS/TS code impact of direct commits:** Negligible — SonarCloud workflow actions and CI action version updates.
- **Issue tracking discipline:** High (pull requests linked to Element/Matrix tracking issues).
- **Workflow notes:** Transitioned from classic GitFlow merge commits on `develop` to GitHub Squash & Merge in early 2022.

## Coverage collection

- **Suites collected:** `unit` (`spec/unit`) and `integration` (`spec/integ`),
  both via `jest --coverage`. For commits whose `test` script hardcodes a `spec/`
  path (2021-01-04 to 2021-04-28), a single combined run is used.
- **Suites excluded:** `spec/browserify` only (a browser-bundle smoke test that
  requires `yarn build` and would instrument `dist/`; removed upstream on
  2023-10-03). Every in-window `.spec`/`.test` file lives under `spec/unit` or
  `spec/integ`, both of which are collected — no other suites exist.
- **Coverage tool / config:** jest's Istanbul instrumentation; from 2021-04-28 the
  project sets `collectCoverageFrom: src/**/*.{js,ts}`. The earlier era has no such
  config, so the run forces the same glob to keep `spec/` helpers out of the
  exposure variable.
- **LCOV production:** the run forces `--coverageReporters=lcov` because some
  commits configure only the `text` reporter; output is `coverage/lcov.info` per
  suite, moved out as `unit.lcov` / `integration.lcov`.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked
- [x] complete run (4989 commits processed; 0 pending)
- [x] complete test failure check (all 843 failing runs labeled; 0 problematic/unclear)
- [x] complete JEV test failure check (all 44 flagged fingerprints audited; see [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 22:13).

| Metric | Value |
|---|---|
| Commits processed | 4989 |
| Without test failures | 4139 |
| With test failures | 843 |
| Not applicable | 0 |
| Hard errors | 7 |
| Coverage produced | 99.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py matrix-js-sdk --stats` (window `min`, run 2026-10-21) and
`stats_output/report.txt` (generated 2026-10-21 22:13). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 843 |
| Failing runs (label DB) | 843 |
| Fingerprints (min / max) | 1247 / 1648 |
| Labeled fingerprints | 1247 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 911 |
| reevaluated_acceptable | 336 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 53 / 1194 |
| Labeled detections (min) | 6283/6283 (100.0%) |
| Labeled runs (min) | 843/843 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 44 flagged rows |
| Jev audit | current |

**State:** complete.

All 44 Jev-flagged fingerprints originate from 14 union runs and were audited
against the project's git history; the audit is recorded in
[`label_analysis/jev_audit.md`](label_analysis/jev_audit.md).

## Environment / setup fixes

- `--coverageReporters=lcov` forces LCOV on commits whose jest config emits only
  `text`.
- `--collectCoverageFrom='src/**/*.{js,ts}'` limits coverage to source on the
  early era, which otherwise instruments `spec/` helpers.
- `--forceExit` prevents in-band jest runs from hanging on open handles.
- `--testTimeout=30000` absorbs timing-sensitive crypto tests that intermittently
  exceed jest's default 5 s under parallel-run load.
- `--testPathIgnorePatterns` drops `spec/browserify` (see Coverage collection).
- `--setupFiles=/coverage_reloaded/silence-console.cjs` no-ops
  `console.log`/`debug`/`info`/`warn` while preserving `console.error`.
- Node 16 override for epoch `1658323000`–`1675957462` (see Test infrastructure).
- yarn-only install with a loud failure for any other package manager.
- `resolve_and_pin` for `gitlab.matrix.org`, `codeload.github.com`, and
  `packages.matrix.org`: these hosts appear as literal `resolved` URLs in
  `yarn.lock` (olm, eslint-plugin-matrix-org) and are not rewritten to WayPack,
  so intermittent DNS failures (`getaddrinfo EAI_AGAIN`) aborted installs on 62
  commits. Pinning them at run start makes resolution robust.

## Known gaps

- `spec/browserify` is deliberately not collected (requires the browser build;
  see Coverage collection).
- 7 commits produce no coverage (`report.txt`):
  - 3 lockfile inconsistencies under `--frozen-lockfile` (`dd8c157bb9` on
    2021-12-09 bumped olm in `package.json` without updating `yarn.lock`;
    `b711781f16` on 2022-07-29 and `22c5999fed` on 2022-08-01 dropped
    `sdp-transform` from `yarn.lock`).
  - 3 git-ref drifts on external submodule/git dependencies.
  - 1 WebRTC uncaught rejection crash (`b4f8b0fe4f` on 2023-01-24 dereferenced
    `this.localUsermediaStream` while `undefined` in an async timer callback).
