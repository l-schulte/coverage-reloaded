# apollo-client

**Repository:** https://github.com/apollographql/apollo-client
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `apollo-client`).
  Version override: `npm@7.20.3` → `npm@8` for epoch `1627914966`–`1636403951`.
- **Node strategy:** default.
- **Runners:** `jest`.
- **Eras:** unit tests only. The `integration-tests/` workspace is Playwright
  end-to-end (off-limits). `scripts/memory` and `integration-tests/node` use
  `node:test` smoke checks that exercise the built package, not `src/`. Behavioral
  integration is already covered by the jest unit run over `src/__tests__`, so no
  separate integration suite is collected.

## Coverage collection

- **Suites collected:** the jest unit run over `src/__tests__`.
- **Suites excluded:** Playwright end-to-end (`integration-tests/`) and the
  `node:test` smoke checks.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** jest `lcov` reporter.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [x] complete run
- [x] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-16 07:51).

| Metric | Value |
|---|---|
| Commits processed | 4462 |
| Without test failures | 3895 |
| With test failures | 514 |
| Not applicable | 0 |
| Hard errors | 53 |
| Coverage produced | 99.0% |

Full statistics and plots: [`stats_output/`](stats_output/). Failure labels:
[`failure_labels_project.csv`](failure_labels_project.csv).

## Known test failures

All failures exit with code 1 and valid (partial) coverage; the suite never bails.
A labeling pass on 2026-09-16 reclassified every previously `problematic`/`unclear`
family to `reevaluated_acceptable`; the collapsed
[`failure_labels_collapsed_problematic_unclear.csv`](failure_labels_collapsed_problematic_unclear.csv)
is now empty.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| Sporadic jest 5000 ms timeouts (40 runs, 2021-11 to 2025-12) | acceptable | valid partial | None. 60 distinct tests hit `thrown: "Exceeded timeout of 5000 ms for a test"`; the largest family is `happy path › memoizes between requests` (`src/link/persisted-queries/__tests__/react.test.tsx`, 11 runs) — a timing assertion (`expect(firstRun).toBeGreaterThan(secondRun)`). No single commit-era cause. |
| Mutation `refetchQueries` assertion (16 runs, 2021-05 to 2021-11) | acceptable | valid partial | None. `allows refetchQueries to be passed to the mutate function` (`src/react/components/__tests__/client/Mutation.test.tsx`) fails; 9 runs (2021-06-23 to 2021-08-16) show `Expected: false / Received: true` on a loading-state assertion, 5 runs (2021-05-18) fail with `Converting circular structure to JSON`, and the 2 runs on 2021-11-03 coincide with the jsdom commit `278ba5fd…`. |
| jsdom environment missing (`window is not defined`) — 1 commit `278ba5fd223f133e53dbef2bc840e38c4dbee735` (2021-11-03) | reevaluated_acceptable | the commit's code was effectively not covered; this is the faithful signal | None. The `src_unit` suite fails to run because the jest `26→27` bump left `testEnvironment` unset, so the default `node` environment aborts every browser-touching test. `testEnvironment: 'jsdom'` was added upstream one day later in `745712847`. |
| `@testing-library/react-render-stream` act-environment incompatibility — 1 commit `7bcde69848dead02b8af2305bcf0a1a87c99dbc8` (2024-12-04) | reevaluated_acceptable | render-stream-covered code was effectively not covered; accepted as a faithful gap | None. All 30 `config_unit` failures (10 "Test suite failed to run" + 20 downstream masking-assertion failures) stem from one error: the pinned `@testing-library/react-render-stream@2.0.0-alpha.1` throws "Tried to create a React root for a render stream inside a React act environment" because `@testing-library/react@16` forces `IS_REACT_ACT_ENVIRONMENT`. The test files already call `disableActEnvironment()`. |
| ts-jest type error (`graphql-ws` `terminate`) — 1 commit `1089b2f0defc5a3eee8c05df9b35f120e8266211` (2022-04-21) | reevaluated_acceptable | faithful gap | None. The `graphqlWsLink.ts` suite fails to run because ts-jest `diagnostics: true` rejects a type error in the test's mock `Client` after the `graphql-ws` v5.7.0 update. The project's own config enforces type-checking, so the developers' run also failed to compile this suite. |
| ts-jest type error (`InMemoryCache` `lookupFragment`) — 1 commit `abecb11601f286e414101a3bc5b53017e7eb1499` (2022-09-21) | reevaluated_acceptable | faithful gap | None. The `writeToStore.ts` suite fails to run because ts-jest `diagnostics: true` rejects a type error in the test's mock `WriteContext` after `InMemoryCache#transformForLink` added the field. The developers' run also failed to compile this suite. |
| `use-sync-external-store/shim` missing — 8 commits around 2021-11 (for example, `7f0d459c7b3b94c5de1561433c006a6efa017007`, 2021-11-16) | reevaluated_acceptable | faithful gap; ~70 unit tests abort | None. The `#8785` `useSyncExternalStore()` addition depends on `use-sync-external-store@^1.0.0-beta-…`, which apollo-client also declares as an optional peer dependency (`peerDependenciesMeta.use-sync-external-store.optional: true`). npm 7+ skips optional peers, so the `shim` subpath is never installed. WayPack serves the tarball correctly, so this is a real dependency-resolution gap at those commits. The project fixed it by bumping to `1.0.0-rc.0` on 2022-01-10. |

## Environment / setup fixes

None.

## Known gaps

The Playwright end-to-end workspace and the `node:test` smoke checks are
intentionally not collected.
