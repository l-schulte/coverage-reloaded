# serverless

**Repository:** https://github.com/serverless/serverless
**Status:** active

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `serverless`).
- **Node strategy:** `min_node_version = 12`.
- **Runners:** `mocha`, `nyc`, `c8`.
- **Eras:** two coverage eras: `nyc` (early 2020) and `c8` (dominant from around
  2020 onward).

## Coverage collection

- **Suites collected:** `test`, the primary suite (mocha-based).
- **Suites excluded:** none.
- **Coverage tool / config:** `nyc` (`nyc --reporter=lcov`) or `c8`
  (`c8 --reporter=lcov`) depending on the era.
- **LCOV production:** `nyc`/`c8` `lcov` reporter.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [x] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 11:26).

| Metric | Value |
|---|---|
| Commits processed | 2765 |
| Without test failures | 0 |
| With test failures | 2265 |
| Not applicable | 290 |
| Hard errors | 210 |
| Coverage produced | 91.5% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `#invokeLocalRuby context.remainingTimeInMillis should become lower over time` and `#invokeLocalRuby calling a class method should execute` — `SyntaxError: Unexpected token t in JSON at position 1` | problematic | none; Ruby invocation logic is covered by passing stub tests | None. The Ruby wrapper's `attach_tty` method prints `"tty unavailable"` in the container (no TTY device), so the output starts with `t` instead of JSON. Verified with Ruby 2.7 (Bullseye default) across 2020–2025 commits; the error persists, confirming an environment issue. |
| v3.0.0 release-train temporal mismatch (`Cannot find module 'lib/utils/telemetry/are-disabled'`, `Cannot find module '@serverless/dashboard-plugin/lib/resolveProviderCredentials'`) | problematic | `are-disabled` case: visible partial (1930 passing / 313 failing); dashboard-plugin case: aborts at load with near-empty coverage | Document as a known failure; not fixable in `install-and-run.sh`. |

Details of the v3.0.0 release-train mismatch: a 247-commit rebase/merge cluster
(the Serverless Framework v3.0.0 release train) shares a single committer timestamp
`1643293318` (2022-01-27 15:21:58) while author dates span 2022-01-14 to
2022-01-25. The pipeline snapshots dependencies at the committer timestamp, so
WayPack serves post-rename dependency versions against pre-rename source. Two
breaking renames landed inside the window:

1. `lib/utils/telemetry/areDisabled.js` → `are-disabled.js` (`c3e08ca34`,
   2022-01-25); `@serverless/test@9.0.0` (published 2022-01-27) requires the new
   hyphenated path. Observed in 5 commits.
2. `resolveProviderCredentials` → `resolve-provider-credentials` in
   `@serverless/dashboard-plugin` (`73b188604`, 2022-01-20); version `6.0.0`
   (published 2022-01-27) ships only the new subpath. Observed in 1 commit.

Of the 247-cluster commits, about 172 use the old `areDisabled.js` and declare
`@serverless/test@^9.0.0`; about 77 use the old dashboard-plugin subpath. A
candidate mitigation (a WayPack local override pinning `@serverless/test` to
`8.8.0` and `@serverless/dashboard-plugin` to `5.5.4` for that timestamp) is
risky because the older harness may be incompatible with v3-era code.

## Environment / setup fixes

None.

## Known gaps

290 commits are **not applicable**: they depend on `@serverlessinc/sf-core`, which
is closed source.
