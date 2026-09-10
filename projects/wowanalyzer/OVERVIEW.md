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

Source: `stats_output/report.txt` (generated 2026-09-10 14:35).

| Metric | Value |
|---|---|
| Commits processed | 10666 |
| Without test failures | 9631 |
| With test failures | 925 |
| Not applicable | 0 |
| Hard errors | 110 |
| Coverage produced | 99.0% |

## Known test failures

### WCL fetches in test mode (classification: acceptable)

`fetchWclApi` throws `Unable to query WCL during test` whenever
`import.meta.env.MODE === 'test'` (`src/common/fetchWclApi.ts:93-96`). Any test path
that reaches the live Warcraft Logs API therefore receives no data. This is a
code-level guard; the container has normal outbound network access.

The integration tests, including `survivalIntegrationTests.test.ts`, do not import
`fetchWclApi`. They load committed local `.zip` fight logs, and
`survivalIntegrationTests` passes in sampled runs (`1609476109`, `1610385843`). The
`Unable to query WCL during test` message is an unhandled promise rejection emitted
by component/unit tests (`ReportSelector.test.tsx`, `fetchWclApi.test.ts`) that call
the fetcher without awaiting; it does not affect integration-test results.

### Priest Discipline SpellCalculations assertion mismatch (classification: acceptable)

`SpellCalculations.test.js` reports `boltHealing` and `smiteHealing` about 5–10%
below expected across 7 assertions (for example, expected `22`, got `20`; expected
`39`, got `36`), using a `mockStatTracker()` with hardcoded stats. This is a
commit-level assertion failure reproducible by the original developers.

### Reclassified failures (label: `reevaluated_acceptable`)

These clusters were originally labeled `problematic`/`unclear` and reclassified as
commit-era developer-facing failures:

| Cluster | Evidence | Coverage impact |
|---|---|---|
| `Cannot find module` (38 rows) | 636 log hits across 25 unique (commit, module) pairs; each target is absent at its commit (`git show` verified). Broken/transitional commits that also fail upstream. | Suites that fail to load yield no coverage for that file (a commit-intrinsic gap, not a measurement artifact). |
| `Test suite failed to run`, non-module (21 rows) | 4 runs with React-16/CRA-3 classic-runtime `React is not defined`, undefined `SPELLS.id`, a committed `<<<<<<< HEAD` merge-conflict marker, and a duplicate `TALENTS_PALADIN` declaration. All reproducible under `react-app-rewired`. | Commit-intrinsic. |
| Protection Paladin integration (139 rows, run `1609582561`) | Parser-build failures (`parser.constructor`/`getModule`/`active` of undefined, `beforeAll` timeouts) on a local `example.zip` log; 8 other integration tests pass in the same run. | Commit-intrinsic. |
| Integration-test snapshot clusters (837 rows) and Survival Hunter integration (66 rows) | Multi-class `CombatLogParser` build crashes (`TypeError: Cannot read property … of undefined`, `beforeAll` timeouts) on local `.zip` logs across the dense bad-commit runs (`1610385843`, `1609891545`, `1611016152`, `1611031160`, `1609711166`, `1614216411`, `1609626761`, …). `survivalIntegrationTests` uses the same input and passes when code is correct. | Commit-intrinsic. |

### Test-suite structure (verified)

Until 2022-09-05 the repository shipped `integrationTests/*.test.ts` files, and the
main `react-app-rewired test` run included them. Commit `1409e34b3a` (2022-09-05)
deleted all integration test files and fixtures; the same day `f8676e4951` switched
`test:integration` to `--passWithNoTests`. Overall coverage drops concurrently: the
`analysis/` tree moved into `src/analysis/`, and since `react-app-rewired`
instruments all files under `src/`, instrumented lines rose from about 10K to about
43K while the test file count fell from 69 to 49.

## Environment / setup fixes

None.

## Known gaps

The `test:integration` sub-suite is not collected; the main `test` script covers the
same behavioral code.
