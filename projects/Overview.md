# Active Projects

# nextcloud/spreed

> ⚠️ test suite is tiny and only improved around 04-2020

Root workspace with `jest`, `vitest`, and `vue-cli-service` (distinct eras).

- `test:unit`: initially used `vue-cli-service` -> `jest`
- `test`: replaces `test:unit`; `jest` -> `vitest`

Does not use testrunner parameters. We call test runners directly and append parameters for coverage.

## Config

```json
"spreed": {
    "url": "https://github.com/nextcloud/spreed",
    "min_pm_version": {
        "npm": "8"
    }
}
```

## Checklist
- [x] 100 done (92/100)
- [x] failed tests doublechecked (fails rarely)
- [x] complete run (95.3% of commits successfull)


# mui/material-ui

Root and workspaces with `lerna`, `package.json`, and `pnpm`.

- `test`: runs `jest` in the beginning, later lint and `test:coverage`
- `test:coverage`: wraps mocha in nyc, reports in txt
- `test:coverage:ci`: wrapes mocha in nyc, reports in lcov

We call `test:coverage` if available and then run nyc to generate lcov output. Fallback is calling `test` during the `jest` era.

## Config

```json
"material-ui": {
    "url": "https://github.com/mui/material-ui",
    "disabled_node_strategies": [
        "pnpm-lock.yaml"
    ],
    "use_exact_node_version": true
}
```

## Checklist
- [x] 100 done (95/100)
- [x] failed tests doublechecked
- [x] complete run (~95,8% of commits successfull)

## Known Test Failures
- `Error: Command failed: git rev-parse next` (fixed)
- We have many pending tests from time to time

# mdn/yari

Root and `package.json` workspaces.

- Workspaces specific `test` scripts using either `jest` or `react-scripts test` (jest based).
- `test:testing` also `jest` based, but runs e2e tests under the hood.

We move into the workspaces and call the scripts based on what is available and adding coverage parameters. We skip the e2e tests.

## Config

```json
"yari": {
    "url": "https://github.com/mdn/yari",
    "use_exact_node_version": true,
    "node_version_overrides": [
        {
            "start_ts": 1676043161,
            "end_ts": 1692619152,
            "old_version": 18,
            "new_version": "18.17"
        }
    ]
}
```

## Checklist
- [x] 100 done (99/100)
- [x] failed tests doublechecked (looks great)
- [x] complete run (~94% of commits successfull)

## Known Test Failures
- none

# google/site-kit-wp

Root and a `test` `package.json` workspace.

- `test`: runs various builds and then `test:js`
- `test:js`: `jest` based. Uses workspace command (npm>=7) at some point.
- `test:storybook`: visual tests
- `test:js:eslint-plugin`: exists only for a few commits, but runs `jest`

We run both `test:js` and `test:js:eslint-plugin` and append coverage parameters.

## Config

```json
"site-kit-wp": {
    "url": "https://github.com/google/site-kit-wp"
}
```

## Checklist
- [x] 100 done (93/100)
- [x] failed tests doublechecked (looks like normal test failures)
- [ ] complete run (this will take a long time, wip again after server shutdown)

## Known Test Failures
- `workspace_js` suite: looks like genuine test errors
- `js` suite:
	* `Expected mock function not to be called but it was called` (improved but not completely gone, timing issue made worse by --runInBand)
	* others look like genuine test errors

# FlowFuse/flowfuse

Only root scripts

- `test:unit` runs mocha specs and later delegates to `test:unit:forge` and `test:unit:frontend`
- `test:unit:forge` runs mocha specs
- `test:unit:frontend` runs vitest tests
- `test:system` runs system tests using mocha

Skipping e2e and docs tests.

## Config

```json
"flowfuse": {
    "url": "https://github.com/FlowFuse/flowfuse",
    "node_version_delay_months": 24,
    "min_node_version": 14
}
```

## Checklist
- [x] 100 done (92/100)
- [x] failed tests doublechecked (few and genuine)
- [x] complete run (91.6% of commits successfull)


# foundryvtt/pf2e

Only one test command `test` that is always just `jest`. We append `--coverage`. No `test` script before Apr 22 2020.

## Config

```json
"pf2e": {
    "url": "https://github.com/foundryvtt/pf2e",
    "node_version_lts_offset_months": 1
}
```

## Checklist
- [x] 100 done (97/100)
- [x] failed tests doublechecked (no failures)
- [x] complete run (99.8% of commits successfull (489 not applicable, missing package.json))

# moodlehq/moodleapp

Ionic/Angular mobile app for Moodle. Single test suite producing one lcov output.

- **`unit`**: Two eras — `ng test` (Karma, single commit ~Oct 2020) and jest (dominant, from ~Sep 2020 onward). Gulp builds lang/env files needed by tests (present from ~Feb 2021). Uses V8 coverage provider (babel-based Istanbul crashes silently). Coverage via `jest --coverage --coverageProvider=v8 --coverageReporters=lcov`.

