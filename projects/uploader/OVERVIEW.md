# uploader

**Repository:** https://github.com/tidepool-org/uploader
**Status:** active

## Test infrastructure

- **Package manager:** yarn (see [`config.json`](../../config.json) → `uploader`); yarn 1 until 2025-01-31, yarn 3.6.4 afterwards.
- **Node strategy:** default with `min_node_version = 12`. The 2021 mainline commits declare `10.17.0` in `.nvmrc` while CI installed `12.13.0`; the minimum clamps those commits to node 12.
- **Runners:** `jest` executed through a custom Electron test runner — `@jest-runner/electron` (window start to 2025-01-31), then `@kayahr/jest-electron-runner` (2025-01-31 onward). Tests run in Electron's renderer environment and require a display (Xvfb in the container).
- **Eras:** the `test` script (`cross-env NODE_ENV=test BABEL_DISABLE_CACHE=1 jest`) is unchanged for the entire window; `testMatch` is `**/test/(app|lib)/**/*.js`. The runner, Electron, and yarn-major transitions occur on 2025-01-31.

## Development style

- **PR merging strategy:** Merge commit (90.6% of first-parent commits; 94.5% overall).
- **Merge convention:** `Merge pull request #<PR> from <branch>`.
- **Direct commits:** Low (9.0% human direct commits, 22 commits).
- **JS/TS code impact of direct commits:** Low — emergency packaging and Electron build rebuilder fixes by lead engineer (`try without legacy rebuilder`, `drop npmRebuild as it breaks windows build`).
- **Issue tracking discipline:** High (medical software repository, changes gated through Tidepool PR review).
- **Workflow notes:** Classical merge-commit integration model on `develop`.

## Coverage collection

- **Suites collected:** `unit` — the combined jest behavioral suite (`test/app` and `test/lib`) run through the Electron runner.
- **Suites excluded:** e2e. `test:e2e` (Playwright) exists only on an unmerged 2024 topic branch; legacy Spectron (`test/spectron`, `test/e2e.js`) predates the study window.
- **Coverage tool / config:** jest's built-in coverage (babel/istanbul). The project defines no coverage configuration and no thresholds.
- **LCOV production:** `yarn test --coverage --coverageReporters=lcov --runInBand` writes `coverage/lcov.info`, which `find-and-move-lcov.sh` moves to the report path.
- **Suite excluded at runtime:** `test/lib/tandem/testTandemSimulator.js` is skipped on commits where `lib/drivers/tandem/tandemSimulator.js` is not part of the repository tree (see Known gaps). Detection is per-commit via the revision tree (not a date), so pre-2022 commits still run the suite.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (inspected non-zero-exit runs; verified genuine developer regressions)
- [x] complete run (2410 of 2410 commits processed)
- [x] complete test failure check (all 82 fingerprints across 95 failing runs labeled and assessed; 81 acceptable, 1 reevaluated_acceptable, 0 problematic, 0 unclear)
- [x] complete JEV test failure check (automated System 1 labeling via Jev evaluated all 82 fingerprints; 1 flagged signature audited in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) and confirmed as commit-era upstream regression)

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 08:13).

| Metric | Value |
|---|---|
| Commits processed | 2410 |
| Without test failures | 2288 |
| With test failures | 95 |
| Not applicable | 0 |
| Hard errors | 27 |
| Coverage produced | 98.9% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py uploader --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 08:13). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 95 |
| Failing runs (label DB) | 95 |
| Fingerprints (min / max) | 82 / 116 |
| Labeled fingerprints | 82 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 81 |
| reevaluated_acceptable | 1 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 50 / 32 |
| Labeled detections (min) | 355/355 (100.0%) |
| Labeled runs (min) | 95/95 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 1 flagged rows (audited in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md)) |
| Jev audit | current |

**State:** complete.

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
