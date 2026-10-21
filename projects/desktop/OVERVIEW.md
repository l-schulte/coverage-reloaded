# desktop

**Repository:** https://github.com/desktop/desktop
**Status:** active

## Test infrastructure

- **Package manager:** yarn (`yarn@1.9`, `yarn.lock`) throughout the study window,
  single package without workspaces; `engines` requires `node >= 10` and
  `yarn >= 1.9`. The project vendors its own Yarn (`vendor/yarn-<version>.js`) and
  the `postinstall` hook invokes it, so container runs report Yarn 1.21.1 even
  though the harness installs `yarn@1.9` (see [`config.json`](../../config.json) →
  `desktop`).
- **Node strategy:** `use_exact_node_version: true` — each commit runs the Node
  version named by its `.nvmrc`: 12/14 (2019–2021), 16 (2022–2023), 18
  (2023–2024), 20 (2024–2025), 22 (2025). No other override in
  [`config.json`](../../config.json).
- **Runners:** `jest` (23 → 26 → 29) with `electron` as the unit-test host
  (`ELECTRON_RUN_AS_NODE=1`) until 2025; the Node test runner (`node --test`
  driven by `tsx`) from 2025-03-26; `mocha` + `ts-node` only in the pre-window
  era.
- **Eras:**
  - before 2019-04-12: `test:unit` = jest under Electron; `test:script` and
    `test:integration` = `mocha` + `ts-node` (pre-window).
  - 2019-04-12: `test:script` and `test:integration` move to jest
    (`script/jest.config.js`, `app/jest.integration.config.js`).
  - 2021-02-11: jest 23 → 26, shipped with the Electron 11 upgrade (PR #11142).
  - 2021-07-04: `test:eslint` = `jest eslint-rules/tests/*.test.js` added; absent
    before.
  - 2022-01-20: `test:integration` and `spectron` removed upstream
    (`1d91a0b9ed`).
  - 2022-05-04: `test:unit:cov`, `test:script:cov`, `collectCoverageFrom` and
    `.codecov.yml` removed (`2db2edbfa6` "Bye bye coverage", `4686d0006a`);
    `test` becomes `yarn test:unit --runInBand && yarn test:script`.
  - 2023-11-30 to 2023-12-11: the unit config is reworked for dexie/uuid-dependent
    tests and switches to `testEnvironment: 'jsdom'`; jest 26 → 29 and TypeScript 5
    land with the `ts5` merge (PR #17315, 2023-12-11).
  - 2025-04-02: jest removed (PR #20261 "jestless", branch commits from
    2025-03-26): `test:unit` = `node script/test.mjs`, `test:script` =
    `node script/test.mjs script`, `test:eslint` = `node script/test.mjs
    eslint-rules`.
  - 2026-03-19: a Playwright end-to-end suite (`test:e2e`) is added — outside the
    window.

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

- **Suites collected:** `unit` (jest on `app/test/unit/**/*-test.ts{,x}` until
  2025-04, then the Node test runner on the same tree) and `script`
  (`jest --config ./script/jest.config.js`, then `node script/test.mjs script`).
  The unit tree grows from 88 test files (2019-05) to 115 (2025-12) — 109 at the
  2021-06-04 commit, 110 at 2021-09-03, 114 at 2024-12-23 — and every file is
  collected: the suites executed equal the test files present on disk at each
  commit.
- **Suite excluded — `integration` (2016-08-03 to 2022-01-20):** it is an
  end-to-end launch test in disguise, not an integration suite.
  `app/test/integration/launch-test.ts` — the only file that directory ever
  contained — spawns the webpack-built application from `out/` as a separate
  Electron process through `spectron` and asserts only OS window state
  (`getWindowCount`, `isVisible`, `isMinimized`, `getBounds`). Three consequences
  follow: (1) it cannot run without `yarn build:dev|prod` first — CI invokes it
  only after the production build, and `script/build.ts` even runs `yarn install`
  inside `out/`; (2) the application code executes in the child process, so jest's
  Istanbul counters in the parent process see no project file —
  `app/jest.integration.config.js` defines no `collectCoverageFrom`, there is no
  `test:integration:cov`, and the project's codecov upload reads only
  `app/coverage/coverage-final.json` from the unit run; (3) forcing `--coverage`
  would therefore emit an empty LCOV and fail the run. Upstream classified the
  suite the same way: it was deleted on 2022-01-20 together with spectron, and a
  genuine Playwright end-to-end suite (`test:e2e`) was introduced on 2026-03-19.
- **Suite excluded — `eslint` (2021-07-04 to present):** `test:eslint` exists from
  2021-07-04 onwards, but it is not a coverage suite: it runs the project's
  *custom lint rules* through ESLint's `RuleTester`, asserting diagnostics on
  inline code strings (`code: 'const b = Math.random();'`, with
  `filename: 'app/src/ui/component.tsx'` strings chosen only to select a rule's
  file mode). No product code executes, and the resulting lcov covers just
  `eslint-rules/**` — four rule implementations, ~134 lines, in the current runs.
  It is also outside the project's own coverage intent: there is no
  `test:eslint:cov`, the root `test` script never invokes it (`yarn test:unit:cov`
  + `yarn test:script:cov`, and CI runs `test`/`test:unit`/`test:script` only),
  and the codecov upload reads `app/coverage/coverage-final.json` from the unit
  run. Under the Node test runner it additionally failed systematically, because
  `node script/test.mjs eslint-rules` discovers zero files (the helper's filter
  matches `-test.<ext>`, these are `*.test.js`) and `node --test` then swept the
  whole repository, running unrelated trees. Collecting it therefore contributed
  no signal for product code, only a dev-tooling lcov and a failure mode; it was
  dropped on 2026-10-16. `unit` and `script` are the only collected suites,
  matching the project's own coverage intent.
- **Focus markers (`.only`):** the guard is runner-aware. Desktop's collected
  suites run under jest (jest 23/26/29 on `app/test/unit` and `script`) until
  2025-04 and under Node's test runner thereafter, and both honour `.only` per
  file, so the helper is called as `na_if_focus_marker --runner jest --runner
  node`. A marked commit is measured with a recorded deficit instead of being
  dropped: the whole suite runs, and the marked file(s) are listed in a
  `focus_marker.txt` sidecar inside the commit's own output directory
  (`<timestamp>_<revision>/focus_marker.txt`, alongside its lcov files). This
  matters because a single `it.only` in
  `app/test/unit/desktop-file-transport-test.ts` persisted upstream from
  2022-03-14 to 2025-04-02 — 5,827 of 10,034 commits (58.1%) — which a run-global
  policy would have removed from the exposure variable entirely.
- **Coverage tool / config:** jest's Istanbul instrumentation until 2025-04, then
  V8 coverage through `c8` (the harness wraps `node script/test.mjs` with
  `c8 --reporter=lcov`, sourced from Verdaccio). `app/jest.unit.config.js` sets
  `collectCoverageFrom: ['src/**/*.{js,jsx,ts,tsx}']` with `!**/node_modules/**`,
  `!**/vendor/**`, `!**/*.d.*`, `!src/cli/**/*`, `!src/crash/**/*`,
  `!src/highlighter/**/*` and `!**/index.ts` until 2022-05-04. From 2022-05-04 the
  project configures no coverage scope, so `--coverage` falls back to jest's
  default, which instruments only the files loaded by the run — see Known gaps.
- **No coverage gate:** no `--check-coverage`, no `coverageThreshold` in any jest
  config, and the project's `.codecov.yml` (present until 2022-05-04) set
  `status: off`.
- **LCOV production:** the run forces `--coverage --coverageReporters=lcov`,
  overriding the project configs that emit only `text-summary`/`json`/`html`/
  `cobertura`; `find-and-move-lcov.sh` moves each suite's `lcov.info` out as
  `unit.lcov` and `script.lcov`.

## Checklist

- [x] 100 done (100-commit sample; earlier runs archived in
  [`archive/run1/`](archive/run1/) and [`archive/run2/`](archive/run2/))
- [x] failed tests doublechecked
- [x] complete run (10,034 commits processed; 0 pending)
- [x] complete test failure check (1,765 fingerprints and 615 failing runs labeled; 0 problematic / 0 unclear)
- [x] complete JEV test failure check (789 flagged rows audited in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

A 100-commit sample spanning 2021-01 to 2025-11 was reviewed: its hard errors
were analysed one by one and its non-zero-exit runs grouped and classified, which
is what the first two items record. The full-history run completed with all
10,034 commits processed. The runs archived under
[`archive/post_completion_nonzero_exit/`](archive/post_completion_nonzero_exit/),
[`archive/promisor_remote_timeout/`](archive/promisor_remote_timeout/) and
[`archive/rebase_progress_timeout/`](archive/rebase_progress_timeout/) were moved
out for clean re-runs after their fixes; the run counts are in each archive
README.

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 20:58).

| Metric | Value |
|---|---|
| Commits processed | 10,034 |
| Without test failures | 8,901 |
| With test failures | 615 |
| Not applicable | 0 |
| Hard errors | 518 |
| Coverage produced | 94.8% |

All commits with a committer date in the study window (2021-01-01 → 2025-12-31)
are processed. The author dates recorded in `commits.csv`, which anchor the
dependency snapshot for each run, span 2019-04-12 → 2025-12-31 because 41 commits
were authored before 2021 and committed inside the window. Full statistics and
plots: [`stats_output/`](stats_output/).

Coverage by year across the 9,516 coverage-producing commits, using each commit's
`unit` suite rate from `stats_output/commits_detail.csv`:

| Year | runs | rate min | median | rate max |
|---|---|---|---|---|
| 2019 | 20 | 30.8% | 31.4% | 31.5% |
| 2020 | 21 | 23.4% | 31.4% | 32.0% |
| 2021 | 2,628 | 8.8% | 31.3% | 32.1% |
| 2022 | 2,067 | 8.4% | 30.9% | 44.8% |
| 2023 | 2,043 | 26.8% | 32.3% | 54.1% |
| 2024 | 1,686 | 30.6% | 39.7% | 59.1% |
| 2025 | 1,051 | 39.6% | 54.5% | 72.2% |
| **all** | **9,516** | **8.4%** | **31.8%** | **72.2%** |

The 31–32% median band through 2023 is the project's own coverage under its own
`collectCoverageFrom` scope, and it holds while the codebase grows — the mark of
a healthy series. Rates above the band are not comparable with it: the
denominator changes twice, first on 2022-05-04 (jest switches to instrumenting
only the files a run loads) and again on 2025-04-02 (the Node test runner with
V8/`c8` instead of Istanbul). The 8.4–8.8% minima in 2021–2022 are runs whose
unit suite exited 1 with many suites failing to load: the code stays in the
denominator but is never exercised, so the rate is valid yet depressed by a
visible failure, not a silent truncation. For 2021-09-24 the instrumented set
equals the project's own `collectCoverageFrom` set exactly — 577 of 669 `app/src`
files, the 92 omitted being the project's ignore patterns (`index.ts`, `*.d.ts`,
`src/cli`, `src/crash`, `src/highlighter`, `__mocks__`) plus 19 type-only modules
with no executable line — and no file appears in the LCOV that is not in
`app/src`. The level is the project's own, not a collection artifact:
`app/src/ui` holds ~55% of the instrumented lines at ~22% and
`app/src/main-process` sits at 5.4%, since the unit tree contains no `ui/` tests.
See Known gaps for the two denominator changes.

## Failure triage

Source: `python check_failures_v2.py desktop --stats` (window `min`, run
2026-10-21) and `stats_output/report.txt` (generated 2026-10-21 20:58). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and
[`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 615 |
| Failing runs (label DB) | 615 |
| Fingerprints (min / max) | 1,765 / 2,154 |
| Labeled fingerprints | 1,765 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 584 |
| reevaluated_acceptable | 1,181 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 14 / 1,751 |
| Labeled detections (min) | 3,563/3,563 (100.0%) |
| Labeled runs (min) | 615/615 (100.0%) |
| Jev mode | dedup-keyword |
| Jev pipeline issues | 789 flagged rows (923 rows; covered fingerprints not recorded) |
| Jev audit | current |

**State:** complete. The label DB and `stats_output/report.txt` agree on 615 failing
runs, and every fingerprint and detection carries a label: 584 `acceptable`,
1,181 `reevaluated_acceptable`, zero `problematic` and zero `unclear`. The eleven
former `unclear` fingerprints were resolved in the 2026-10-21 family assessment;
all eleven are `reevaluated_acceptable` (upstream branch mistakes), and the nine
rules that carried `unclear` were updated to match.


The rebuild of 2026-10-21 changed one project file,
[`failure_patterns.json`](label_analysis/failure_patterns.json): the jest-era
stems `app_unit` and `script_script` now carry the general `●` pattern in addition
to the error-line pattern. The `unit` and `script` rules — which apply to the
Node-test-runner era — keep only error-prefixed lines, and that rule matches no
jest assertion block, so before the fix 532 of the 615 failing runs produced no
detected failure at all. The rebuild restores 1,761 of the 1,766 fingerprints
that the pre-fix detection produced, and every failing run now yields detections.

Two Jev artifacts exist.
[`failure_labels_jev_min_dedup.csv`](label_analysis/failure_labels_jev_min_dedup.csv)
holds the deduplication-mode labels (923 rows, `labeled_at`
2026-10-21T14:25–14:27 plus four rows at 21:24): one row per `(suite, keyword)`
family, 789 flagged rows; 922 of its 923 representatives exist in the rebuilt set.
The file predates the `family_fingerprints` column, so it records no covered
fingerprint list. [`failure_labels_jev_min.csv`](label_analysis/failure_labels_jev_min.csv)
holds fingerprint-mode labels (855 rows, `labeled_at` 2026-10-21T20:48–20:50) that
cover only 759 of the 1,765 rebuilt fingerprints and therefore lag the rebuild.
Row counts across the two files are not comparable. The audit of the 789 flagged
rows is recorded in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md):
eight commit-era upstream defects and no pipeline defect.

## Environment / setup fixes

- **Electron runtime libraries** in the Dockerfile (`libnss3`, `libnspr4`,
  `libgtk-3-0`, `libgbm1`, `libasound2`, `libsecret-1-dev`, X11 client libraries,
  …) because the unit suite runs the Electron binary as its Node host
  (`ELECTRON_RUN_AS_NODE=1`).
- **Xvfb** on `:99` with `DISPLAY` exported, for tests that touch the display.
- **Electron / Node header mirroring.** `ELECTRON_MIRROR` (the Electron binary
  download) is pointed at WayPack, and `resolve_and_pin` is applied to
  `electronjs.org` and `artifacts.electronjs.org`. Before mirroring, both
  2026-10-14 attempts failed inside the `postinstall` hook, where
  `script/post-install.ts` runs the vendored Yarn with `--force` in `app/` and
  node-gyp rebuilt `detect-arm64-translation` from `atom.io` headers. Node-gyp
  reads `npm_config_disturl` in preference to the `runtime` / `target` / `disturl`
  that `app/.npmrc` declares (rewriting that file has no effect), so the variable
  carries the **Electron** headers path for the whole run. A root-level *Node*
  addon cannot be served by the same value — see the pre-seed bullet below.
- **node-gyp header pre-seed.** Before the install, the script fetches the running
  Node version's headers through WayPack and extracts them into node-gyp's cache
  (`${XDG_CACHE_HOME:-~/.cache}/node-gyp/<version>/`, plus the legacy
  `~/.node-gyp/<version>/`) with the `installVersion` marker its node-gyp expects.
  node-gyp then finds them locally and never requests a URL, so rare root-level
  Node addons (e.g. `vendor/printenvz`) build despite the Electron `disturl`;
  Electron builds key their cache on the Electron version and are unaffected.
  Verified on `975bd31a`, which previously could not install at all.
- **`npm_config_fetch_retries=5`**, because one run died when WayPack returned
  `500` for an Electron `SHASUMS256.txt` immediately after serving the matching
  headers tarball; the affected commit (`7352907c`) now completes with both suites
  at exit code 0.
- **Zero-test guard wired.** `assert_suite_ran` is called for `unit` and `script`
  in both runner eras — the shared helper gained a `node` case for the
  `ℹ tests <n>` summary — and each suite's output is teed into a log file for it
  to read (jest writes its summary to stderr). A run that loads no tests now
  aborts instead of emitting an all-zero lcov.
- **Exact Node versions** — `config.json` sets `use_exact_node_version: true` for
  desktop, so each commit runs the version its `.nvmrc` names (e.g. `v20.17.0`)
  rather than the newest patch of that major at image-build time. Without it,
  headers from a 2026-era patch broke the era's `node-addon-api` while compiling
  `windows-argv-parser`.
- **`NODE_OPTIONS=--max-old-space-size=4096`** for the unit run, and
  **`rm -f .gitmodules`** before `yarn install`: the post-install hook runs
  `git submodule update --recursive --init` for `gemoji`,
  `app/static/common/choosealicense.com` and `app/static/common/gitignore`; all
  three still check out.
- **Package-manager assertion:** the script aborts unless the resolved package
  manager is yarn.
- **Coverage-instrumentation pin (2022-05-10 → 2023-12-11 window).**
  `tsconfig.json` raised `target` from `es2017` to `ES2022` on 2022-05-10, so
  TypeScript began emitting native class fields into the JavaScript that coverage
  instrumentation parses, while the parser on that path (`babel-plugin-istanbul@6`
  → `istanbul-lib-instrument@4.0.3` → `@babel/core@7.12.9` →
  `@babel/parser@7.12.7`) predates class-field parsing (Babel 7.14). Those commits
  declare no `@babel/*` dependency at all, so nothing forced a modern parser. The
  script detects the combination (`@babel/parser` < 7.14 **and** `target` ≥
  `ES2022`), adds a yarn `resolutions` pin to `@babel/core`/`@babel/parser`
  **7.17.10** and re-runs `yarn install --ignore-scripts`. 7.17.10 is the newest
  version present in WayPack's commit-dated view at the window's opening commit
  (2022-05-10), so the pin resolves everywhere in the window without leaving that
  view, and it is one uniform version rather than a moving range. The gate leaves
  every other era untouched, including 2021 (same old parser, but `es2017`
  downlevels class fields) and 2024+ (parser already ≥ 7.14).
- **dugite's bundled git (same window).** `dugite` downloads a prebuilt
  `dugite-native-*-ubuntu` git (2.39.3 at these commits) that requires
  glibc ≥ 2.32, while this image is Debian bullseye (2.31). The payload cannot
  start, so every git-backed unit test failed with `GLIBC_2.32 not found` —
  masked until the Babel fix let the suites load.
  `app/test/setup-test-framework.ts` deletes `LOCAL_GIT_DIRECTORY`, so dugite's
  embedded git cannot be redirected by environment variable. The Dockerfile
  therefore pulls libc from bookworm and leaves the rest of the image on bullseye,
  exactly as [`projects/sequelize/Dockerfile`](../sequelize/Dockerfile) does for
  the era's DB2 clidriver: `apt-get install -y --no-install-recommends -t bookworm
  libc6 libc6-dev libc-bin libstdc++6 libgcc-s1` (glibc becomes 2.36); glibc is
  backward-compatible, so nothing else changes and dugite's own git runs natively.
  Verified by `ldd --version` at build time and by the git-fixture suites passing.
- **git-lfs** in the image: the LFS unit suites shell out to `git lfs`.
- **Post-completion non-zero exits (3 runs).** Some `podman run` invocations
  return non-zero *after* `execute.sh` has printed `Coverage run completed` and
  written a complete coverage directory, so `docker_run.py` classified a valid run
  as a hard error and left a `.error` marker beside the output. The harness now
  records the actual exit code in the marker and removes a stale `.error` on a
  successful re-run. The affected runs were archived to
  [`archive/post_completion_nonzero_exit/`](archive/post_completion_nonzero_exit/)
  and re-run; the new runs reproduce the original line coverage (only execution
  counts differ).
- **Unmocked promisor remote network timeout (2 runs).** The test `it('returns
  promisor remote')` (added 2023-07-14 in `17367e087f`) executes an unmocked
  `git fetch --filter=blob:none` against `https://github.com/desktop/not-found.git`,
  expecting GitHub to return 404 in milliseconds so Git records the partial clone
  filter in config. Transient outbound network latency occasionally exceeded
  Jest's 10,000 ms timeout. The affected runs were archived to
  [`archive/promisor_remote_timeout/`](archive/promisor_remote_timeout/) for
  re-run.
- **Long rebase progress test timeout (2 runs).** In
  `app/test/unit/git/rebase/progress-test.ts`, the 10-commit rebase sequence with
  conflict resolution runs dozens of Git subprocesses and typically requires >60 s
  per file. In two runs an async step intermittently exceeded Jest's 10,000 ms
  per-test timeout under transient system load. Both runs were archived to
  [`archive/rebase_progress_timeout/`](archive/rebase_progress_timeout/) for
  re-run.

## Known gaps

- **`integration` suite not collected** — an end-to-end launch test of the
  packaged application; see Coverage collection for the evidence. It exists only
  from 2016-08-03 to 2022-01-20 and would require a full webpack build per commit
  while contributing no source-level lines.
- **`eslint-rules` remains in the focus-marker pathspec** although the `eslint`
  suite is no longer collected. A committed `.only` under `eslint-rules/` would
  therefore still write a `focus_marker.txt` deficit for a tree that is not part
  of the measurement.
- **518 commits produce no coverage** (`report.txt`). They are dominated by
  network and package-mirror failures: DNS resolution (`EAI_AGAIN`, mostly
  `codeload.github.com` for git dependencies and
  `release-assets.githubusercontent.com` while dugite downloads its bundled Git),
  a corrupted `yarn@1.9.4` tarball served by Verdaccio (`Z_DATA_ERROR`), and
  failures while cloning a git submodule or git dependency. The remainder are
  install failures, TypeScript compile errors, node-gyp build errors, HTTP 4xx/5xx
  responses and run timeouts.
- **Two commits remain hard errors for upstream reasons, one for an environment
  reason.**
  `9a5a5099` (2021-04-06) aborts the post-install `compile:script` because that
  commit's tree imports `remote` from `electron` unused
  (`script/dist-info.ts(6,1): error TS6133`), and `script/tsconfig.json` sets
  `noUnusedLocals`; upstream removed it in `7621c25c20` the same day.
  `aa132c49` (2024-10-07) fails node-gyp building `windows-argv-parser` against
  Electron 32.1.2 headers with
  `invalid conversion from 'napi_finalize' to 'node_api_basic_finalize'`, because
  the era's `node-addon-api` predates that signature; the commit already runs its
  exact Node version, so this needs a per-era header decision.
  `975bd31a` (2025-11-26) builds the root *Node* addon `printenvz` against the
  Electron headers path set by `npm_config_disturl` and receives a 404. The
  header pre-seed addresses it, but the full-run attempt aborted earlier at
  `getaddrinfo EAI_AGAIN codeload.github.com` while yarn fetched the
  `desktop/desktop-trampoline` git dependency, so the commit remains uncollected;
  re-run it once DNS is available.
- **Coverage scope changes meaning on 2022-05-04.** Until that date the project's
  own `collectCoverageFrom` fixes the denominator to `app/src`. Afterwards no
  scope is configured and jest instruments only the files a run happens to load.
  In magnitude the two are close (22,692–26,256 lines before, 30,112–33,614 after,
  because the loaded set also picks up `app/test/helpers`), so the series is
  usable across the boundary — but the denominator is not formally the same
  quantity, and one commit breaks the pattern: `f93d46ca` (2024-11-13) reports
  17,754 lines at 39.9% where its neighbour `879b2c63` (2024-03-20) reports 33,614
  at 31.7%, for the same 1,032 passing tests. That outlier is unexplained (it also
  loads far fewer `app/src/ui` files) and is the remaining comparability question
  for the post-2022-05 era.
- **The 2025-04-02 era is measured differently.** From the `jestless` change the
  suites run under Node's test runner, so coverage comes from V8/`c8` instead of
  jest's Istanbul: the numbers are not on the same scale (the 2025 runs range
  39.6–72.2%, median 54.5%), and `c8` additionally counts `app/test/helpers` (and,
  in the runs made while the `eslint` suite was still collected, a `vendor/`
  file). Cross-era comparison across 2025-04 needs a deliberate decision.
- **The measurement surface is what the project defines.** `app/src/cli`,
  `app/src/crash`, `app/src/highlighter` and `index.ts` files are excluded by the
  project's own config, and the 2022-05-04 removal of `collectCoverageFrom` cannot
  be undone without diverging from the project's intent — any scope pinned for
  later commits is a documented deviation.
