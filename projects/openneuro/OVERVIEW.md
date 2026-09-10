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
- [x] failed tests doublechecked (environment vs test-code classified across a 100-log review)
- [ ] complete run
- [ ] complete test failure check

## Results

**Pending (no `stats_output`).**

## Known test failures

All failures are non-bail; exit code 1 yields valid (partial) coverage. A failing
test still executes the code under test, so it counts toward line coverage. Only
"suite failed to run" cases lose coverage for that file.

### Environment fixes applied (no longer failures)

| Fix | Commits affected |
|---|---|
| `tsc -b` build made non-fatal (dist still emitted) | ~10 commits |
| `bids-validator` local `file:` dependency rewritten to published `1.6.2` | 2 commits |
| `ELASTICSEARCH_CONNECTION`/`JWT_SECRET` exported | `71eff390…`, `2cc91510…` |
| vitest `../libs/*` resolution fixed by always building first | `1ca85116…` |

### Pre-existing test-code (classification: acceptable — accept as valid partial, do NOT fix)

| Signature | Evidence |
|---|---|
| jest `moduleNameMapper` maps `@openneuro/components/search-page` to a nonexistent path | `8cd69392…`; 1 suite fails, 387 pass |
| `enzyme@3.9.0` + `react@17` `mount()` crash | `89e21602…` |
| Snapshot mismatches in `*.spec` suites | `8719e33…`, `0915c6c…`, `9396eb3…` |

### Recent 100-commit review

12 exit-code-1 soft failures, all genuine developer-facing issues (assertion and
snapshot mismatches plus transitional commits with missing modules or empty
suites): `2da0686`, `561557a`, `60139d3`, `ea1fc065`, `6c325812`, `979433a`,
`ddbf1138`, `1ab46e07`, plus time-relative snapshot drifts `280f862`, `9b4898db`.
`49aea993` (vite-node `.js`→`.ts`, with a fixup commit following) and `1ecc8b11`
(cli `npm:` Deno-specifier imports unresolved by vitest — a toolchain gap; accept no
`cli` coverage).

## Environment / setup fixes

See the environment-fixes table above.

## Known gaps

No `stats_output` has been generated yet. The `cli` suite may lack coverage on
commits where `npm:` Deno-specifier imports are unresolved by vitest.