Early commits (before test infrastructure exists) exit with code 2 (NOT APPLICABLE).

## Config

```json
"moodleapp": {
    "url": "https://github.com/moodlehq/moodleapp",
    "disabled_node_strategies": [
        "Angular compatibility"
    ]
}
```

## Checklist
- [x] 100 done (100/100)
- [x] failed tests doublechecked (few and genuine)
- [x] complete run (944 not applicable; 93.4% of remaining commits successful)

## Known Test Failures

- Rare genuine failures (3 out of 119 runs): Angular DI setup issues (`init.page.test.ts`), directive/component test setup (`link.test.ts`, `user-avatar.test.ts`, `iframe.test.ts`), service test (`navigator.test.ts`)
- `NG0203` Angular injection context warnings appear in logs (~410 per run) but do not cause test failures — tests pass despite these runtime warnings

# third-culture-software/bhima

Full-stack hospital information system: Node.js/Express backend with MySQL + Redis, AngularJS client. Runs 4 test suites, each producing separate lcov output.

- **`server-unit`**: mocha + c8. Two eras: `sh/server-unit-tests-node.sh` (shell_script) vs direct mocha (mocha_direct).
- **`client-unit`**: Karma + karma-coverage harness sidecar. Coverage validated for non-zero DA entries and AngularJS DI failures.
- **`integration`**: mocha + c8 against a live Express server. Requires MySQL (`build:db`), Redis, and Chromium.
- **`integration-stock`**: Same as integration, but requires separate `build:stock` DB seed. Runs after main integration, server killed between suites.

Client bundle built via `build` / `build:client` / `compile` (detected dynamically). c8 installed as fallback. Chromium runs with `--no-sandbox`.

## Config

```json
"bhima": {
    "url": "https://github.com/third-culture-software/bhima",
    "package_manager_version_overwrite": "npm"
}
```

## Checklist
- [x] 100 done (96/100)
- [x] failed tests doublechecked (genuine issues)
- [ ] complete run (wip)

## Known Test Failures

