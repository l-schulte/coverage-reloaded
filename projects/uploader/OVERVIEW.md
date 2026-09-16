# uploader

**Repository:** https://github.com/tidepool-org/uploader
**Status:** active

## Test infrastructure

- **Package manager:** yarn (see [`config.json`](../../config.json) → `uploader`); yarn 1 until
  2025-01-31, yarn 3.6.4 afterwards.
- **Node strategy:** default with `min_node_version = 12`. The 2021 mainline commits declare
  `10.17.0` in `.nvmrc` while CI installed `12.13.0`; the minimum clamps those commits to
  node 12.
- **Runners:** `jest` executed through a custom Electron test runner —
  `@jest-runner/electron` (window start to 2025-01-31), then `@kayahr/jest-electron-runner`
  (2025-01-31 onward). Tests run in Electron's renderer environment and require a display
  (Xvfb in the container).
- **Eras:** the `test` script (`cross-env NODE_ENV=test BABEL_DISABLE_CACHE=1 jest`) is
  unchanged for the entire window; `testMatch` is `**/test/(app|lib)/**/*.js`. The runner,
  Electron, and yarn-major transitions occur on 2025-01-31.

## Coverage collection

- **Suites collected:** `unit` — the combined jest behavioral suite (`test/app` and
  `test/lib`) run through the Electron runner.
- **Suites excluded:** e2e. `test:e2e` (Playwright) exists only on an unmerged 2024 topic
  branch; legacy Spectron (`test/spectron`, `test/e2e.js`) predates the study window.
- **Coverage tool / config:** jest's built-in coverage (babel/istanbul). The project defines
  no coverage configuration and no thresholds.
- **LCOV production:** `yarn test --coverage --coverageReporters=lcov --runInBand` writes
  `coverage/lcov.info`, which `find-and-move-lcov.sh` moves to the report path.
- **Suite excluded at runtime:** `test/lib/tandem/testTandemSimulator.js` is skipped on
  commits where `lib/drivers/tandem/tandemSimulator.js` is not part of the repository tree
  (see Known test failures and Known gaps). Detection is per-commit via the revision tree
  (not a date), so pre-2022 commits still run the suite.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (4 non-zero-exit runs inspected; all classified developer-facing)
- [ ] complete run (not started; 100 of 2410 commits sampled)
- [ ] complete test failure check (no labels produced yet)

## Results

Source: `stats_output/report.txt` (generated 2026-09-16 18:54).

| Metric | Value |
|---|---|
| Commits processed | 100 |
| Without test failures | 96 |
| With test failures | 4 |
| Not applicable | 0 |
| Hard errors | 0 |
| Coverage produced | 100.0% |

