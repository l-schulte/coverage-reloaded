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

- [x] 100 done
- [x] failed tests doublechecked
- [x] complete run
- [x] complete test failure check

## Results

Source: `stats_output/report.txt` (generated 2026-09-24).

| Metric | Value |
|---|---|
| Commits processed | 4,989 |
| Without test failures | 4,139 |
| With test failures | 843 |
| Not applicable | 0 |
| Hard errors | 7 |
| Coverage produced | 99.9% |

The 7 hard errors are the documented non-environment gaps: Group B (3,
`--frozen-lockfile` lockfile inconsistency), Group C (3, git-ref drift), and
Group E (1, WebRTC crash). The environment groups (A, D) were recovered by the
`resolve-and-pin` fix. Full statistics and plots:
[`stats_output/`](stats_output/).

## Known test failures

Labeling pass complete. `failure_labels_project.csv` holds 400 fingerprints
covering all 6,463 detected failures across the 843 failing runs: **328
`acceptable`, 72 `reevaluated_acceptable`, 0 `problematic`, 0 `unclear`**. Every
family was re-assessed at the error-body level; none is a setup artifact of this
pipeline, so no `install-and-run.sh` or `Dockerfile` change is required and no
coverage-threshold confound was found. See
[`failure_labels_project.csv`](failure_labels_project.csv) and the collapsed
views [`failure_labels_collapsed_by_rule.csv`](failure_labels_collapsed_by_rule.csv) /
[`failure_labels_collapsed_problematic_unclear.csv`](failure_labels_collapsed_problematic_unclear.csv)
(both empty of unresolved families). The olm-related families
(`End-to-end encryption not supported`, `Cannot find module '@matrix-org/olm'`,
`must contain at least one test`) were traced to genuine upstream defects: merge
`4e283176` deleted `"@matrix-org/olm"` from `package.json`, and the 2021-05-21
libolm package rename left `spec/olm-loader.js` importing the old `olm` name.

### Hard failures (no coverage produced)

These commits emit no `lcov.info` and are therefore excluded from the sample.
Both families are faithful to the checked-out commit's own state — not
environment artifacts — so they are documented rather than patched.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `yarn install --frozen-lockfile` → `Your lockfile needs to be updated` — `dd8c157bb95a6604ebe0b25a143755c42b57f87f` (2021-12-09) | genuine upstream: the commit bumped `@matrix-org/olm` 3.2.3→3.2.7 in `package.json` but left `yarn.lock` at 3.2.3 | no coverage; 1 commit | Document. `--frozen-lockfile` is correctly rejecting an inconsistent committed tree; do not patch. |
| `yarn install --frozen-lockfile` → `Your lockfile needs to be updated` — `b711781f1657f10ade40e71f81919196793e1ddf` (2022-07-29) and `22c5999fed9d0e8b8f31f510c5048e04cde40e80` (2022-08-01) | genuine upstream: merge `b711781f` dropped the `sdp-transform` / `@types/sdp-transform` entries from `yarn.lock` while `package.json` kept them; `22c5999f` inherits the bad merge; restored upstream at `2cc51e0db` (2022-08-04) | no coverage; 2 commits | Document. `--frozen-lockfile` is correctly rejecting an inconsistent committed tree; do not patch. |
| `TypeError: Cannot read properties of undefined (reading 'getVideoTracks')` at `src/webrtc/call.ts` — `b4f8b0fe4fed799276fd9595e3b747164ccf1015` (2023-01-24) | genuine upstream: the commit's own change dereferences `this.localUsermediaStream` while it is `undefined` in an async timer callback; the uncaught rejection crashes jest mid-run (triggered from `spec/unit/matrix-client.spec.ts`) | no coverage; 1 commit | Document as a faithful gap; dev-facing regression at that commit. |

### Soft failures (partial coverage, suite did not bail)

