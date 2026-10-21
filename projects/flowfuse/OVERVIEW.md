# flowfuse

**Repository:** https://github.com/FlowFuse/flowfuse
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `flowfuse`).
- **Node strategy:** `node_version_delay_months = 24`, `min_node_version = 14`.
- **Runners:** `mocha` (forge, unit and system suites) and `vitest` (frontend suite).
- **Eras:** `test:unit` initially ran the mocha suite; later commits split it into
  `test:unit:forge` (mocha) and `test:unit:frontend` (vitest), with `test:unit` kept
  only as a fallback when neither split script exists. `test:system` runs mocha
  throughout. Only root scripts exist.

## Development style

- **PR merging strategy:** Merge commit (96.1% of first-parent commits).
- **Merge convention:** `Merge pull request #<PR> from <branch>`.
- **Direct commits:** Negligible (0.6% human direct commits, 19 commits).
- **JS/TS code impact of direct commits:** Negligible — emergency reverts and CI script adjustments by core maintainers.
- **Issue tracking discipline:** High (all behavioral changes gated through reviewed PRs).
- **Workflow notes:** Clean, disciplined 2-parent merge commit workflow. Feature branches preserve all commit steps.

## Coverage collection

- **Suites collected:** `forge-unit` → mocha; `frontend-unit` → vitest; `unit` →
  mocha (fallback when the split scripts are absent); `system` → mocha.
- **Suites excluded:** end-to-end (Cypress) and documentation tests.
- **Coverage tool / config:** `nyc`. From the nyc era onward the project's own `nyc`
  and `.nycrc.json` (`include: forge/**`) drive collection. The 641 pre-nyc-era
  commits (2021-07-29 to 2022-03-21) are instrumented with an injected `nyc@15`
  using `--all --include 'forge/**' --include 'ee/**'`, reproducing the project's
  own file set so the exposure variable is produced by one tool and one file set
  across the whole history ([`archive/switch_to_nyc/`](archive/switch_to_nyc/)).
- **Focus markers:** commits whose collected suites contain a committed `.only` are
  marked not-applicable rather than recording subset coverage (see
  [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §2).
- **LCOV production:** `nyc` with an `lcov` reporter. The frontend suite emits its
  own `lcov.info` through the version-matched Vitest coverage provider.

## Checklist

- [x] 100 done (92/100)
- [x] failed tests doublechecked
- [x] complete run (nyc-only re-run of the pre-nyc commits completed)
- [x] complete test failure check (20288 fingerprints, 100% labeled; 1540/1540 failing runs covered)
- [x] complete JEV test failure check (dedup-keyword artifact, 760 families, 42 flagged; audit current)

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 21:47).

| Metric | Value |
|---|---|
| Commits processed | 15802 |
| Without test failures | 13157 |
| With test failures | 1540 |
| Not applicable | 319 |
| Hard errors | 786 |
| Coverage produced | 94.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

Coverage produced (94.9%) is above the 90% inclusion criterion; 786 commits are hard
errors and 319 are not applicable.

## Failure triage

Source: `python check_failures_v2.py flowfuse --stats` (window `min`, run 2026-10-21)
and `stats_output/report.txt` (generated 2026-10-21 21:47). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 1540 |
| Failing runs (label DB) | 1540 |
| Fingerprints (min / max) | 20288 / 29056 |
| Labeled fingerprints | 20288 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 6616 |
| reevaluated_acceptable | 808 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 12864 |
| Manual / auto-propagated labels | 32 / 20256 |
| Labeled detections (min) | 38308/38308 (100.0%) |
| Labeled runs (min) | 1540/1540 (100.0%) |
| Jev mode | dedup-keyword |
| Jev pipeline issues | 42 flagged families |
| Jev audit | current |

**State:** complete.

No `problematic` or `unclear` families. The `max` window is built and unlabeled;
it is a diagnostic window only. The frontend suite anchors on the inline `×` tick
and on `Error: [vite-node]` lines, while `Failed Tests` summary blocks are excluded
to avoid double counting and `Failed Suites` blocks are scanned
([`label_analysis/failure_patterns.json`](label_analysis/failure_patterns.json)).

The 42 Jev-flagged families were audited against git history; no flag traces to the
pipeline (see [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md)).

