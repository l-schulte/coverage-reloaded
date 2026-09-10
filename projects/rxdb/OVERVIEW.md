# rxdb

**Repository:** https://github.com/pubkey/rxdb
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `rxdb`).
- **Node strategy:** `node_version_lts_offset_months = 0`,
  `node_version_delay_months = 0`, `use_exact_node_version = true`.
- **Runners:** `mocha`, `c8`.
- **Eras:** mocha-based tests with storage variants. The harness handles
  significant complexity:
  - Patches `.mocharc` to disable `bail: true`, which is present across the entire
    project history.
  - Runs `transpile` once, then iterates over the available storage variants:
    `memory`, `dexie`, `lokijs`, `pouchdb`, `dexie-worker`, `memory-validation`,
    `remote`, `foundationdb`, `mongodb`.
  - FoundationDB: detects the API version from source, then installs matching DEB
    packages and the npm module.
  - MongoDB: started via Docker-in-Docker.
  - Skips `custom` (template placeholder, never functional) and `test:full` (empty
    test file).
  - Skips `lokijs:worker` (duplicate of `lokijs`).

## Coverage collection

- **Suites collected:** the storage variants listed above.
- **Suites excluded:** `custom`, `test:full`, `lokijs:worker`.
- **Coverage tool / config:** `c8 --reporter=lcov`.
- **LCOV production:** `c8` `lcov` reporter.

## Checklist

- [x] 100 done (94/100; 4 more may be fixable; some MongoDB errors in the latest commits)
- [x] failed tests doublechecked (only a few errors, seem genuine)
- [ ] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 11:10).

| Metric | Value |
|---|---|
| Commits processed | 4188 |
| Without test failures | 2681 |
| With test failures | 1137 |
| Not applicable | 115 |
| Hard errors | 255 |
| Coverage produced | 93.7% |
| Commits not yet processed | 4316 |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

None documented beyond a few genuine errors.

## Environment / setup fixes

None.

## Known gaps

The run is incomplete (4316 commits not yet processed). Some MongoDB errors appear
in the latest commits.
