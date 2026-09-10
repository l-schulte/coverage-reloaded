# moodleapp

**Repository:** https://github.com/moodlehq/moodleapp
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `moodleapp`).
  The `Angular compatibility` Node strategy is disabled.
- **Node strategy:** default.
- **Runners:** `jest`, Karma (`ng test`).
- **Eras:** the `unit` suite has two eras: `ng test` (Karma, a single commit around
  2020-10) and `jest` (dominant, from around 2020-09). A Gulp step builds
  language/environment files required by the tests (present from around 2021-02).

## Coverage collection

- **Suites collected:** `unit` (a single suite producing one `lcov` output).
- **Suites excluded:** none.
- **Coverage tool / config:** jest with the V8 coverage provider, because the
  babel-based Istanbul provider crashes silently. Coverage is produced with
  `jest --coverage --coverageProvider=v8 --coverageReporters=lcov`.
- **LCOV production:** jest `lcov` reporter.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (few and genuine)
- [x] complete run
- [wip] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 10:17).

| Metric | Value |
|---|---|
| Commits processed | 6607 |
| Without test failures | 6105 |
| With test failures | 137 |
| Not applicable | 152 |
| Hard errors | 213 |
| Coverage produced | 96.7% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| Angular DI setup issues (`init.page.test.ts`), directive/component setup (`link.test.ts`, `user-avatar.test.ts`, `iframe.test.ts`), service test (`navigator.test.ts`) | acceptable | valid partial coverage | None. Rare and genuine (3 of 119 runs). |
| `NG0203` Angular injection-context warnings (~410 per run) | false_positive | none | None. Warnings only; tests pass. |

## Environment / setup fixes

None.

## Known gaps

Early commits that predate the test infrastructure exit with code 2 and are
recorded as **not applicable** (152 commits).
