# matrix-js-sdk

**Repository:** https://github.com/matrix-org/matrix-js-sdk
**Status:** active

## Test infrastructure

- **Package manager:** yarn (`yarn@1`, `yarn.lock`) throughout the study window
  (see [`config.json`](../../config.json) → `matrix-js-sdk`).
- **Node strategy:** default, with a targeted override to Node 16 for epoch
  `1658323000`–`1675957462` (2022-07-20 to 2023-02-09). The override avoids two
  upstream toolchain bugs that only manifest on Node 18: the `@matrix-org/olm`
  ≤ 3.2.12 `fetch(<path>)` WASM loader failure, and the `@sinonjs/fake-timers` 9.x
  `Cannot assign to read only property 'performance'` failure.
- **Runners:** `jest` (26 → 29 → 30 across the window).
- **Eras:**
  - 2021-01-04 to 2021-04-28: `test` = `jest spec/ --coverage` (coverage on by
    default).
  - 2021-04-28 to 2026-01-01: `test` = `jest`; coverage reached via `--coverage`.
  - `spec/unit` and `spec/integ` exist for the whole window.
  - `spec/browserify` exists until 2023-10-03 (removed upstream).
  - The 2026-01-15 switch to Vitest is outside the window.

## Coverage collection

- **Suites collected:** `unit` (`spec/unit`) and `integration` (`spec/integ`),
  both via `jest --coverage`. For commits whose `test` script hardcodes a `spec/`
  path (2021-01-04 to 2021-04-28), a single combined run is used.
- **Suites excluded:** `spec/browserify` only (a browser-bundle smoke test that
  requires `yarn build` and would instrument `dist/`; removed upstream on
  2023-10-03). Every in-window `.spec`/`.test` file lives under `spec/unit` or
  `spec/integ`, both of which are collected — no other suites exist.
- **Coverage tool / config:** jest's Istanbul instrumentation; from 2021-04-28 the
  project sets `collectCoverageFrom: src/**/*.{js,ts}`. The earlier era has no such
  config, so the run forces the same glob to keep `spec/` helpers out of the
  exposure variable.
- **LCOV production:** the run forces `--coverageReporters=lcov` because some
  commits configure only the `text` reporter; output is `coverage/lcov.info` per
  suite, moved out as `unit.lcov` / `integration.lcov`.

## Checklist

- [wip] 100 done
- [ ] failed tests doublechecked
- [ ] complete run
- [ ] complete test failure check

## Results

Source: `stats_output/report.txt`. The last 50-commit sample predates the
environment fixes below (browserify exclusion, source-only coverage glob, test
timeout); a re-run is pending before these figures are final.

| Metric | Value |
|---|---|
| Commits processed | pending |
| Without test failures | pending |
| With test failures | pending |
| Not applicable | pending |
| Hard errors | pending |
| Coverage produced | pending |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

No `failure_labels_project.csv` exists yet; families have not been labeled.

## Expected console output

`src/logger.ts` writes to `console` via a dynamic `console[methodName]` lookup
(`src/logger.ts:99-118`), and the suites deliberately drive error paths, so logs
carry large volumes of `console.error` (push-rule setup, mocked
`.well-known`/`/sync`/backup failures, RTC membership). Node also emits
`DeprecationWarning` (`Buffer()`) and `UnhandledPromiseRejectionWarning` from test
teardown, and some commits warn that timer APIs were not replaced with fake
timers. None of this is a test failure or coverage signal: commits with zero
failing tests still emit dozens of errors.

`silence-console.cjs` (loaded via `--setupFiles`) no-ops `console.log`,
`console.debug`, `console.info`, and `console.warn`; `console.error` is preserved
for debugging. Because the logger resolves `console[methodName]` at call time,
tests that `jest.spyOn(console, ...)` still intercept and assert normally — this
was verified exhaustively across the window (only four console-assertion sites,
all spy-guarded) and empirically (`logger.spec.ts` asserts on `console.debug`
while `debug` is muted and passes). Node-level warnings are not `console.*` and
therefore still appear.

### Troubleshooting: a console-expecting test fails

If a run fails with `expected console.<method> to have been called` /
`toHaveBeenCalledWith` (or any assertion on a muted method), that test does **not**
install a spy and depends on the real console method — the shim is the cause.
Fix by removing the offending method from the list in
[`silence-console.cjs`](silence-console.cjs), or by adding a
`jest.spyOn(console, "<method>")` at that commit. Never un-mute `console.error`:
its output is the primary failure signal.

## Environment / setup fixes

- `--coverageReporters=lcov` forces LCOV on commits whose jest config emits only
  `text`.
- `--collectCoverageFrom='src/**/*.{js,ts}'` limits coverage to source on the
  early era, which otherwise instruments `spec/` helpers.
- `--forceExit` prevents in-band jest runs from hanging on open handles.
- `--testTimeout=30000` absorbs timing-sensitive crypto tests that intermittently
  exceed jest's default 5 s under parallel-run load.
- `--testPathIgnorePatterns` drops `spec/browserify` (see Coverage collection).
- `--setupFiles=/coverage_reloaded/silence-console.cjs` no-ops
  `console.log`/`debug`/`info`/`warn` while preserving `console.error` (see
  Expected console output for the diagnostic if this ever fails a test).
- Node 16 override for epoch `1658323000`–`1675957462` (see Test infrastructure).
- yarn-only install with a loud failure for any other package manager.

## Known gaps

- `spec/browserify` is deliberately not collected (requires the browser build;
  see Coverage collection).
- `src/webrtc/mediaHandler.ts` unconditionally referenced `navigator.mediaDevices`
  for 14 commits (2022-02-18 to 2022-02-22); those runs produce valid partial
  coverage. Fixed upstream shortly after.
