# desktop

**Repository:** https://github.com/desktop/desktop
**Status:** active

## Test infrastructure

- **Package manager:** yarn (`yarn@1.9`, `yarn.lock`) throughout the study window, single
  package without workspaces; `engines` requires `node >= 10` and `yarn >= 1.9`. The
  project vendors its own Yarn (`vendor/yarn-<version>.js`) and the `postinstall` hook
  invokes it, so container runs report Yarn 1.21.1 even though the harness installs
  `yarn@1.9` (see [`config.json`](../../config.json) → `desktop`).
- **Node strategy:** default — the commit's `.nvmrc` is used verbatim: 12/14 (2019–2021),
  16 (2022–2023), 18 (2023–2024), 20 (2024–2025), 22 (2025). No override in `config.json`.
- **Runners:** `jest` (23 → 26 → 29) with `electron` as the unit-test host
  (`ELECTRON_RUN_AS_NODE=1`) until 2025; the Node test runner (`node --test` driven by
  `tsx`) from 2025-03-26; `mocha` + `ts-node` only in the pre-window era.
- **Eras:**
  - before 2019-04-12: `test:unit` = jest under Electron; `test:script` and
    `test:integration` = `mocha` + `ts-node` (pre-window).
  - 2019-04-12: `test:script` and `test:integration` move to jest
    (`script/jest.config.js`, `app/jest.integration.config.js`).
  - 2021-02-11: jest 23 → 26, shipped with the Electron 11 upgrade (PR #11142).
  - 2021-07-04: `test:eslint` = `jest eslint-rules/tests/*.test.js` added; absent before.
  - 2022-01-20: `test:integration` and `spectron` removed upstream (`1d91a0b9ed`).
  - 2022-05-04: `test:unit:cov`, `test:script:cov`, `collectCoverageFrom` and
    `.codecov.yml` removed (`2db2edbfa6` "Bye bye coverage", `4686d0006a`); `test` becomes
    `yarn test:unit --runInBand && yarn test:script`.
  - 2023-11-30 to 2023-12-11: the unit config is reworked for dexie/uuid-dependent tests
    and switches to `testEnvironment: 'jsdom'`; jest 26 → 29 and TypeScript 5 land with
    the `ts5` merge (PR #17315, 2023-12-11).
  - 2025-04-02: jest removed (PR #20261 "jestless", branch commits from 2025-03-26):
    `test:unit` = `node script/test.mjs`, `test:script` = `node script/test.mjs script`,
    `test:eslint` = `node script/test.mjs eslint-rules`.
  - 2026-03-19: a Playwright end-to-end suite (`test:e2e`) is added — outside the window.

## Development style

- **PR merging strategy:** Merge commit (classic merge) for the whole window; no squash or
  rebase merges are used.
- **Merge convention:** `Merge pull request #<PR> from <branch>` — 100% of first-parent
  commits in 2019, 2021 and 2025, and 98–99.7% in 2020 and 2022–2024. The only
  non-conforming merge in the window is `Merge branch 'askpass' into development`
  (2024-05-08).
- **Direct commits:** Minimal — 12 of 2,743 first-parent commits (0.4%), all from the
  maintainer accounts `tidy-dev` (10) and `Billy Griffin` (2).
- **JS/TS code impact of direct commits:** Hotfixes and reverts only — 8 of 14 changed
  files are TSX (57.1%), all in `app/src/ui/app.tsx`: four commit/revert pairs on
  2022-04-25 editing the "pull request checks failed" copy, plus two SCSS edits to
  `app/styles/ui/_no-branches.scss` (2023-01-04). The remaining four files are `.github`
  issue templates.
- **Issue tracking discipline:** Low in git-visible terms — 1.5% of merge commits carry an
  issue number in the PR title or branch name. The project links work through pull-request
  descriptions and an organisation project board, neither of which is part of the
  repository, so issue linkage is not measurable from git history.
- **Workflow notes:** All changes land on `development` through GitHub pull requests from
  contributor forks or `desktop/*` branches; maintainers push direct commits only in
  exceptional cases. Release preparation is automated through the `draft-release` scripts
  and GitHub workflows.

## Coverage collection

- **Suites collected:** `unit` (jest on `app/test/unit/**/*-test.ts{,x}` until 2025-04, then
  the Node test runner on the same tree) and `script` (`jest --config ./script/jest.config.js`,
  then `node script/test.mjs script`). The unit tree grows from 88 test files (2019-05) to 115
  (2025-12) — 109 at the 2021-06-04 commit, 110 at 2021-09-03, 114 at 2024-12-23 — and every
  file is collected: the suites executed equal the test files present on disk at each commit.
- **Suite excluded — `integration` (2016-08-03 to 2022-01-20):** it is an end-to-end launch
  test in disguise, not an integration suite. `app/test/integration/launch-test.ts` — the
  only file that directory ever contained — spawns the webpack-built application from
  `out/` as a separate Electron process through `spectron` and asserts only OS window state
  (`getWindowCount`, `isVisible`, `isMinimized`, `getBounds`). Three consequences follow:
  (1) it cannot run without `yarn build:dev|prod` first — CI invokes it only after the
  production build, and `script/build.ts` even runs `yarn install` inside `out/`; (2) the
  application code executes in the child process, so jest's Istanbul counters in the parent
  process see no project file — `app/jest.integration.config.js` defines no
  `collectCoverageFrom`, there is no `test:integration:cov`, and the project's codecov
  upload reads only `app/coverage/coverage-final.json` from the unit run; (3) forcing
  `--coverage` would therefore emit an empty LCOV and fail the run. Upstream classified the
  suite the same way: it was deleted on 2022-01-20 together with spectron, and a genuine
  Playwright end-to-end suite (`test:e2e`) was introduced on 2026-03-19.
- **Suite excluded — `eslint` (2021-07-04 to present):** `test:eslint` exists from 2021-07-04
  onwards, but it is not a coverage suite: it runs the project's *custom lint rules* through
  ESLint's `RuleTester`, asserting diagnostics on inline code strings
  (`code: 'const b = Math.random();'`, with `filename: 'app/src/ui/component.tsx'` strings
  chosen only to select a rule's file mode).
  No product code executes, and the resulting lcov covers just `eslint-rules/**` — four rule
  implementations, ~134 lines, in the current runs. It is also outside the project's own
  coverage intent: there is no `test:eslint:cov`, the root `test` script never invokes it
  (`yarn test:unit:cov` + `yarn test:script:cov`, and CI runs `test`/`test:unit`/`test:script`
  only), and the codecov upload reads `app/coverage/coverage-final.json` from the unit run.
  Under the Node test runner it additionally failed systematically, because
  `node script/test.mjs eslint-rules` discovers zero files (the helper's filter matches
  `-test.<ext>`, these are `*.test.js`) and `node --test` then swept the whole repository,
  running unrelated trees. Collecting it therefore contributed no signal for product code,
  only a dev-tooling lcov and a failure mode; it was dropped on 2026-10-16. `unit` and `script`
  are the only collected suites, matching the project's own coverage intent.
- **Focus markers (`.only`):** the guard is runner-aware. Desktop's collected suites run under
  jest (jest 23/26/29 on `app/test/unit` and `script`) until 2025-04 and under
  Node's test runner thereafter, and both honour `.only` per file, so the helper is called as
  `na_if_focus_marker --runner jest --runner node`. A marked commit is measured with a
  recorded deficit instead of being dropped: the whole suite runs, and the marked file(s) are
  listed in a `focus_marker.txt` sidecar inside the commit's own output directory
  (`<timestamp>_<revision>/focus_marker.txt`, alongside its lcov files). This matters because a single
  `it.only` in `app/test/unit/desktop-file-transport-test.ts` persisted upstream from
  2022-03-14 to 2025-04-02 — 5,827 of 10,034 commits (58.1%) — which a run-global policy would
  have removed from the exposure variable entirely.
- **Coverage tool / config:** jest's Istanbul instrumentation until 2025-04, then V8
  coverage through `c8` (the harness wraps `node script/test.mjs` with
  `c8 --reporter=lcov`, sourced from Verdaccio). `app/jest.unit.config.js` sets
  `collectCoverageFrom: ['src/**/*.{js,jsx,ts,tsx}']` with `!**/node_modules/**`,
  `!**/vendor/**`, `!**/*.d.*`, `!src/cli/**/*`, `!src/crash/**/*`,
  `!src/highlighter/**/*` and `!**/index.ts` until 2022-05-04. From 2022-05-04 the project
  configures no coverage scope, so `--coverage` falls back to jest's default, which
  instruments only the files loaded by the run — see Known gaps.
- **No coverage gate:** no `--check-coverage`, no `coverageThreshold` in any jest config,
  and the project's `.codecov.yml` (present until 2022-05-04) set `status: off`.
- **LCOV production:** the run forces `--coverage --coverageReporters=lcov`, overriding the
  project configs that emit only `text-summary`/`json`/`html`/`cobertura`;
  `find-and-move-lcov.sh` moves each suite's `lcov.info` out as `unit.lcov` and
  `script.lcov`.

## Checklist

- [x] 100 done
- [x] failed tests doublechecked
- [x] complete run
- [x] complete test failure check
- [x] complete JEV test failure check

A 100-commit sample spanning 2021-01 to 2025-11 was reviewed: its hard errors were analysed
one by one and its non-zero-exit runs grouped and classified, which is what the first two
items record. That sample is archived in [`archive/run1/`](archive/run1/). The full-history run
completed with all 10,034 commits processed; the 12 transient timeout commits previously
archived to [`archive/promisor_remote_timeout/`](archive/promisor_remote_timeout/) and
[`archive/rebase_progress_timeout/`](archive/rebase_progress_timeout/) were cleanly re-run,
recovering 11 passing commits.

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 18:15).

| Metric | Value |
|---|---|
| Commits processed | 10,034 |
| Without test failures | 8,901 |
| With test failures | 615 |
| Not applicable | 0 |
| Hard errors | 518 |
| Coverage produced | 94.8% |

All commits with a committer date in the study window (2021-01-01 → 2025-12-31) are
processed. The author dates recorded in `commits.csv`, which anchor the dependency snapshot for
each run, span 2019-04-12 → 2025-12-31 because 41 commits were authored before 2021 and
committed inside the window. The reviewed 100-commit sample is archived in
[`archive/run1/`](archive/run1/); the causes that remain relevant are recorded under Known test
failures and Environment / setup fixes. Full statistics and plots:
[`stats_output/`](stats_output/).

Coverage by year across the 9,516 coverage-producing runs (derived from
`stats_output/commits_detail.csv`):

| Year | runs | rate min | median | rate max |
|---|---|---|---|---|
| 2019 | 20 | 30.6% | 31.2% | 31.3% |
| 2020 | 21 | 23.3% | 31.2% | 31.8% |
| 2021 | 2,628 | 8.8% | 31.1% | 31.9% |
| 2022 | 2,067 | 8.4% | 30.7% | 44.7% |
| 2023 | 2,043 | 26.8% | 32.3% | 53.5% |
| 2024 | 1,686 | 30.6% | 39.6% | 58.0% |
| 2025 | 1,051 | 39.6% | 54.4% | 72.1% |
| **all** | **9,516** | **8.4%** | **31.7%** | **72.1%** |

The 31–33% band through 2023 is the project's own coverage under its own
`collectCoverageFrom` scope, and it holds while the codebase grows — the mark of a healthy
series. Rates above that are not comparable with it: the denominator changes twice, first on
2022-05-04 (jest switches to instrumenting only the files a run loads) and again on 2025-04-02
(the Node test runner with V8/`c8` instead of Istanbul). The 8.4–8.8% minima in 2021–2022 are
runs whose unit suite exited 1 with many suites failing to load: the code stays in the
denominator but is never exercised, so the rate is valid yet depressed by a visible failure,
not a silent truncation. For 2021-09-24 the instrumented set equals the project's own
`collectCoverageFrom` set exactly — 577 of 669 `app/src` files, the 92 omitted being the
project's ignore patterns (`index.ts`, `*.d.ts`, `src/cli`, `src/crash`, `src/highlighter`,
`__mocks__`) plus 19 type-only modules with no executable line — and no file appears in the
LCOV that is not in `app/src`. The level is the project's own, not a collection artifact:
`app/src/ui` holds ~55% of the instrumented lines at ~22% and `app/src/main-process` sits at
5.4%, since the unit tree contains no `ui/` tests. See Known gaps for the two denominator
changes.

## Known test failures

The full run produced 9,516 coverage-producing runs (615 with a non-zero exit) and 518 hard
errors. The complete test failure triage was conducted across all failure fingerprints using the v2 toolchain
(`label_analysis/failure_labels_project_min.csv`), and audited against the Jev automated labeler
(`label_analysis/failure_labels_jev_min.csv`). The families below document genuine developer-facing
failures, environment fixes, and Jev audit discrepancies.

The 518 hard errors are dominated by network and package-mirror failures, counted from
`logs/*.error`: 251 stop on DNS (`EAI_AGAIN`; 156 at `codeload.github.com` for git
dependencies and 97 at `release-assets.githubusercontent.com` while dugite downloads its
bundled Git), 90 fail on a corrupted `yarn@1.9.4` tarball from Verdaccio (`Z_DATA_ERROR`), and
84 fail while cloning a git submodule or git dependency. The remainder are 54 unclassified
install failures, 21 TypeScript compile errors, 9 node-gyp build errors, 3 90-minute
timeouts, 3 HTTP 404s, 2 HTTP 5xx responses and 1 network timeout.

### Genuine, developer-facing — document, do not patch

TypeScript errors in the commits' own trees, surfaced by ts-jest: the one suite that imports the
offending file fails to load, the remaining suites run, coverage is still emitted and the run
exits 1. A visible partial, not a silent one.

| commit | date | diagnostic |
|---|---|---|
| `ec38ca2f00` | 2021-05-10 | `app/src/ui/app.tsx:133:25 - error TS6133: 'ICommitContext' is declared but its value is never read` |
| `7be6d97bb9` | 2021-05-25 | `app/src/lib/stores/app-store.ts:6370:7 - error TS2345: Argument of type 'null' is not assignable to parameter of type '(state: …) => …'` |
| `39cd2c4e40` | 2023-10-31 | `app/src/ui/preferences/git.tsx:203:18 - error TS2339: Property 'onOpenItemInExternalEditor' does not exist on type '…IGitProps…'` |
| `eeb2208f61` | 2024-09-17 | `app/test/unit/git/diff-test.ts:402:16 - error TS2554: Expected 3 arguments, but got 2` (the test file itself) |

Consistent with intermediate pull-request commits, where the branch was red at that commit and
fixed before the merge. All four remain failing runs in the full history.

### Jev Discrepancy Audits (Automated vs. Ground Truth)

The automated System 1 labeler evaluated 919 fingerprints across 175 runs (`label_analysis/failure_labels_jev_min.csv`). Cross-referencing against the project's Git commit history confirmed that all major clusters flagged by Jev as `is_pipeline_issue = True` were upstream developer regressions rather than container/harness defects:

- **`temp_cleanup_enoent` (738 fingerprints, 2 runs):** Markus Olsson introduced an unhandled `rm()` retry loop in `app/test/helpers/temp.ts` (`f688751c`), throwing `ENOENT` on test fixture cleanup across hundreds of tests. Fixed by author in `e45fa12eab` 13 minutes later (`reevaluated_acceptable`).
- **`app_version_undefined` (315 fingerprints, 2 runs):** On branch `custom-ua` (`e19beea3`, `eb9adb17`), `trampoline-environment.ts` added a user-agent referencing `__APP_VERSION__`, which was missing from `app/test/globals.ts`. Fixed by author in `c487f2177f` 31 minutes later (`reevaluated_acceptable`).
- **`git_delimiter_parser_breakage` (18 fingerprints, 4 runs):** An off-by-one loop condition in `git-delimiter-parser.ts` during PR #11486 dropped single-commit log outputs, failing git operations with `Cannot read property 'sha' of undefined`. Fixed by author in `032101127f` ("math?") (`reevaluated_acceptable`).
- **`trampoline_server_refactor` (14 fingerprints, 2 runs):** Circular imports during initial TCP trampoline refactoring in PR #11510 (`2151b429`) caused `ReferenceError: trampoline_server_1 is not defined`. Resolved in follow-up branch commits (`e833f9c5`, `2f96fc87`) (`acceptable`).
- **Git checkout & dugite operational tests (8 fingerprints, 9 runs):** Sub-failures of the trampoline and custom-ua bugs, plus an Electron remote removal mock issue (`462a2084e2`) and Git 2.35.5 CVE submodule file protocol restriction resolved 46 minutes later in `11870edb89` (`acceptable` / `reevaluated_acceptable`).
- **`rebase_progress_timeout` (1 fingerprint, 1 run):** Jev marked `is_pipeline_issue = False` (stateless false negative attributing runner timeouts to test logic), while human triage archived the affected runs (`55f994e7`, `9de9c9c2`) to [`archive/rebase_progress_timeout/`](archive/rebase_progress_timeout/) for re-run (`problematic`).

No runner or Dockerfile modifications were required.

### Environment / setup

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `script/dist-info.ts(6,1): error TS6133: 'remote' is declared but its value is never read` — aborts the post-install `compile:script`, so no suite runs (`9a5a5099`, 2021-04-06) | upstream: the unused `import { remote } from 'electron'` is in that commit's tree and `script/tsconfig.json` sets `noUnusedLocals` | no coverage; 1 commit | Upstream removed it in `7621c25c20` the same day. Confirmed still a hard error in the full run. Document; do not patch. |
| node-gyp `invalid conversion from 'napi_finalize' to 'node_api_basic_finalize'` building `app/node_modules/windows-argv-parser` (`aa132c49`, 2024-10-07) | environment: `app/.npmrc` sets `runtime = electron` and `target = 32.1.2`, so node-gyp builds against Electron 32.1.2 headers (`/root/.cache/node-gyp/32.1.2`); the era's `node-addon-api` predates the `node_api_basic_finalize` signature declared there. The commit runs its exact Node version (v20.17.0), so the earlier Node-patch diagnosis does not hold | no coverage; 1 commit | Still a hard error in the full run. Requires a per-era `node-addon-api`/header decision; `use_exact_node_version` does not address it. |
| node-gyp `500 status code downloading checksum` for the Electron v36.1.0 `SHASUMS256.txt` (`7352907c`, 2025-07-14) | transient infrastructure: the matching headers tarball fetched fine (200) in the same run; only the checksum file failed | no coverage; 1 commit | Fixed: the full run completes with both suites at exit code 0, and `npm_config_fetch_retries=5` retries a single mirror hiccup. |
| node-gyp `404 … artifacts.electronjs.org/headers/dist/v22.23.2/node-v22.23.2-headers.tar.gz` building root `node_modules/printenvz` (`975bd31a`, 2025-11-26) | environment, ours: `npm_config_disturl` exported the **Electron** headers path for the whole run, so a root **Node** addon requested a Node version on a path that only serves Electron releases. The variable cannot be split — node-gyp reads it from the environment in preference to `app/.npmrc`, and the app's Electron addons (the vast majority of native builds) need the Electron value | was no coverage; 1 commit | The header pre-seed fix is verified separately, but the full-run attempt aborted earlier at `getaddrinfo EAI_AGAIN codeload.github.com` while yarn fetched the `desktop/desktop-trampoline` git dependency. Remains uncollected; re-run with the DNS fix. |

## Environment / setup fixes

- **Electron runtime libraries** in the Dockerfile (`libnss3`, `libnspr4`, `libgtk-3-0`,
  `libgbm1`, `libasound2`, `libsecret-1-dev`, X11 client libraries, …) because the unit
  suite runs the Electron binary as its Node host (`ELECTRON_RUN_AS_NODE=1`).
- **Xvfb** on `:99` with `DISPLAY` exported, for tests that touch the display.
- **Electron / Node header mirroring.** `ELECTRON_MIRROR` (the Electron binary download) is
  pointed at WayPack, and `resolve_and_pin` is applied to `electronjs.org` and
  `artifacts.electronjs.org`. Both 2026-10-14 attempts failed inside the `postinstall` hook,
  where `script/post-install.ts` runs the vendored Yarn with `--force` in `app/` and node-gyp
  rebuilds the native module `detect-arm64-translation`; node-gyp fetched Electron v11.1.1
  headers from `atom.io` and aborted with `There was a fatal problem while
  downloading/extracting the tarball`. Mirroring the payloads removed the failure.
  `npm_config_disturl` therefore carries the **Electron** headers path for the whole run,
  because the app's Electron addons are the overwhelming majority of native builds and
  node-gyp reads that variable in preference to the `runtime` / `target` / `disturl` that
  `app/.npmrc` already declares (rewriting that file has no effect). A root-level *Node*
  addon cannot be served by the same value — see the pre-seed bullet below.
- **node-gyp header pre-seed.** Before the install, the script fetches the running Node
  version's headers through WayPack and extracts them into node-gyp's cache
  (`${XDG_CACHE_HOME:-~/.cache}/node-gyp/<version>/`, plus the legacy `~/.node-gyp/<version>/`)
  with the `installVersion` marker its node-gyp expects. node-gyp then finds them locally and
  never requests a URL, so rare root-level Node addons (e.g. `vendor/printenvz`) build despite
  the Electron `disturl`; Electron builds key their cache on the Electron version and are
  unaffected. Verified on `975bd31a`, which previously could not install at all.
- **`npm_config_fetch_retries=5`**, because one run died when WayPack returned `500` for an
  Electron `SHASUMS256.txt` immediately after serving the matching headers tarball.
- **Zero-test guard wired.** `assert_suite_ran` is now called for `unit` and `script` in both
  runner eras — the shared helper gained a `node` case for the `ℹ tests <n>` summary — and each
  suite's output is teed with `2>&1` into a log file for it to read (jest writes its summary to
  stderr). A run that loads no tests now aborts instead of emitting an all-zero lcov. Verified
  in the container for both runners: `unit ran tests (Test Suites: 1 failed, 115 passed, …)`
  and `unit ran tests (ℹ tests 830)`.
- **Exact Node versions** — `config.json` sets `use_exact_node_version: true` for desktop, so
  each commit runs the version its `.nvmrc` names (e.g. `v20.17.0`) rather than the newest
  patch of that major at image-build time. Without it, headers from a 2026-era patch broke the
  era's `node-addon-api` while compiling `windows-argv-parser`.
- **`NODE_OPTIONS=--max-old-space-size=4096`** for the unit run, and **`rm -f .gitmodules`**
  before `yarn install`: the post-install hook runs
  `git submodule update --recursive --init` for `gemoji`,
  `app/static/common/choosealicense.com` and `app/static/common/gitignore`; all three still
  check out.
- **Package-manager assertion:** the script aborts unless the resolved package manager is
  yarn.
- **Coverage-instrumentation pin (2022-05-10 → 2023-12-11 window).** `tsconfig.json` raised
  `target` from `es2017` to `ES2022` on 2022-05-10, so TypeScript began emitting native
  class fields into the JavaScript that coverage instrumentation parses, while the parser on
  that path (`babel-plugin-istanbul@6` → `istanbul-lib-instrument@4.0.3` →
  `@babel/core@7.12.9` → `@babel/parser@7.12.7`) predates class-field parsing (Babel 7.14).
  Those commits declare no `@babel/*` dependency at all, so nothing forced a modern parser.
  The script detects the combination (`@babel/parser` < 7.14 **and** `target` ≥ `ES2022`),
  adds a yarn `resolutions` pin to `@babel/core`/`@babel/parser` **7.17.10** and re-runs
  `yarn install --ignore-scripts`. 7.17.10 is the newest version present in WayPack's
  commit-dated view at the window's opening commit (2022-05-10), so the pin resolves
  everywhere in the window, stays inside the commit-dated registry — no registry switching —
  and is one uniform version rather than a moving range. The gate leaves every other era
  untouched, including 2021 (same old parser, but `es2017` downlevels class fields, so
  nothing breaks there) and 2024+ (parser already ≥ 7.14).
- **dugite's bundled git (same window).** `dugite` downloads a prebuilt
  `dugite-native-*-ubuntu` git (2.39.3 at these commits) that requires glibc ≥ 2.32, while
  this image is Debian bullseye (2.31). The payload cannot start, so every git-backed unit
  test failed with `GLIBC_2.32 not found` — masked until the Babel fix let the suites load.
  `app/test/setup-test-framework.ts` deletes `LOCAL_GIT_DIRECTORY`, so dugite's embedded git
  cannot be redirected by environment variable. The Dockerfile therefore pulls the libc from
  bookworm and leaves the rest of the image on bullseye, exactly as
  [`projects/sequelize/Dockerfile`](../sequelize/Dockerfile) does for the era's DB2
  clidriver:
  `apt-get install -y --no-install-recommends -t bookworm libc6 libc6-dev libc-bin
  libstdc++6 libgcc-s1` (glibc becomes 2.36); glibc is backward-compatible, so nothing else
  changes and dugite's own git runs natively. Verified by `ldd --version` at build time and
  by the git-fixture suites passing.
- **git-lfs** in the image: the LFS unit suites shell out to `git lfs`.
- **Post-completion non-zero exits (3 runs archived).** Some `podman run` invocations return
  non-zero *after* `execute.sh` has printed `Coverage run completed` and written a complete
  coverage directory, so `docker_run.py` classified a valid run as a hard error and left a
  `.error` marker beside the output. The harness now records the actual exit code in the marker
  and removes a stale `.error` on a successful re-run. Three affected runs (`731993d200`,
  `95d343e827`, `b1b38b6604`) were archived to
  [`archive/post_completion_nonzero_exit/`](archive/post_completion_nonzero_exit/) and were
  re-run successfully; the new runs reproduce the original line coverage (only execution
  counts differ).
- **Unmocked promisor remote network timeout (10 runs archived).** The test
  `it('returns promisor remote')` (added 2023-07-14 in `17367e087f`) executes an unmocked
  `git fetch --filter=blob:none` against `https://github.com/desktop/not-found.git`, expecting
  GitHub to return 404 in milliseconds so Git records the partial clone filter in config.
  While the test passed in >99.7% of commits, transient outbound network latency occasionally
  exceeded Jest's 10,000 ms timeout. Ten affected runs (8 under Jest 28+ timeout formatting, 2 under
  Jest 27) were archived to
  [`archive/promisor_remote_timeout/`](archive/promisor_remote_timeout/) for re-run.
