# metaphysics

> **Archived project (inaccessible issues).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Root workspace with `jest`.

- `test` calls `jest` either with a config file or without
- `test:jest` calls `jest` with a config file, but is not always available

We call test directly, add coverage parameters and add the config file if it exists.

## Config

```json
"metaphysics": {
    "url": "https://github.com/artsy/metaphysics"
}
```

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (failures in the beginning frequent, based on broken graphql queries that are not added to ignore list)
- [x] complete run (~97,8% of commits successfull)

## Known Test Failures

All known failure groups exit with code 1 but still produce valid (partial) coverage — they do not corrupt the exposure variable and are logged as such.

- **Time-dependent / self-expiring tests** (exit 1, ~7 of ~2885 tests at affected commits):
    * `show_events` / `partner_show_events` UA-sniffing date check (`is not yet time to rethink this UA-sniffing behavior`) — asserts a temporary workaround deadline has not passed; the deadline predates the commit, so it fails regardless of when run.
    * `display_timely_at` relative-label tests in `sale/index` (v1 + v2) — snapshot assertions on labels like "live in 2m" anchored to the run moment. Faking `Date.now()` to the commit timestamp (via `fake-time-node.js`) was tried and **reverted**: it did not fix these and additionally broke `sale/index` tests that previously passed at wall-clock time, raising failures 7→9.
- **Schema-stitching / persisted-query validation** (environment-related, not developer-facing):
    * `validatePersistedQueries.test.ts` fails with `Unknown type` / `Cannot query field` for consignment (Convection) mutation types — the v2 schema is stitched from remote Artsy service schemas unavailable in the sandbox.
    * `src/lib/stitching/{vortex,gravity}/__tests__/*` fail on schema merge (`Error merging schemas: Unknown type …`) for the same reason. These pass in Artsy's own CI.