- `integration` suite (example commit `181f69`, 8 failures):
    - UTF-8 encoding mismatches (`RemunÃ©ration` vs `Remunération`) in `accountFYBalances` and `budget/import` — likely locale/db collation issue
    - `employee_config` DELETE expects 400, gets 404 — test expectation bug
    - `purchases` order 4: SQL out-of-range error on `purchase_interval` + calculation mismatches — date-dependent (faketime)
    - `staffingIndices` — DB state or date-dependent failures
    - `integration` logs ~217 `#interceptor()` messages from the Express error handler ([`server/config/interceptors.js`](https://github.com/third-culture-software/bhima/blob/181f6988df8c50988efa0607a608429ad6f05de5/server/config/interceptors.js)) — **all intentional negative tests**: deliberate 404s (nonexistent records), 400s (invalid data, `INVALID_RENDERER` from [`ReportManager.js:116`](https://github.com/third-culture-software/bhima/blob/181f6988df8c50988efa0607a608429ad6f05de5/server/lib/ReportManager.js#L116)), SQL constraint violations, and 401s (auth tests). Not real errors.
    - `ENOENT: bhima-bootstrap.css` (22 occurrences) — [`head.handlebars`](https://github.com/third-culture-software/bhima/blob/181f6988df8c50988efa0607a608429ad6f05de5/server/lib/template/partials/head.handlebars#L5) references a CSS build artifact (compiled from `client/src/less/bhima-bootstrap.less` via gulp) that doesn't exist in source. HTML report tests still pass because they assert on JSON rendering.

# gatsbyjs/gatsby

Lerna monorepo with `jest`. Two eras: jest 27 (before ~Nov 2022) and jest 29 (after).

- `test:coverage`: wraps jest with `--coverage` — primary test script across all eras
- `test`: runs lint, jest, and peril — we skip this and call jest directly

We call `jest --coverage --coverageReporters=lcov --maxWorkers=1 --testTimeout=120000` directly.

### Historical issues

- **jest 27 + Parcel timeout**: jest 27 does not intercept `process.exit()`. Gatsby's `reporter.panic()` calls `process.exit(1)` when Parcel fails. Parcel is slow in containers, causing jest teardown mid-compilation. Fixed via `--testTimeout=120000`. A `--setupFiles` process.exit guard is kept as a commented-out fallback.

## Config

```json
"gatsby": {
    "url": "https://github.com/gatsbyjs/gatsby"
}
```

## Checklist
- [x] 100 done (93/100)
- [x] failed tests doublechecked
- [x] complete run (93.1% of commits successful)

## Known Test Failures

This file causes exit code 1 for many tests, not because of test failures but because it is invalid JS that Babel cannot parse, which prevents coverage collection **for that file**. The test suite still runs and produces valid coverage for all other files, so this is a known, non-critical failure.

```
ERROR: /coverage_reloaded/repo/packages/gatsby-remark-prismjs/src/__tests__/fixtures/highlight-start-without-end.js: 'return' outside of function. (3:0)
```

### Non-critical logs

The following `console.error` / `console.warn` output is intentional test behavior — React development-mode warnings emitted inside test assertions. Not real errors.

- React prop validation warnings (`html-renderer.js`) — test deliberately triggers casing and unknown-prop warnings
- xhr-mock warnings (`dev-loader.js`) — test deliberately triggers missing handler paths
- gatsby-link external link warnings (`index.js`) — test verifies warning for external URLs in `<Link>`
- `Failed to collect coverage from highlight-start-without-end.js` — intentionally invalid JS fixture; Babel can't parse it, one file skipped
- `gatsby-source-wordpress` 502/503/504 errors — test deliberately triggers HTTP error paths

# serverless/serverless

Root workspace with mocha + nyc/c8. Two eras: nyc (early 2020) → c8 (dominant from ~2020 onward).

- `test`: primary suite, mocha-based with coverage
- Coverage via `nyc --reporter=lcov` or `c8 --reporter=lcov` depending on era

## Config

```json
"serverless": {
    "url": "https://github.com/serverless/serverless",
    "min_node_version": 12
}
```

## Checklist
- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [x] complete run (86.9% of commits successful, 93.9% excluding not-applicable commits)

## Not Applicable Commits

290 commits depend on @serverlessinc/sf-core, which is closed source.

## Known Test Failures

- **Ruby invokeLocal tests** (2 tests, ~0.08% of suite, all commits):
    * `#invokeLocalRuby context.remainingTimeInMillis should become lower over time`
    * `#invokeLocalRuby calling a class method should execute`
    * **Error:** `SyntaxError: Unexpected token t in JSON at position 1`
    * **Cause:** Ruby wrapper's `attach_tty` method prints `"tty unavailable"` in container environment (no TTY device). Test expects JSON output from Ruby handler, but output starts with 't' from the warning message.
    * **Impact:** Coverage unaffected — Ruby invocation logic verified by passing stub tests (`should call invokeLocalRuby when ruby2.7 runtime is set`). These 2 tests verify Ruby subprocess output format, not Serverless framework behavior.
    * **Fix attempts:** Tested Ruby 2.7 (Bullseye default) across 2020-2025 commits — same error persists, confirming environment issue, not Ruby version mismatch.

- **v3.0.0 release-train temporal mismatch** (clustered commits at committer timestamp `1643293318` = 2022-01-27 15:21:58):
    * A 247-commit rebase/merge cluster (the Serverless Framework v3.0.0 release train) shares a single committer timestamp while author dates span Jan 14–25, 2022. The pipeline snapshots dependencies at the **committer** timestamp (`collect_commits.py` uses `committer_date`), so WayPack serves post-rename dependency versions against pre-rename source code.
    * Two breaking dependency renames landed inside that window:
        1. Repo renamed `lib/utils/telemetry/areDisabled.js` → `are-disabled.js` (`c3e08ca34`, 2022-01-25); `@serverless/test@9.0.0` (published 2022-01-27) requires the new hyphenated path → `Cannot find module 'lib/utils/telemetry/are-disabled'`, **313 failing tests, exit 255** (5 commits observed).
        2. Repo adapted to `@serverless/dashboard-plugin`'s subpath rename `resolveProviderCredentials` → `resolve-provider-credentials` (`73b188604`, 2022-01-20); `@serverless/dashboard-plugin@6.0.0` (published 2022-01-27) only ships the new subpath → `Cannot find module '@serverless/dashboard-plugin/lib/resolveProviderCredentials'` (1 commit observed).
    * **Classification:** Setup/environment temporal artifact — not a WayPack defect, not a developer-facing test regression. The commits are transitional snapshots of the release branch; at their author date the caret range (`^9.0.0`) would not even resolve (only pre-releases existed) and there is no lockfile.
    * **Coverage impact:** are-disabled case = visible partial (1930 passing / 313 failing); dashboard-plugin case = aborts at load with near-empty coverage.
    * **Blast radius:** of the 247-cluster commits, ~172 have the old `areDisabled.js` and declare `@serverless/test@^9.0.0`; ~77 use the old dashboard-plugin subpath. These will reproduce when the full run reaches them.
    * **Fix attempts:** Not fixable in `install-and-run.sh`. Candidate mitigation: WayPack local override pinning `@serverless/test` → 8.8.0 and `@serverless/dashboard-plugin` → 5.5.4 for that timestamp (risky — older harness may be incompatible with v3-era code). Recommend documenting as known failure rather than forcing a green run.

# huridocs/uwazi

Root workspace with `jest` (24.8.0 → 27.5.1 → 29.7.0 across history), two jest projects (client/server), `--runInBand --forceExit`. Behavioral suite runs with coverage; ES via Docker-in-Docker, MongoDB 7.0, redis-server.

## Config

```json
"uwazi": {
    "url": "https://github.com/huridocs/uwazi"
}
```

## Checklist
- [x] 100 done (97/100)
- [x] failed tests doublechecked (failures below are known; none are bails)
- [x] complete run (98.7% of commits successful)

## Known Test Failures

All exit code 1 with valid (partial) coverage — never bails.

**Genuine test bugs (accept as valid partial, do NOT fix):**
- `NavlinkForm` / `NavlinksSettings` / `navlinksActions` — spec omits required `links` prop → TypeError + missing-spy
- `54-add_system_key_translations` — `Cannot read property 'value' of undefined`
- `18-fix-malformed-metadata` — `Expected ["123-c1","6","7"]`, `Received ["123-c1"]`
- `entitySavingManager` — `.pdf` vs `.jpg` (insertion-order vs sorted)
- `ModelWithPermissions` — doc order swapped (`$in`/insertion nondeterminism)
- `dateHelpers` — Arabic-Indic vs Latin digits (`٦ أكتوبر ٢٠٢٣` vs `6 أكتوبر 2023`, ICU locale data)
- `activitylogMiddleware` — async append race (`>0` vs `0`)

**Timeouts NOT fixable by raising `--testTimeout` (3 independent ceilings):**
- jest 24.8.0 ignores the flag entirely → stuck at 5000 ms default: `migrator`, `33-character-count`, `31-editDate`, `4-pdf_thumbnails`, `entitiesModel`, `exportRoutes`
- Hardcoded per-test/hook timeouts in specs (jest 29): `csvLoaderSelects` (`beforeAll` 10s), `distributedLoop` (10s/60s)
- `wait-for-expect` internal 4500 ms ceiling: `taskManager`, `socketClusterMode`, `distributedLoop` (redis/socket timing)
- `exportRoutes` hung past 60 s even where the flag applied — genuine hang, not slowness

# wowanalyzer/wowanalyzer

## Config

```json
"wowanalyzer": {
    "url": "https://github.com/wowanalyzer/wowanalyzer",
    "disabled_node_strategies": [
        "Dockerfile"
    ],
    "min_node_version": 12
}
```

## Checklist
- [kinda] 100 done
- [x] failed tests doublechecked
- [x] complete run (78 not applicable; 99.4% of remaining commits successful)

## Known Test Failures

- **WCL network isolation** (exit 1, `survivalIntegrationTests.test.ts`):
    * Integration tests fetch combat data from the Warcraft Logs API. In the sandboxed container the remote endpoint is unreachable, causing the parser to return zeros for all computed metrics (DPS, focus, cast counts). All 24 snapshot assertions diff against the zero values.
    * **Classification:** Setup/environment — not developer-facing. Developers running locally against WCL would not hit this.
    * **Coverage impact:** Warning-acceptable — exit 1 with valid partial coverage (6346/6377 tests pass at the affected commit). Coverage data is correctly measured for the passing tests.
    * **Future fix candidate:** Mock the WCL fetcher at the test boundary.

- **Priest Discipline SpellCalculations assertion mismatch** (exit 1, `SpellCalculations.test.js`):
    * `boltHealing` and `smiteHealing` values are consistently ~5-10% lower than expected across 7 assertions (e.g. expected `22` got `20`, expected `39` got `36`). Uses a `mockStatTracker()` with hardcoded stats.
    * **Classification:** Developer-facing — a genuine commit-level assertion failure that the developer would also have hit.
    * **Coverage impact:** Warning-acceptable — exit 1 with valid partial coverage.

**Test-suite structure (verified):** the main `test` script is a strict superset of the sub-suites. Until 2022-09-05 the repo shipped `integrationTests/*.test.ts` files (per-spec, loading bundled `.zip` fight logs), and the main `react-app-rewired test` run included them; `test:interface`/`test:parser` explicitly exclude them via `--testPathIgnorePatterns integrationTests`, while `test:integration` (`yarn test integrationTests`) is only a path-filtered view. Commit `1409e34b3a` (2022-09-05, "reorganize back into a mono-package") **deleted all integration test files** (fixtures + snapshots) and the same day `f8676e4951` switched `test:integration` to `--passWithNoTests`. `test:integration` was removed entirely with the vitest migration (`bd58e15539`, 2024-04-10). At the same time the overall coverage drops. The drop is amplified by the directory restructuring: the `analysis/` tree was moved into `src/analysis/`, and since `react-app-rewired` instruments all files under `src/`, instrumented lines jumped from ~10K to ~43K while test count fell from 69 to 49 files. Running only the main `test` suite therefore covers all behavioral code in every era; no sub-suites are needed.

---

# vega/vega-lite

Root workspace with `jest` (May 2020 – Feb 2025) and later `vitest` (Mar 2025+).

- **Jest era**: `test` runs jest; a separate `jest` script carries `--experimental-vm-modules` for ESM.
- **Vitest era**: `test --run` with `@vitest/coverage-istanbul`; separate `examples` suite.
- **Runtime suite** skipped: uses `@vitest/browser-playwright` (visual/selection, not behavioral coverage).

## Config

```json
"vega-lite": {
    "url": "https://github.com/vega/vega-lite"
}
```

## Checklist
- [x] 100 done (99/100)
- [x] failed tests doublechecked (genuine errors)
- [x] completed run (98.5% of commits successfull)

---

# n8n-io/n8n

Large monorepo. Orchestration evolved over the timeframe: **npm + lerna** (2020-01 → 2022-08, root `test` = `lerna run test`) → **npm + turbo** (2022-08 → 2022-11) → **pnpm + turbo** (2022-11 → 2025-12, root `test` = `turbo run test`).

Runners:
- **jest** — backend (`cli`, `core`, `workflow`, `nodes-base`, most `@n8n/*`) for the whole timeframe.
- **vitest** — frontend (`editor-ui`, `design-system`, `@n8n/chat`, etc.) from 2022; `workflow` from 2025-06.
- **vue-cli-service test:unit** — early frontend (2020-2022), wraps jest.
- No karma/mocha in `test` scripts. e2e (cypress → playwright) excluded; never part of the root `test` dispatch.

Approach: install + `npm run build`/`pnpm build` (tests import workspace packages via `dist/`), then `patch-coverage.js` walks every `package.json` outside `node_modules`/`.git`/`dist` and appends runner coverage flags:
- `jest` → `--coverage --coverageReporters=lcov --maxWorkers=2` (strips `--no-coverage`)
- `vitest` → `--coverage`
- `vue-cli-service` → `--coverage` + `"coverageReporters": ["lcov"]` into the package's `jest` key
- root `test`: `lerna run test` → `--no-bail --concurrency=2`; `turbo run test` → `--continue --concurrency=2`
- neutralises the 2025-07 `packages/testing/playwright` `test` script (e2e) to a noop

Then run the root `test` once with `COVERAGE_ENABLED=true` (activates n8n's own jest/vitest-config coverage gate) and call `find-and-move-lcov.sh "test" "true"`.

## Config

```json
"n8n": {
    "url": "https://github.com/n8n-io/n8n"
}
```

## Checklist
- [x] 100 done (~90/100)
- [ ] failed tests doublechecked (todo)
- [x] complete run (0 not applicable; 92.8% of remaining commits successful)

## Known Gaps (preliminary)
- **Frontend vitest 2022-04 → 2025-02**: `--coverage` alone uses vitest default reporters (no lcov) — those commits get backend-only coverage unless a reporter override/config patch is added.
- **cli unit gap ~2025-09-17 → 2025-10-31**: `test` pointed at the integration-only `jest.config.integration.js` before `test:unit` existed.
- Only the root `test` script is run; in a few short windows some packages exposed only `test:unit` (editor-ui 2022-08 → 2022-11) or only `test:integration` — their coverage is missed.
- The 2022-08 empty-script transition window may produce no lcov (errors rather than silent gaps).
- Test-suite runtime is large; the 90-min container budget is unvalidated.

## Known Test Failures

All exit code 1 with valid (partial) coverage — never bails.

- **`@n8n/n8n-benchmark#test`** — placeholder script (`echo "Error: no test specified" && exit 1`). No real tests exist. Coverage impact negligible; recommend excluding from turbo.
- **`n8n-core` SSL certificate assertion** — 2 tests in `node-execute-functions.test.ts` expect 4-key `Agent.options` but `https.Agent` now also exposes `defaultPort`/`protocol`. 46/47 suites pass (778/780 tests); partial coverage valid. Genuine upstream test bug.

---

# opencrvs/opencrvs-core

> ⚠️ **Preliminary.** First prototype only — `install-and-run.sh`, `Dockerfile`, and `patch-coverage.js` are written and dry-run-tested on git snapshots, but **no single-commit container run has been performed yet.** Expect era/runner edge cases to surface during validation.

Lerna monorepo with pnpm workspaces. Package manager evolved: **yarn** (2020-01 → ~2025-05) → **pnpm** (~2025-05 → 2025-12). Root test: `lerna run test --stream`.

Runners:
- **jest** — backend packages (`auth`, `commons`, `gateway`, `notification`, `search`, `user-mgnt`, `webhooks`, `workflow`, `config`) for the whole timeframe.
- **vitest** — `client` (from ~2022-08, replacing craco/jest), `events` (from 2024).
- **craco test** — `client` early era (2020-2022), wraps jest.
- **e2e**: `packages/e2e` uses Cypress — excluded; never part of the root `test` dispatch.
- **storybook**: `test-storybook` in client — excluded.

Approach: install + `lerna run build` (tests import workspace packages via `dist/`), then `patch-coverage.js` walks every `package.json` outside `node_modules`/`.git`/`dist`/`build`/`lib` and appends runner coverage flags:
- `jest` → `--coverage --coverageReporters=lcov --maxWorkers=2` (strips `--no-coverage`)
- `vitest` → `--coverage --reporters=lcov --maxWorkers=2`
- `craco test` → `--coverage --coverageReporters=lcov --maxWorkers=2`
- root `test`: `lerna run test` → `--no-bail --concurrency=1`
- neutralises `cypress`/`playwright` and `test-storybook` scripts to noops

Then run the root `test` once and call `find-and-move-lcov.sh "test" "true"`.

## Config

```json
"opencrvs-core": {
    "url": "https://github.com/opencrvs/opencrvs-core"
}
```

## Checklist
- [ ] 100 done (wip — first prototype, not yet validated in container)
- [ ] failed tests doublechecked
- [ ] complete run

## Known Gaps (preliminary)
- **Postinstall hook** (`node development-environment/link-ts6-api.js`): left to run; may fail in container if it expects certain paths.
- **Older commits (2020)**: `craco test` path is covered but untested — may need iteration.
- **Package manager transition (~2025-05)**: commits around the yarn→pnpm switch may have inconsistent lockfiles; the pipeline branches on `$IS_PNPM_MAIN_PM` / `$IS_YARN_MAIN_PM` based on which lockfile exists at the checked-out commit.
- **Test coverage flags missing in some packages**: `gateway` and `client` (latest era) lack `--coverage` in their test scripts; the patch script adds it.

## Known Test Failures

- **Storybook build failure** (commit `42315429`, 2023-04, Node 16): `lerna run build-storybook` fails — `build-storybook` binary missing from `node_modules`. Developer-facing: the project's own storybook build is broken at this commit. Hard failure, no coverage produced. No action needed — developers would hit this too.

---

## apollo-client

## Checklist
- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [x] complete run (97.9% of commits successful)

## Known Test Failures

All exit code 1 with valid (partial) coverage — never bails.

- **ObservableQuery refactoring cluster** (~42 timeout runs, ~43 assertion runs — all from 2020-04-30):
    * A 49-commit refactoring of `ObservableQuery` and `QueryManager` introduced async behavioral changes. Tests at intermediate commits expect specific `handleCount` thresholds via `subscribeAndCount` that the refactored code no longer meets, causing jest 5000 ms timeouts. Later commits in the same day fix them (e.g., `76e22d7a7 Fix ObservableQuery tests`). Developer-facing — tests genuinely broken at these intermediate snapshots.

- **TypeScript compilation errors in `optimistic.ts`** (62 runs):
    * `error TS6133: 'ApolloQueryResult' is declared but its value is never read` and `error TS2305: Module has no exported member 'Subscription'` — real import/type errors in the test file at affected commits. Developer-facing.

- **useQuery `stopPolling` flaky test** (~26 runs across 2019-12 to 2020-12):
    * `should not throw an error if stopPolling is called manually after a component has unmounted` — expects `renderCount === 2` but sometimes gets 3 due to extra re-renders from polling timing. Flaky/timing-sensitive; fails across unrelated commit dates.

- **Mutation `refetchQueries` assertion** (~11 runs, 2020-07 to 2020-12):
    * `allows refetchQueries to be passed to the mutate function` — `Expected: false / Received: true`. Developer-facing genuine test failures.

---

# Instrumentation issues

# alphagov/govuk-frontend

Tests fully jest based, we run `test` and inject the coverage flag. Workspaces do not have own general `test` script, only for screenshot tests.

> ⚠️ early commits use `jest` only to invoke `jest-puppeteer`, for which coverage collection is not possible. -> Archive

## Config

```json
"govuk-frontend": {
    "url": "https://github.com/alphagov/govuk-frontend"
}
```

## Checklist
- [x] 100 done (99/100)
- [x] failed tests doublechecked (seem like UI related errors, e.g., "scrolls the label or legend to the top of the screen" expectin 0 and receiving 0.828...)
- [no] complete run (----)

## V8 Instrumentation Drift (Node 22 → 24)

> **Note:** A >15pp line coverage rise and branch coverage drop between commits `5f4c845...` and `1748fe8...` is attributed to Node 22 (V8 12.x) → Node 24 (V8 13.6) instrumentation changes rather than behavioral code modifications.

- **Delta composition:** +963 line hits (+41.8%) consist almost entirely of `0→1` increments. Zero `covered→0` reversals observed.
- **Code pattern:** Delta lines are predominantly JSDoc blocks, class property declarations, and method signatures (e.g., `constructor`, `initControls()`), rather than executable logic. Validated across `accordion.mjs`, `button.mjs`, `tabs.mjs` (70-85% JSDoc/comments).
- **Root cause:** V8 12.x → 13.6 instrumentation maps preceding JSDoc blocks and ES method opening braces `{` as new branch entries, increasing coverage counts without corresponding behavioral execution changes.
- **Classification:** Environment-driven measurement variation — does not reflect code evolution or test behavior changes. Coverage data remains valid for the exposure variable; the delta represents instrumentation differences between V8 versions.

---

# Unstable


# polkadot-js/apps

Root workspace with `jest` (short era) and `polkadot-dev-run-test`. Packages without own scripts.

- `test`: runs `jest` and `polkadot-dev-run-test` with parameters, excluding "slow" tests.
- `test:all`: runs `polkadot-dev-run-test` with jest config for slow tests (require a running docker container)

We call both `test` and `test:all` when available and wrap them in c8.

## Config

```json
"polkadot-apps": {
    "url": "https://github.com/polkadot-js/apps",
    "node_version_overrides": [
        {
            "start_ts": 1628856104,
            "end_ts": 1657386674,
            "old_version": 12,
            "new_version": "14"
        }
    ]
}
```

## Checklist
- [x] 100 done (98/100)
- [ ] failed tests doublechecked
- [no] complete run

## Known Test Failures

- **node:test-era `jest.fn().mockClear has not been implemented`** (only in `test:all` / `unit_slow`, ~18 commits): the project's own `@polkadot/dev-test` jest-compat shim (the `jest` global on top of node:test) stubs `mockClear`, `mockReturnValue`, `mockResolvedValue`, `mockRejectedValue`, `mockReturnValueOnce`, `mockResolvedValueOnce`, `mockReturnThis`, `mockName`, `getMockName` to `throw new Error('… has not been implemented')` (via `stubObj` in `env/jest.js`). Specs that call e.g. `jest.fn().mockClear()` in a `beforeEach`/`afterEach` hook throw and the whole spec file fails to run, contributing ~0 coverage.
	* **Verified repo-intrinsic (faithful):** across the pinned `dev-test` versions at these commits (0.75.10 → 0.83.3) `env/jest.js` is byte-identical (same md5) and `mockClear` appears only in `MOCK_KEYS_STUB`, never as an implemented method. So the developers' own `yarn test:all` failed these specs too.
	* **Deliberately NOT polyfilled:** recovering them would inflate the exposure variable with coverage that never ran for the developers (a confound per AGENTS.md §1/§7), and any partial shim would be inconsistent (only `mockClear` covered, not `mockReturnValue` etc.). The resulting ~0 coverage for those specs is the faithful signal. Affects only `unit_slow`; the primary `unit` (`yarn test`) suite is clean.
- Runner-level `TypeError: Cannot read properties of undefined (reading 'error')` in `@polkadot/dev/scripts/polkadot-exec-node-test.mjs` `complete()` (2 commits) and an `Invalid key format` crypto/key spec failure (1 commit) — separate, genuine spec failures; exit 1 → valid partial coverage.
- `check configured chain endpoints` slow tests with multiple, separate, issues. Should have little effect on coverage though.
	* connect to real websocket urls on the internet (most of which do not exist)
	* raise TypeError: (0 , _xFetch.fetch)
- TypeError: Cannot read property 'proposeBounty' of undefined


---

# Integration test issues

# getsentry/sentry-javascript

Unit tests are simple, but there are different integration tests for the packages:

- remix
    - lerna
        - client: `yarn playwright test`
        - server: `jest --config=...`
    - workspace
        - client: `yarn playwright test`
        - server: `jest --config=...`, later `vitest run`
- browser
    - lerna
        - default: `test/integration/run.js`
    - workspace
        - default: `test/integration/run.js`
- nextjs (workspace and lerna)
    - lerna:
        - client: `yarn playwright test`
        - server: `jest --config=...`
    - workspace:
        - client: `node test/client.js --silent`, later `yarn playwright test`
        - server: `node test/server.js --silent`, later `jest --config=`, then `(cd test/integration && yarn test:server)`

additionally, there are various integration specific workspaces. Archiving the project because of the complexity of the integration tests and the difficulty of running them in a containerized environment. The integration tests require a large dependency tree of browsers, playwright, and other services that are not easily containerized at correct versions.

## Config

```json
"sentry-javascript": {
    "url": "https://github.com/getsentry/sentry-javascript"
}
```

## Checklist
- [no] 100 done
- [no] failed tests doublechecked
- [no] complete run

---

# Gated

Projects excluded from collection due to coverage gates (AGENT.md §7.2). The presence of coverage thresholds in the test pipeline confounds the exposure variable by incentivizing coverage-maintaining commits and making test failures indistinguishable from threshold breaches.

## npm/cli

Root and workspaces using `tap`.

- `test:coverage` uses the nyc-based --coverage flag
- `test` just calls tap

We call tap directly, appending the `--nyc-arg=--reporter=lcov` parameter.

⚠️ Coverage gate: defaults to 100% lines, checked between 08.2020 and 03.2024. Commits often reach it.

**Reason for exclusion:** Coverage threshold at 100% lines makes coverage indistinguishable from behavioral verification. Commits that reach the threshold inflate the exposure variable.

## metamask/metamask-extension

⚠️ Coverage Gates:

- nyc --check-coverage era (Mar 2020 – Apr 2021): Low risk — the 0% default made it a no-op.
    * [link](https://github.com/MetaMask/metamask-extension/blob/b1d090ac4d/package.json#L28-L30)
- jest coverageThreshold era (Apr 2021 – Jan 2023): Moderate risk — thresholds were low (6–52%) but rising, and jest-it-up prevented drops >5%.
    * [link](https://github.com/MetaMask/metamask-extension/blob/01c0d7823d988d15ddedbf9ad8fa6ca5f7f6ca73/jest.config.js#L12-L24)
- Custom merge-coverage.js era (Jan 2023 – Jun 2024): High risk — thresholds were substantial (57–71% lines) and the script also failed if coverage exceeded the threshold by >5%, creating a strong incentive to keep coverage within a narrow band.
    * [link](https://github.com/MetaMask/metamask-extension/blob/f6acedb6cc72f79f043317e5e1390e3cd62c05f7/coverage-targets.js)

**Reason for exclusion:** Three distinct eras of coverage gates with increasingly strict thresholds. The merge-coverage.js era also penalized exceeding thresholds, creating a narrow coverage band incentive.

# Inaccessible Issues

# artsy/metaphysics

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


# edgeapp/edge-react-gui

Root workspace with jest.

- `test`: default, sometimes uses `jest.config.js` or calls `test:sync` and `test:async`
- `test:sync`: jest with `jest.config.js`
- `test:async`: jest with `jest.async.config.js`

We call jest directly with whichever config is available.

## Config

```json
"edge-react-gui": {
    "url": "https://github.com/EdgeApp/edge-react-gui"
}
```

## Checklist
- [x] 100 done (96/100, installation process fails flaky)
- [x] failed tests doublechecked (ok)
    * between 2025-06 and 2022-09 the same test fails: expects 185, got 184
    * between 2021-05 and 2020-12... no tests fail, exit code is 1 because it skips one test.
- [x] complete run (~97% of commits successfull, after re-run of errors, might have duplicate logfiles)


# pubkey/rxdb

Mocha-based tests with storage variants. The install-and-run.sh handles significant complexity:

- Patches `.mocharc` to disable `bail: true` (present across entire project history)
- Runs `transpile` once, then iterates over available storage variants (memory, dexie, lokijs, pouchdb, dexie-worker, memory-validation, remote, foundationdb, mongodb)
- Coverage via `c8 --reporter=lcov`
- FoundationDB: detects API version from source, installs matching DEB packages + npm module
- MongoDB: started via Docker-in-Docker
- Skips `custom` (template placeholder, never functional) and `test:full` (empty test file)
- Skips `lokijs:worker` (duplicate of `lokijs`)

## Config

```json
"rxdb": {
    "url": "https://github.com/pubkey/rxdb",
    "node_version_lts_offset_months": 0,
    "node_version_delay_months": 0,
    "use_exact_node_version": true
},
```

## Checklist
- [x] 100 done (94/100; 4 more maybe fixable, some mongodb error in latest commits)
- [x] failed tests doublechecked (only few errors, seem genuine)
- [no] complete run (moved to archive before completion)


# linode/manager

The linode-manager project is a monorepo that runs 8 named test suites, detected by checking for specific root scripts. Each suite resolves to either a root-level command or a workspace package's test script, and runs via vitest (with `@vitest/coverage-istanbul`) or jest, both with coverage enabled and `--bail=0`. If none of the named scripts exist, it falls back to the generic `test` script.

- **`test:manager`** — runs tests for the manager package (jest or vitest)
- **`test:sdk`** — runs tests for the SDK package
- **`test:ui`** — runs UI component tests
- **`test:search`** — runs search-related tests
- **`test:validation`** — runs validation package tests
- **`test:utilities`** — runs utilities package tests
- **`test:queries`** — runs query-related tests
- **`test:shared`** — runs shared package tests
- **Fallback `test`** — only if none of the above scripts exist

Skipping build-only and lerna bootstrap scripts. Coverage is collected per-suite via lcov, using the project's native runner (vitest or jest).

## Config

```json
"linode-manager": {
    "url": "https://github.com/linode/manager"
}
```

## Checklist
- [x] 100 done (96/100)
- [x] failed tests doublechecked (genuine errors)
- [no] complete run (cancelled moved to archive)

## Known Test Failures

- Async issues, timeouts and assertion errors in `unit` suite
- Timeouts and "unable to find an element" UI validation in `test:manager` suite


---

# Flagged Items

Implementation details not captured in the per-project descriptions above:

1. **linode-manager buildRequests.js patch** — install-and-run.sh patches `packages/manager/scripts/buildRequests.js` to skip live API caching during build.
2. **govuk-frontend GitHub URL rewriting** — install-and-run.sh replaces all GitHub URLs in source files (excluding package.json) with WayPack proxy URLs.
3. **yari content repo** — install-and-run.sh checks out a separate content repository at a timestamp-matched commit.