All of these still emit `lcov.info`, so they are visible partial results — no
silent under-measurement. The remaining soft-failure groups are still under
triage; the one resolved so far is below.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `SAS verification › verification in DM › should verify a key` times out at 30 s — **523 commits** (2021-01-04 → 2022-06-16; steady 25–35% of commits per month) | genuine upstream flakiness: a race in the verification state machine let a `ready` event arriving after `started` trigger a spurious cancel, so the verifier never resolved. Fixed upstream in `d9f070404` ("reduce flakiness of e2e verif test", PR #2250, merged 2022-05-23) | **measurably zero**: isolating commits where this is the only failure (n=464) vs. fully clean commits (n=1301) over the flaky window, `src/crypto/verification` coverage is 70.5% vs 70.3% (`SAS.js` 87.9% vs 87.9%) — the other tests in `sas.spec` cover the same lines, so no unique lines are lost and a re-run would not help | Document. Do not patch; the project fixed it itself. |

> Note: comparing failing vs. passing commits *without* conditioning on this
> being the sole failure shows a misleading ~17pp coverage gap, because those
> commits also carry other failing suites. Always isolate the signature first.

#### Whole-suite source-parse failures (Group 4)

15 commits where a core source file fails to compile in the checked-out commit,
so every spec that imports it aborts. All are genuine upstream breakage,
self-healed in later commits; the loss is large but faithful and visible in
`lcov.info` (`LF` stays ~12–13k, `LH` collapses).

| Cause | Commits | Date | Defect | Coverage impact | Action |
|---|---|---|---|---|---|
| `.babelrc` `"modules": false` (ESM not transpiled) | `bbeea51a`, `6e07c9e9`, `fe0a2689` | 2021-09-21 | reverted to `"commonjs"` shortly after | 0.0% vs 51.6% clean baseline (−51.6pp) | Document; do not patch. |
| Missing `}` — `private pushLocalFeed` inserted inside `pushNewFeed` in `src/webrtc/call.ts` | `23f5c2e0`, `cebdc446`, `25eb6de2`, `e9b802de`, `cbc74815`, `d250e738` | 2021-05-07/08 | real committed syntax error | 18.2% vs 54.5% (−36.3pp) | Document; do not patch. |
| Same class of structural defect | `c4263692`, `96420a75` | 2021-07-06 | real committed syntax error | 9.9% vs 52.8% (−42.9pp) | Document; do not patch. |
| Same class of structural defect | `4fd77c2f`, `3e94db18`, `d7dbaeba` | 2021-08-11 | real committed syntax error | 17.9% vs 52.5% (−34.6pp) | Document; do not patch. |
| Merge left duplicate import `IRefreshTokenResponse` in `src/client.ts:195` | `276849f0` | 2022-09-12 | `Identifier 'IRefreshTokenResponse' has already been declared` | 7.5% vs 56.9% (−49.4pp) | Document; do not patch. |

#### Broken JS→TS migration window (2021-06-02; Group 5)

The `[Combined] First pass of JS->TS for MatrixClient` branch landed a migrated
`MatrixClient` before the harness, tests, and dependent modules were updated. On
2021-06-02, **19 of 22 commits fail** (aggregate coverage **48.9%** vs 54.3%
clean June baseline), in two disjoint modes:

- **whole-suite `Cannot find module './client'`** — 7 commits (`8a1d34c4`,
  `497c2dc8`, `4030ec9c`, `92e18b32`, `f3b27d1e`, `f027ddaf`, `caab5bef`): the
  branch renamed `client.js` → `src/1client.ts` while `src/matrix.ts` still
  imported `./client`, so every spec importing `matrix.ts` aborts. Coverage
  **17.9–18.5%** (−36pp).
- **partial internal-API mismatch** — ~14 commits, e.g. `67994f7a` (332 failing
  tests: unit 61/363, integration 77/14): the migrated client no longer exposes
  `_sessionStore.store`, `_baseApis._cryptoCallbacks`, `_crypto.*`,
  `_callEventHandler.calls`, or `opts.clientWellKnownPollPeriod`, so tests fail
  (`clientWellKnownPollPeriod` 842, `_storeClientOptions is not a function` 101,
  plus `downloadKeys`/`_olmDevice`/`_crossSigningInfo`). Coverage **40.9–50.2%**
  (−4 to −13pp).

Genuine upstream breakage, self-healed within the day. Document; do not patch.

#### Other whole-suite source-load failures (Groups 6–8)

Genuine upstream breakage, self-healed; errors confirm committed defects.

| Group | Cause | Commits | Coverage vs. clean baseline | Action |
|---|---|---|---|---|
| 6 — `Class extends value undefined` | bad merges (`develop`→group-call 2022-09-08; 2022-12-13): `RoomWidgetClient extends MatrixClient` where `MatrixClient` is undefined at module init (`src/embedded.ts`), a circular-import break | `d950cda0`, `071d5e71` | 21.5% vs 56.9% (−35.4pp); 26.2% vs 64.1% (−37.9pp) | Document; do not patch. |
| 7 — `Cannot access 'requestInstance' before initialization` | TDZ from a circular import (`src/index.ts → src/crypto/index.ts → src/matrix.ts:65`) | `fc67dc64`, `27a6d1f8`, `66b17aa0`, `26648485` (2021-06-19/23); `49994ac4`, `09fee4a2` (2022-02-25) | ~35.9–36.0% vs 54.3% (−18pp); 38.6% vs 50.6% (−12pp) | Document; do not patch. |
| 8 — `Identifier 'mapper' has already been declared` | committed syntax error: duplicate `const mapper` in `src/sync.js:1550` | `8820619e`, `19d6dbaa` (2021-05-06) | 18.1% vs 54.5% (−36.4pp) | Document; do not patch. |

#### Per-test long tail (2021–2022; Groups 9+)

The remaining soft failures are per-test assertion/teardown failures, not
whole-suite aborts, spread thinly across 259 commits (2021-01 → 2022-12; gone
from 2023 on). Signatures and counts:

- teardown/afterEach cascades — `Cannot read property 'getMember' of null`
  (830), `Caught error after test environment was torn down` (281/75),
  `verifyNoOutstandingExpectation' of null` (156), `_deviceList`/`doTxn`/`stop`/
  `when`/`_crossSigningInfo`/`getTimelineSets`/`getAccountDataFromServer`
  TypeErrors (`Caught error…`/`The error below may be caused by using the wrong
  test environment` are their jest wrapper);
- mock-http ordering — `Expected to see HTTP request for /pushrules` (652),
  `/keys/query` (75);
- API churn — `this.client._storeClientOptions is not a function` (101),
  `Cannot set property 'downloadKeys'` (100);
- `clientWellKnownPollPeriod` (842) — the 2021-06-02 migration window (see Group 5).

Aggregate coverage across all 2,795 commits in 2021–2022:

| Class | Commits | Coverage | Δ vs clean |
|---|---|---|---|
| clean | 1,974 | 55.9% | — |
| SAS flake only | 464 | 53.9% | −2.0pp |
| **per-test long tail** | **259** | **52.4%** | **−3.5pp** |
| whole-suite breaks | 98 | 18.0% | −37.9pp |

**Classification:** genuine upstream test-harness fragility from the 2021–22
refactor era — no `EAI_AGAIN`/`ECONNREFUSED`/fake-time signatures. The suite
still runs (valid partial coverage); impact is small (−3.5pp). Document; do not
patch.

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
- `resolve_and_pin` for `gitlab.matrix.org`, `codeload.github.com`, and
  `packages.matrix.org`: these hosts appear as literal `resolved` URLs in
  `yarn.lock` (olm, eslint-plugin-matrix-org) and are not rewritten to WayPack,
  so intermittent DNS failures (`getaddrinfo EAI_AGAIN`) aborted installs on 62
  commits. Pinning them at run start makes resolution robust.

## Known gaps

- `spec/browserify` is deliberately not collected (requires the browser build;
  see Coverage collection).
- `src/webrtc/mediaHandler.ts` unconditionally referenced `navigator.mediaDevices`
  for 14 commits (2022-02-18 to 2022-02-22); those runs produce valid partial
  coverage. Fixed upstream shortly after.
