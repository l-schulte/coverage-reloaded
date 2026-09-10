# uwazi

**Repository:** https://github.com/huridocs/uwazi
**Status:** active

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `uwazi`).
- **Node strategy:** override Node 16 → `14` for epoch `1626742218`–`1659708655`.
- **Runners:** `jest`.
- **Eras:** jest `24.8.0` → `27.5.1` → `29.7.0`. Two jest projects (client and
  server) run with `--runInBand --forceExit`.

## Coverage collection

- **Suites collected:** the behavioral suite, with coverage.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** jest `lcov` reporter.
- **Services:** Elasticsearch via Docker-in-Docker, MongoDB 7.0, and `redis-server`.

## Checklist

- [x] 100 done (97/100)
- [x] failed tests doublechecked (failures below are known; none are bails)
- [x] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 12:02).

| Metric | Value |
|---|---|
| Commits processed | 8907 |
| Without test failures | 1011 |
| With test failures | 7839 |
| Not applicable | 1 |
| Hard errors | 56 |
| Coverage produced | 99.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

All failures exit with code 1 and valid (partial) coverage; the suite never bails.

### Genuine test bugs (classification: acceptable)

| Signature | Coverage impact | Action |
|---|---|---|
| `NavlinkForm` / `NavlinksSettings` / `navlinksActions` — spec omits the required `links` prop → `TypeError` + missing spy | valid partial | None; do not fix. |
| `54-add_system_key_translations` — `Cannot read property 'value' of undefined` | valid partial | None; do not fix. |
| `18-fix-malformed-metadata` — `Expected ["123-c1","6","7"]`, `Received ["123-c1"]` | valid partial | None; do not fix. |
| `entitySavingManager` — `.pdf` vs `.jpg` (insertion order vs sorted) | valid partial | None; do not fix. |
| `ModelWithPermissions` — document order swapped (`$in`/insertion nondeterminism) | valid partial | None; do not fix. |
| `dateHelpers` — Arabic-Indic vs Latin digits (`٦ أكتوبر ٢٠٢٣` vs `6 أكتوبر 2023`, ICU locale data) | valid partial | None; do not fix. |
| `activitylogMiddleware` — async append race (`>0` vs `0`) | valid partial | None; do not fix. |

### Timeouts not fixable by raising `--testTimeout`

| Cause | Affected tests |
|---|---|
| jest 24.8.0 ignores the flag entirely, stuck at the 5000 ms default | `migrator`, `33-character-count`, `31-editDate`, `4-pdf_thumbnails`, `entitiesModel`, `exportRoutes` |
| Hardcoded per-test/hook timeouts in specs (jest 29) | `csvLoaderSelects` (`beforeAll` 10 s), `distributedLoop` (10 s/60 s) |
| `wait-for-expect` internal 4500 ms ceiling | `taskManager`, `socketClusterMode`, `distributedLoop` (redis/socket timing) |
| Genuine hang | `exportRoutes` hung past 60 s even where the flag applied |

## Environment / setup fixes

None.

## Known gaps

None documented.