- **Long rebase progress test timeout (2 runs archived).** In `app/test/unit/git/rebase/progress-test.ts`,
  the 10-commit rebase sequence with conflict resolution runs dozens of Git subprocesses and
  typically requires >60s per file. In two runs (`55f994e7` and `9de9c9c2`), an async step
  intermittently exceeded Jest's 10,000 ms per-test timeout under transient system load. Both runs were
  archived to [`archive/rebase_progress_timeout/`](archive/rebase_progress_timeout/) for re-run.

## Known gaps

- **`integration` suite not collected** — an end-to-end launch test of the packaged
  application; see Coverage collection for the evidence. It exists only from 2016-08-03 to
  2022-01-20 and would require a full webpack build per commit while contributing no
  source-level lines.
- **Coverage scope changes meaning on 2022-05-04.** Until that date the project's own
  `collectCoverageFrom` fixes the denominator to `app/src`. Afterwards no scope is
  configured and jest instruments only the files a run happens to load. In magnitude the two
  are close (22,692–26,256 lines before, 30,112–33,614 after, because the loaded set also
  picks up `app/test/helpers`), so the series is usable across the boundary — but the
  denominator is not formally the same quantity, and one commit breaks the pattern:
  `f93d46ca` (2024-11-13) reports 17,754 lines at 39.9% where its neighbour `879b2c63`
  (2024-03-20) reports 33,614 at 31.7%, for the same 1,032 passing tests. That outlier is
  unexplained (it also loads far fewer `app/src/ui` files) and is the remaining
  comparability question for the post-2022-05 era; the by-year table is in Results.
- **The 2025-04-02 era is measured differently.** From the `jestless` change the
  suites run under Node's test runner, so coverage comes from V8/`c8` instead of jest's
  Istanbul: the numbers are not on the same scale (the 2025 runs in the full history range
  39.6–72.1%, median 54.4%), and `c8` additionally counts `app/test/helpers` (and, in the runs
  made while the `eslint` suite was still collected, a `vendor/` file). Cross-era comparison
  across 2025-04 needs a deliberate decision.
- **The measurement surface is what the project defines.** `app/src/cli`, `app/src/crash`,
  `app/src/highlighter` and `index.ts` files are excluded by the project's own config, and
  the 2022-05-04 removal of `collectCoverageFrom` cannot be undone without diverging from
  the project's intent — any scope pinned for later commits is a documented deviation.
