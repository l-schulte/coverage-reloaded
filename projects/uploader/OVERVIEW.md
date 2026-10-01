# uploader

**Repository:** https://github.com/tidepool-org/uploader
**Status:** active

## Test infrastructure

- **Package manager:** yarn (see [`config.json`](../../config.json) → `uploader`); yarn 1 until 2025-01-31, yarn 3.6.4 afterwards.
- **Node strategy:** default with `min_node_version = 12`. The 2021 mainline commits declare `10.17.0` in `.nvmrc` while CI installed `12.13.0`; the minimum clamps those commits to node 12.
- **Runners:** `jest` executed through a custom Electron test runner — `@jest-runner/electron` (window start to 2025-01-31), then `@kayahr/jest-electron-runner` (2025-01-31 onward). Tests run in Electron's renderer environment and require a display (Xvfb in the container).
- **Eras:** the `test` script (`cross-env NODE_ENV=test BABEL_DISABLE_CACHE=1 jest`) is unchanged for the entire window; `testMatch` is `**/test/(app|lib)/**/*.js`. The runner, Electron, and yarn-major transitions occur on 2025-01-31.

## Coverage collection

- **Suites collected:** `unit` — the combined jest behavioral suite (`test/app` and `test/lib`) run through the Electron runner.
- **Suites excluded:** e2e. `test:e2e` (Playwright) exists only on an unmerged 2024 topic branch; legacy Spectron (`test/spectron`, `test/e2e.js`) predates the study window.
- **Coverage tool / config:** jest's built-in coverage (babel/istanbul). The project defines no coverage configuration and no thresholds.
- **LCOV production:** `yarn test --coverage --coverageReporters=lcov --runInBand` writes `coverage/lcov.info`, which `find-and-move-lcov.sh` moves to the report path.
- **Suite excluded at runtime:** `test/lib/tandem/testTandemSimulator.js` is skipped on commits where `lib/drivers/tandem/tandemSimulator.js` is not part of the repository tree (see Known test failures and Known gaps). Detection is per-commit via the revision tree (not a date), so pre-2022 commits still run the suite.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (inspected non-zero-exit runs; verified genuine developer regressions)
- [x] complete run (2410 of 2410 commits processed)
- [x] complete test failure check (all 64 fingerprints across 95 failing runs labeled and assessed; 51 acceptable, 13 reevaluated_acceptable, 0 problematic, 0 unclear)
- [x] complete JEV test failure check (automated System 1 labeling via Jev evaluated all 64 signatures; all 12 flagged problematic signatures audited against git history and confirmed to be genuine developer-facing regressions)

## Results

Source: `stats_output/report.txt` (generated 2026-10-01 15:50).

| Metric | Value |
|---|---|
| Commits processed | 2410 |
| Without test failures | 2288 |
| With test failures | 95 |
| Not applicable | 0 |
| Hard errors | 27 |
| Coverage produced | 98.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

All 64 failure fingerprints across 95 failing runs are developer-facing code or configuration mistakes committed to git; none is an artifact of the collection pipeline. Labels are documented in [`failure_labels_project.csv`](failure_labels_project.csv) and [`failure_labels_jev.csv`](failure_labels_jev.csv).