## Environment / setup fixes

- **SQLite `:memory:` connection race (`pool-shim`).** Symptom: cascades of
  `no such table: MetaVersions` / `duplicate column name: editorAffinity` and 0%
  coverage or crashes. Root cause: SQLite `:memory:` is per-connection, so pooled
  connections see different empty databases and migrations are re-applied. Fix:
  `pool-shim.js` force-injects `pool: { max: 1, min: 1 }` into any Sequelize
  constructor using `storage: ':memory:'`; loaded via `NODE_OPTIONS` in
  [`install-and-run.sh`](install-and-run.sh) and copied by the
  [`Dockerfile`](Dockerfile). Logs: [`archive/pool-shim/`](archive/pool-shim/).
- **`sqlite3` native module built from source.** Symptom: `Could not locate the
  bindings file` and `GLIBC_2.33 not found` crashes in the forge and system suites.
  Root cause: `npm rebuild sqlite3` re-downloaded a prebuilt addon incompatible with
  the installed Node ABI or the image glibc. Fix: when `require('sqlite3')` fails to
  load, run `npm_config_build_from_source=true npm rebuild sqlite3` in
  [`install-and-run.sh`](install-and-run.sh). Logs:
  [`archive/bindings/`](archive/bindings/),
  [`archive/pre_glibc_fix/`](archive/pre_glibc_fix/).
- **Git submodules for `file:sub_modules/` dependencies.** Symptom: `npm ERR! code
  ENOLOCAL: Could not install from "sub_modules/flowforge-driver-localfs"`. Root
  cause: `package.json` declared local dependencies pointing at Git submodules that
  `execute.sh` does not initialize. Fix: run `git submodule update --init` before
  `npm install` when `.gitmodules` exists and `package.json` declares
  `file:sub_modules/` dependencies ([`install-and-run.sh`](install-and-run.sh)).
  Logs: [`archive/fix_submodules/`](archive/fix_submodules/).
- **Cypress binary download bypass.** Symptom: `npm install` failing with
  `getaddrinfo EAI_AGAIN download.cypress.io`. Root cause: the Cypress postinstall
  downloads desktop binaries from a blocked external domain. Fix:
  `CYPRESS_INSTALL_BINARY=0` in [`install-and-run.sh`](install-and-run.sh). Logs:
  [`archive/fix_cypress_download/`](archive/fix_cypress_download/).
- **Version-matched Vitest coverage provider.** Symptom: `test:unit:frontend`
  crashing with `Cannot find module 'vitest/coverage'` and no `lcov.info`. Root
  cause: an unversioned provider is incompatible with Vitest `< 0.32`, which
  requires `@vitest/coverage-c8` at an exact version. Fix:
  [`install-and-run.sh`](install-and-run.sh) installs `@vitest/coverage-c8@$VERSION`
  (< 0.32) or `@vitest/coverage-v8@$VERSION` (≥ 0.32) only when no provider is
  present. Logs: [`archive/fix_vitest_dependency/`](archive/fix_vitest_dependency/).

The `archive/` folders hold the archived logs and outputs only; none contains a
`README.md`.

## Known gaps

- **Committed focus markers (`.only`).** 81 collected commits contain a
  `describe.only`/`it.only` in a collected suite (`test/unit/` or `test/system/`;
  40 distinct spec files, 2022-09 → 2025-12). The forge suite runs under mocha,
  whose `.only` is run-global and would emit a valid-looking but unrepresentative
  `lcov`, so these commits are marked not-applicable by
  `na_if_focus_marker --runner mocha --runner vitest test/unit test/system` (see
  [`STUDY_DECISIONS.md`](../../STUDY_DECISIONS.md) §2). The 79 commits that previously
  recorded subset coverage were re-run and the 2 hard errors were reclassified
  ([`archive/reclassify_only/`](archive/reclassify_only/)).
- **Excluded suites.** The Cypress end-to-end suite under `test/e2e` and the
  documentation tests are not collected; Cypress is still installed with
  `CYPRESS_INSTALL_BINARY=0`.
- **Lint-gated `test` script.** On the early `unit` suite, `npm run test` runs
  `npm run lint && mocha`, so a commit with lint errors fails the suite before any
  test executes.
