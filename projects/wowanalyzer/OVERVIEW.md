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

## Results

Source: `stats_output/report.txt` (generated 2026-09-19 14:29).

| Metric | Value |
|---|---|
| Commits processed | 10666 |
| Without test failures | 9741 |
| With test failures | 822 |
| Not applicable | 0 |
| Hard errors | 103 |
| Coverage produced | 99.0% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

Sourced from [`failure_labels_project.csv`](failure_labels_project.csv). All 1,385 recorded failures are genuine commit-era developer-facing failures (`acceptable` or `reevaluated_acceptable`).

| Signature / Failure Cluster | Classification | Coverage Impact | Action / Rationale |
|---|---|---|---|
| Integration & UI snapshot assertions (1,171 rows: `matches the statistic/suggestions/checklist snapshot`) | `acceptable` / `reevaluated_acceptable` | Valid partial coverage (exit code 1) | None. Genuine snapshot diffs from feature additions or un-updated golden snapshots (`jest -u`), plus Holy Paladin ABC `TypeError` (`26030c8`) and Jest 27 `setImmediate` upgrade (`88676a7`). |
| Unit / component assertion mismatches & logic errors (124 rows) | `acceptable` | Valid partial coverage (exit code 1) | None. Genuine commit-level test assertions, including `SpellCalculations.test.js` stats mismatches and `fetchWclApi` test-mode guards (`Unable to query WCL during test`). |
| `Cannot find module` (missing imports / files, 69 rows) | `acceptable` / `reevaluated_acceptable` | Valid partial coverage (exit code 1) | None. Target files were omitted from commits (e.g. `AugmentRuneChecker.ts`, `Arrow.tsx`, `sanctumofdomination.jpg`, or subfolder reorganization). In each case, the repository authors pushed fix commits shortly after. |
| `Test suite failed to run` (syntax & runtime crashes, 21 rows) | `acceptable` / `reevaluated_acceptable` | Valid partial coverage (exit code 1) | None. Developer-introduced syntax or runtime crashes (missing React import in JSX, duplicate imports, undefined soulbind properties, or checked-in `<<<<<<< HEAD` merge conflicts). Fixed in follow-up commits. |

## Environment / setup fixes

None.

## Known gaps

The `test:integration` sub-suite is not collected; the main `test` script covers the
same behavioral code.
