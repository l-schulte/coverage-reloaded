# apollo-client

**Repository:** https://github.com/apollographql/apollo-client
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `apollo-client`).
  Version override: `npm@7.20.3` → `npm@8` for epoch `1627914966`–`1636403951`.
- **Node strategy:** default.
- **Runners:** `jest`.
- **Eras:** one full jest unit run for the whole window. The run is filed under two
  suite labels because the lcov file inherits the directory the project writes its
  coverage to: `src_unit` (2019-10-16 → 2022-09-08) when coverage lands in
  `src/coverage`, and `config_unit` (from 2020-05-20, dominant from 2022-06-28,
  through 2025-12-23) when it lands in `config/coverage`. The two labels never occur
  at the same commit. The `integration-tests/` workspace is Playwright end-to-end
  (off-limits), and `scripts/memory` / `integration-tests/node` are `node:test`
  smoke checks that exercise the built package rather than `src/`. Behavioral
  integration is already covered by the jest unit run over `src/__tests__`, so no
  separate integration suite is collected.

## Development style

- **PR merging strategy:** Squash and merge (57.4% in 2021–2025; 84%+ from 2023 onward).
- **Merge convention:** `<Title> (#<PR>)` (e.g. `Warn when rereading a partial cache result after a write (#13392)`).
- **Direct commits:** Moderate (26.2% bot direct commits, 9.2% human direct commits).
- **JS/TS code impact of direct commits:** Minimal — human direct commits touch CI configs, roadmap, release metadata, and Changeset OIDC publishing (`try to fix changeset publishing with OIDC`).
- **Issue tracking discipline:** High (features and fixes tracked via PRs and issues).
- **Workflow notes:** Contributor PRs are squashed. In 2021–2022, Renovate bot performed linear automerges for dependencies (`chore(deps): update ...`) without PR numbers; shifted to squash in 2023+. Releases use Changesets.

## Coverage collection

- **Suites collected:** the single jest unit run, recorded as `src_unit` or
  `config_unit` (see Eras).
- **Suites excluded:** Playwright end-to-end (`integration-tests/`) and the
  `node:test` smoke checks (`scripts/memory`, `integration-tests/node`).
- **Coverage tool / config:** jest's Istanbul coverage through the project's own
  `coverage` script (`jest --config ./config/jest.config.js --coverage`);
  [`patch-coverage.js`](patch-coverage.js) appends `--coverageReporters=lcov`.
- **LCOV production:** the run writes `<dir>/coverage/lcov.info`; the harness moves
  it out of the repository and files it as `src_unit` or `config_unit`, one lcov
  per commit.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [x] complete run (4462 commits processed; 0 pending)
- [x] complete test failure check (all 488 failing runs labeled; 0 problematic/unclear)
- [x] complete JEV test failure check (all 359 flagged fingerprints audited; see [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 20:03).

| Metric | Value |
|---|---|
| Commits processed | 4462 |
| Without test failures | 3921 |
| With test failures | 488 |
| Not applicable | 0 |
| Hard errors | 53 |
| Coverage produced | 98.8% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py apollo-client --stats` (window `min`, run 2026-10-21)
and `stats_output/report.txt` (generated 2026-10-21 20:03). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 488 |
| Failing runs (label DB) | 488 |
| Fingerprints (min / max) | 872 / 967 |
| Labeled fingerprints | 872 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 425 |
| reevaluated_acceptable | 447 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 16 / 856 |
| Labeled detections (min) | 2020/2020 (100.0%) |
| Labeled runs (min) | 488/488 (100.0%) |
| Jev pipeline issues | 359 |

**State:** complete.

All 359 Jev-flagged fingerprints originate from four runs and were audited against
the project's git history; the audit is recorded in
[`label_analysis/jev_audit.md`](label_analysis/jev_audit.md).

## Environment / setup fixes

- **Jest test timeouts under container load (`fix_jest_timeouts`):** 71
  timeout-affected runs were archived to
  [`archive/fix_jest_timeouts/`](archive/fix_jest_timeouts/) and re-run with
  `--testTimeout=20000`, applied in [`install-and-run.sh`](install-and-run.sh) and
  [`patch-coverage.js`](patch-coverage.js). See the
  [archive README](archive/fix_jest_timeouts/README.md) for the archived run list.

## Known gaps

- The Playwright end-to-end workspace (`integration-tests/`) and the `node:test`
  smoke checks (`scripts/memory`, `integration-tests/node`) are intentionally not
  collected.
- 53 commits produce no coverage (`report.txt`): 34 abort with exit code 127
  because a build binary is absent (`tsc` 27, `ts-node-script` 6, `rollup` 1), 10
  with exit code 2 (9 TypeScript build errors, 1 `npm install` failure), 7 with exit
  code 1 (5 `npm install` failures, 1 `SyntaxError: Cannot use import statement
  outside a module`, 1 unresolved `whatwg-fetch` import in `dist/`), and 2 hit the
  90-minute run timeout.