| Signature / Error | Classification | Coverage impact | Action / Root Cause |
|---|---|---|---|
| `Cannot find module '.../lib/drivers/tandem/tandemSimulator.js'` (`test/lib/tandem/testTandemSimulator.js`, from 2022-06-22) | reevaluated_acceptable (private submodule not available) | Before fix: suite failed to load, exit code 1 with valid partial coverage; after fix: suite excluded, exit code 0 | Excluded conditionally in `install-and-run.sh`; the driver source became an external private submodule at `34e707f87`/`e98a41a6f` and the suite exercises only that external code. |
| `SyntaxError: Cannot use 'import.meta' outside a module` (`testCommonFunctions.js`, `testMedtronic600Simulator.js`, commit `8e940c63f`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Upstream commit `8e940c63f` introduced `import.meta.url` in `app/utils/ipc.js` during Node 22 upgrade; developer fixed it 3 hours later in `aef83e362` (*"fix tests"*). |
| `Loading non-context-aware native module in renderer ... usb_bindings.node` (`test/lib/testSerialDevice.js`, commits `0c28ad508` to `59005b934`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Top-level `require('usb')` left unguarded during Electron 12 upgrade; developer fixed it in `6e330bf4e9` by scoping `require('usb')` to non-test environments. |
| `Cannot find module '../../lib/core/driverManifests'` (`test/app/actions/async.test.js`, commits `0c28ad508` to `888cbbbc8`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Developer imported `driverManifests.js` before adding the file to git; committed missing file 2 commits later in `59005b934`. |
| `SyntaxError: Unexpected token 'export'` (`node_modules/webmtp/mtp.js`, commit `673e3dd93`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Developer bumped `webmtp` to an ESM build; fixed 47 minutes later in `851dade0a` (*"fix jest for es6 module"*). |
| `TypeError: Cannot read properties of undefined (reading 'on')` (`test/app/reducers/working.test.js`, commit `00679046d`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Merged test file mocked `electron` instead of `@electron/remote`; fixed 30 minutes later in `622871643` (*"fixing issues after merge"*). |
| `SyntaxError: .../app/actions/async.js: Unexpected token (271:4)` (`test/app/reducers/users.test.js`, commit `7bbd7f016`) | reevaluated_acceptable (developer regression) | Suite fails to load, exit code 1; valid partial coverage | Syntax typo committed by developer (duplicate closing `}); };` blocks); resolved in subsequent commit. |
| Behavioral test assertion failures (`HIDE_UNAVAILABLE_DEVICES`, `doUpload`, `doVersionCheck`, `doLogin`, simulator assertions) | acceptable (developer-facing test regressions) | Test assertion failures, exit code 1; valid partial coverage | Genuine unit test assertion failures across 51 distinct fingerprints. |

## Environment / setup fixes

- `min_node_version = 12`: 2021 `.nvmrc` declares node 10 while CI used node 12.
- Dockerfile: `libudev1` downgraded to the version required by `libudev-dev` (bullseye main serves a newer `libudev1` than the matching `-dev` package).
- Dockerfile: Xvfb plus Electron/GTK/DBus runtime libraries and native build headers (usb, serialport, drivelist, keytar).
- Electron binary fetched through the WayPack mirror; the `electron-chromedriver` cache is pre-seeded from WayPack for spectron-era commits because `@electron/get` and `electron-download@4` expect different `ELECTRON_MIRROR` conventions.
- `node_modules/electron/cli.js` patched to pass `--no-sandbox` (container runs as root).
- `ENV NPM_CONFIG_LOCATION=global` applied image-wide so `execute.sh` can run its `npm config set` calls; `install-and-run.sh` unsets it. Required because the project's legacy `devEngines` block is rejected by npm >= 10.9, which the node-22 era ships.
- `install-and-run.sh`: excludes `test/lib/tandem/testTandemSimulator.js` when `lib/drivers/tandem/tandemSimulator.js` is absent from the commit tree. The suite only covers the external private driver, which cannot be fetched (see Known gaps).

## Known gaps

- `lib/drivers/tandem` and `lib/drivers/fora` are private git submodules (`git@github.com:tidepool-org/tandem-driver.git`, `.../fora-driver.git`). They are not initialized in the collection environment and cannot be fetched (private; SSH is redirected to anonymous HTTPS and anonymous access returns 404 — see tidepool-org/uploader#1698).
- Structural break (Tandem): `34e707f87` (2022-06-22) removed the in-tree driver source and `e98a41a6f` added the submodule gitlink, so from 2022-06-22 the Tandem simulator is no longer part of the repository. `test/lib/tandem/testTandemSimulator.js` then cannot load and is excluded on exactly those commits; ~231 instrumented tandem-simulator lines leave the coverage universe at that point. `fora` was added 2025-04-01 (`cda8f3a87`) but has no tests.
- E2E suites are not collected: Playwright is unmerged and Spectron predates the window.
- 27 hard errors occurred across 2410 commits (transient network 5xx or build timeout issues), achieving a 98.9% coverage production rate.
