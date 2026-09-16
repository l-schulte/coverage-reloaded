# site-kit-wp

**Repository:** https://github.com/google/site-kit-wp
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `site-kit-wp`).
- **Node strategy:** default.
- **Runners:** `jest`.
- **Eras:** `test` runs several builds and then `test:js`. `test:js` is jest-based
  and uses the workspace command (npm ≥ 7) for part of the history. `test:storybook`
  runs visual tests. `test:js:eslint-plugin` exists for a few commits and runs jest.

## Coverage collection

- **Suites collected:** `test:js` and `test:js:eslint-plugin` when present, with
  coverage parameters appended.
- **Suites excluded:** `test:storybook` (visual regression, not behavioral).
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** runner coverage output is collected by
  `find-and-move-lcov.sh`.

## Checklist

- [x] 100 done (93/100)
- [x] failed tests doublechecked (looks like normal test failures)
- [ ] complete run (long-running; work in progress)
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 11:34).

| Metric | Value |
|---|---|
| Commits processed | 15403 |
| Without test failures | 2199 |
| With test failures | 12623 |
| Not applicable | 0 |
| Hard errors | 581 |
| Coverage produced | 96.2% |
| Commits not yet processed | 21387 |

The report lists 15 conflicting entries (a run directory coexisting with an
`.error` or `.not_applicable` sidecar). Full statistics and plots:
[`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `workspace_js` suite failures | acceptable | valid partial coverage | Genuine test errors. |
| `Expected mock function not to be called but it was called` in the `js` suite | acceptable | valid partial coverage | Timing issue, worsened by `--runInBand`; improved but not fully resolved. |
| Remaining `js` suite failures | acceptable | valid partial coverage | Genuine test errors. |

## Environment / setup fixes

None.

## Known gaps

None documented.