2310 commits remain unprocessed. Full statistics and plots:
[`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `Cannot find module '.../lib/drivers/tandem/tandemSimulator.js'` (`test/lib/tandem/testTandemSimulator.js`, from 2022-06-22) | environment/setup (private submodule not available) | before fix: one suite failed to load, exit code 1 with valid partial coverage; after fix: suite excluded, exit code 0 | Fixed by conditional per-commit exclusion in `install-and-run.sh` (2026-09-15); the driver source became external at `34e707f87`/`e98a41a6f` and the suite targets only that external code |
| `Cannot find module '../../../app/actions/index.'` (`test/app/reducers/misc.test.js`, commit `8f92a5bd`, 2025-09-08) | acceptable (project typo introduced by that commit) | one suite does not load at that commit only | None; resolved in later commits (outside the current 100-commit sample) |
| `async`/`sync`/`utils`: expected action lacks the `os` metric property (`test/app/actions/{async,sync,utils}.test.js`, commit `350128d`, 2022-03-21, branch `v2.44.0-os-metrics.1`) | acceptable (developer-facing; `app/actions/sync.js` adds `os: \`${os.platform()}-${os.arch()}-${os.release()}\`` to metric properties without updating the tests) | 13 tests fail, exit code 1; coverage valid and partial (see [`1647874605_350128ded...log`](logs/1647874605_350128dedb681a544ce2a41120e9cdc871ef6766.log)) | None; not an environment artifact |
| `misc.test.js` HIDE_UNAVAILABLE_DEVICES [mac]/[win] (`test/app/reducers/misc.test.js`, commits `c003386`, 2021-04-29; `c66ebdc`, 2023-01-18) | acceptable (developer-facing; `app/reducers/misc.js` has the availability filter commented out, so the reducer returns all devices) | 2 tests fail, exit code 1; coverage valid (see [`1619688392_c003386...log`](logs/1619688392_c003386565e2ea00055dfb424fb2ec01a0988559.log), [`1674058762_c66ebdc...log`](logs/1674058762_c66ebdc8ae85658906eb794be429cc23a937d9d7.log)) | None; not an environment artifact |
| `async.test.js` readFile wrong file extension (`test/app/actions/async.test.js`, commit `4430fff`, 2024-01-25) | acceptable (developer-facing; the test expects `CHOOSING_FILE → READ_FILE_ABORTED`, but only one action is dispatched) | 1 test fails, exit code 1; coverage valid (see [`1706194624_4430fff...log`](logs/1706194624_4430fffd6e5c97d9efb85700cd35b01275c02fd6.log)) | None; not an environment artifact |

No `failure_labels_project.csv` exists yet; classifications above are from direct log
inspection and have not been labelled.

## Environment / setup fixes

- `min_node_version = 12`: 2021 `.nvmrc` declares node 10 while CI used node 12.
- Dockerfile: `libudev1` downgraded to the version required by `libudev-dev` (bullseye main
  serves a newer `libudev1` than the matching `-dev` package).
- Dockerfile: Xvfb plus Electron/GTK/DBus runtime libraries and native build headers
  (usb, serialport, drivelist, keytar).
- Electron binary fetched through the WayPack mirror; the `electron-chromedriver` cache is
  pre-seeded from WayPack for spectron-era commits because `@electron/get` and
  `electron-download@4` expect different `ELECTRON_MIRROR` conventions.
- `node_modules/electron/cli.js` patched to pass `--no-sandbox` (container runs as root).
- `ENV NPM_CONFIG_LOCATION=global` applied image-wide so `execute.sh` can run its
  `npm config set` calls; `install-and-run.sh` unsets it. Required because the project's
  legacy `devEngines` block is rejected by npm >= 10.9, which the node-22 era ships.
- `install-and-run.sh`: excludes `test/lib/tandem/testTandemSimulator.js` when
  `lib/drivers/tandem/tandemSimulator.js` is absent from the commit tree. The suite only
  covers the external private driver, which cannot be fetched (see Known gaps).

## Known gaps

- `lib/drivers/tandem` and `lib/drivers/fora` are private git submodules
  (`git@github.com:tidepool-org/tandem-driver.git`, `.../fora-driver.git`). They are not
  initialized in the collection environment and cannot be fetched (private; SSH is
  redirected to anonymous HTTPS and anonymous access returns 404 — see
  tidepool-org/uploader#1698).
- Structural break (Tandem): `34e707f87` (2022-06-22) removed the in-tree driver source and
  `e98a41a6f` added the submodule gitlink, so from 2022-06-22 the Tandem simulator is no
  longer part of the repository. `test/lib/tandem/testTandemSimulator.js` then cannot load
  and is excluded on exactly those commits; ~231 instrumented tandem-simulator lines leave
  the coverage universe at that point. `fora` was added 2025-04-01 (`cda8f3a87`) but has no
  tests.
- E2E suites are not collected: Playwright is unmerged and Spectron predates the window.
- The run is incomplete (100 of 2410 commits); no failure labelling has been performed.
  Three aborts in the 100-commit batch (a yarn cache-extraction race, an Electron binary
  download 5xx, and corrupt Electron headers) were transient and produced valid coverage on
  re-run; `stats_output/report.txt` records 0 hard errors.
