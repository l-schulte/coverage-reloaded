# moodleapp

**Repository:** https://github.com/moodlehq/moodleapp
**Status:** active

## Test infrastructure

- **Package manager:** npm (see [`config.json`](../../config.json) → `moodleapp`).
  The `Angular compatibility` Node strategy is disabled.
- **Node strategy:** default.
- **Runners:** jest (dominant); a Karma (`ng test`) branch exists in
  `install-and-run.sh` but never fired in the collection window.
- **Eras:** the `unit` suite runs jest for the whole collection window (from
  2021-01). The `test` script changed from `jest --verbose` to
  `NODE_ENV=testing gulp && jest --verbose` (from 2021-02), so a Gulp step builds
  language/environment files before the tests from that point on. The `ng test`
  branch targets a single pre-window commit (around 2020-10).

## Coverage collection

- **Suites collected:** `unit` (one suite, one `lcov` output).
- **Suites excluded:** none.
- **Coverage tool / config:** jest with the V8 coverage provider; the babel-based
  Istanbul provider crashes silently. Run as
  `jest --coverage --coverageProvider=v8 --coverageReporters=lcov --runInBand`.
- **LCOV production:** jest `lcov` reporter.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (non-zero-exit runs inspected and classified by failure family)
- [x] complete run (6607/6607 commits processed on author-date timestamps; 0 pending)
- [x] complete test failure check (all 116 failing runs labeled; 0 problematic/unclear)

## Results

Source: `stats_output/report.txt` (generated 2026-09-16 07:20).

| Metric | Value |
|---|---|
| Commits processed | 6607 |
| Without test failures | 6229 |
| With test failures | 116 |
| Not applicable | 152 |
| Hard errors | 110 |
| Coverage produced | 98.3% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

The 116 failing runs fall into six signatures. All are dev-facing — the era's
developer would see them at the same commit — and are labeled `acceptable` or
`reevaluated_acceptable` (the latter records a family re-assessed from
`unclear`/`problematic`). See
[`failure_labels_project.csv`](failure_labels_project.csv) for the labels;
[`failure_labels_collapsed_problematic_unclear.csv`](failure_labels_collapsed_problematic_unclear.csv)
lists no `problematic`/`unclear` families.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `● Test suite failed to run` — ts-jest compile errors at broken intermediate commits (`@services/nav-helper`, `@types/jest` window, `@singletons/components-registry`, `CorePlatform.isIOS`, `Constructor` export, `@ionic-native/qr-scanner`, `LongDateFormatKey`, `TS2740`/`TS2769`/`TS2507` refactor window (2021-03)) | acceptable / reevaluated_acceptable | valid partial | None |
| `● Credentials page › renders` — `NullInjectorError` (no `HttpClient` provider), 2023 era; later 5000 ms timeouts recovered by the `--testTimeout` fix | acceptable | valid partial | None |
| `● Credentials page › suggests contacting support after multiple failed attempts` — unbounded `fixture.whenStable()` hang during the 2023-09 `MOBILE-4201` login-restyling window | acceptable / reevaluated_acceptable | valid partial | None (transient window) |
| `● CoreFormatTextDirective` / `● CoreLinkDirective` (`should use link directive on anchors`, `should render`, `should format text`, `should use external-content directive on images`, `should capture clicks`) — un-mocked directive dependencies | acceptable / reevaluated_acceptable | valid partial | None |
| `● CoreNavigator › navigates to site paths using the default tab` (2022 era) | acceptable | valid partial | None |
| `● Site Home link handlers › Handles links ending with /?redirect=0` — unbounded `handleCustomURL` await (true hang) | acceptable | valid partial | None (transient window) |
| `NG0203` Angular injection-context warnings (present in 476 logs) | false_positive | none | None. Warnings only; tests pass. |

## Environment / setup fixes

- `--testTimeout=30000` added to the jest invocation in `install-and-run.sh`:
  component-render tests occasionally exceeded the 5000 ms default in the
  single-threaded container. Recovered 22 runs (failing runs 137 → 115) and
  eliminated the `CoreSitesProvider › adds ionic platform and theme classes`
  timeout family. A longer timeout cannot mask a genuine hang; two tests that
  never resolve still time out.
- V8 coverage provider used instead of the babel-based Istanbul provider, which
  crashes silently (see Coverage collection).

## Known gaps

- 152 processed commits predate the test infrastructure and are recorded as
  **not applicable**.
- 110 hard errors (no coverage): 93 `npm install` failures — 69 on git-based
  `moodlemobile` Cordova dependencies (`git ls-remote`/HTTP errors for
  `phonegap-plugin-push`, `cordova-plugin-prevent-override`, and others) and 24
  registry version misses (`ETARGET`, e.g. `which-module@2.0.1`, `ws@8.16.0`) —
  15 runs where jest aborts with `Cannot find module 'ts-jest/utils'` and emits no
  LCOV, and 2 suite timeouts.
- Two true-hang tests cannot be recovered by raising the timeout (`Site Home link
  handlers` and `Credentials page › suggests contacting support` during the
  2023-09 login-restyling window). Both are dev-facing and transient.
