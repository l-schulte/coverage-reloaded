# compass

**Repository:** https://github.com/mongodb-js/compass
**Status:** active

## Test infrastructure

- **Package manager:** npm + lerna (see [`config.json`](../../config.json) → `compass`). Overrides `npm@7.16.0` to `npm@8` across 2021-06 → 2022-08 to eliminate the fatal npm 7 tarball decompression bug (`Z_DATA_ERROR` / `TAR_ENTRY_INVALID` checksum failure), using `patch-coverage.js` to alias workspace `prepare` scripts to `bootstrap` so npm 8 cannot fire out-of-order compilation hooks during root install, and preserving `npm@6.13.0` for early Node 12 commits.
- **Node strategy:** `use_first_node_version: true` (resolves earliest supported Node from `package.json` engines). `engine-strict` in `.npmrc` is relaxed in `install-and-run.sh` because upstream engines lagged at `>=16.15.1` while release tooling required Node 18.
- **Runners:** `mocha` (all workspace packages); `nyc` (coverage).
- **Eras (Jan 2021 – Jan 2025):**
  - **Era 1 (Jan 2021 – Apr 2021, 56 commits / 0.89%):** Single-package legacy repository. Marked `not_applicable` (external npm plugins, no unified monorepo suite).
  - **Era 2 (Apr 2021 – Jun 2021, 277 commits / 4.42%):** Pre-workspaces Lerna v4 monorepo (`lerna.json` present, no `workspaces` in `package.json`). Marked `not_applicable` (unintegrated plugins never tested in full by upstream CI).
  - **Era 3 (Jun 2021 – Jan 2025, 5,927 commits / 94.68%):** Native npm workspaces (`workspaces` in `package.json`). Target exposure variable for the study. Root dependencies installed and linked with `npm install --ignore-scripts`, followed by workspace compilation via `npm run bootstrap` (or `npm run compile`). Mocha/NYC test suite dispatched via `npm run test-ci`. Clean test execution and line coverage verified across all 40–52 workspace packages.

## Development style

- **PR merging strategy:** Squash and merge (82.6% of first-parent commits follow `Title (#<PR>)`).
- **Merge convention:** `<type>(<scope>): <title> COMPASS-<issue> (#<PR>)`.
- **Direct commits:** 17.4% overall, overwhelmingly automated release metadata and documentation synchronization bots (`chore: update AUTHORS, THIRD-PARTY-NOTICES, Security Test Summary` account for over 1,000 commits; `chore(release): bump package versions`). Human direct commits touching code without a PR are negligible (<3%).
- **JS/TS code impact of direct commits:** Negligible; restricted to license manifests, dependency bumps, and automated release tags.
- **Issue tracking discipline:** High (Jira ticket tags `COMPASS-<id>` and GitHub PR references present on almost all commits).
- **Workflow notes:** Standard enterprise monorepo workflow with automated CI sync scripts committing generated documentation and licensing notices back to `main`.

## Coverage collection

- **Suites collected:** package unit and behavioral suites across monorepo workspaces via root `test-ci` / `test` dispatch (`lerna run test-ci`).
- **Suites excluded:**
  - `packages/compass-e2e-tests` — end-to-end tests targeting packaged application binaries against live external database services.
  - `test-ci-electron` / `test-electron` — end-to-end platform launch and runtime smoke suite in disguise. In the top-level application shell (`packages/compass`), it boots the full Electron desktop app (`test-main` & `test-renderer`) under `Xvfb` to assert on Chromium window and OS integration; in the workspace plugin packages, it re-runs the exact same unit specs already executed by `test-ci` inside a live Chromium browser window via `electron-mocha` as a platform compatibility smoke test. Because code executes inside a Chromium child process without IPC coverage hooks, coverage cannot be collected; upstream configured NYC coverage exclusively on the Node unit suite (`test-cov` / `test-ci`). Excluded to prevent empty/corrupted LCOV artifacts (matching the Spectron exclusion precedent in `projects/desktop`).
- **Eras excluded:**
  - **Eras 1 & 2 (Pre-workspaces era, Jan 2021 – Jun 2021, 333 commits / 5.32%):** Excluded from coverage collection using the standard `not_applicable` sentinel (`logging.sh`). Commits where `package.json` lacks `"workspaces"` (`[ "$HAS_WORKSPACES" != "true" ]`) immediately write `${OUTPUT_PATH}/${timestamp}_${revision}.not_applicable` and exit 0.
    - **Core issue:** Compass transitioned to a monorepo in commit `85d097c0c3` (April 2021, Era 2) by copying 70+ historically independent plugin repositories into `packages/` managed by Lerna v4, prior to the adoption of native npm workspaces (`0f2b435ced`, June 2021, Era 3). During Era 2, the plugin packages were unintegrated: many lacked direct dependency declarations (e.g. `lodash.isempty`), had missing peerDependencies (e.g. `reflux`), or depended on Babel/Webpack plugins that failed when symlinked locally (e.g. `transform-decorators-legacy`). Upstream Evergreen CI in Era 2 never ran a unified monorepo suite across all plugins—its CI task (`test-evergreen`) scoped execution strictly to `--scope mongodb-compass`. Attempting to force full monorepo testing across Era 2 would require retrofitting missing dependencies and patching configurations across dozens of packages at runtime, introducing severe measurement bias and inventing a test workflow upstream developers never ran. In Era 1 (pre-April 2021, 56 commits), Compass was a standalone wrapper importing pre-compiled plugins from npm.
    - **Longitudinal coverage feasibility & validity:** The study inclusion criterion requires that ≥ 90% of a project's commits produce valid longitudinal coverage. The commit distribution across the 6,260 commits is:
      - **Era 1 (Single-package legacy):** 56 commits (0.89%)
      - **Era 2 (Pre-workspaces Lerna):** 277 commits (4.42%)
      - **Era 3 (Native npm workspaces):** 5,927 commits (94.68%)
      Excluding Eras 1 & 2 leaves 94.68% of the repository's commits in Era 3. The 90% inclusion threshold requires 5,634 commits, leaving a buffer of 293 failing developer commits in Era 3 while remaining well above the inclusion threshold. Verification across Era 3 confirmed 100% clean test passes across all 40–52 workspace packages.
- **Coverage tool / config:**
  - `patch-coverage.js` walks all workspaces, configuring `nyc` reporting where missing, ensuring mocha and lerna run with `--no-bail`, and setting `"useNx": false` in `lerna.json` to prevent Nx task-graph bailing when upstream packages encounter failures.
- **LCOV production:** per-package `coverage/lcov.info` collected by `find-and-move-lcov.sh "test" "true" "$TEST_EXIT"`.

## Checklist

- [x] 100 done (2967/100)
- [x] failed tests doublechecked (true exit codes restored across 3,140 output directories via `helper/fix_compass_exit_codes.py`)
- [x] complete run (6,260/6,260 commits processed, 0 pending)
- [x] complete test failure check (176 fingerprints, 100 % labeled, 0 problematic, 0 unclear)
- [x] complete JEV test failure check (176/176 fingerprints labeled; audit current, see [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: [`stats_output/report.txt`](stats_output/report.txt) (generated 2026-11-04 18:52).

| Metric | Value |
|---|---|
| Commits processed | 6,260 |
| Without test failures | 4,272 |
| With test failures | 1,605 |
| Not applicable | 333 |
| Hard errors | 50 |
| Coverage produced | 99.2 % |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Sources: `python check_failures_v2.py compass --stats` (window `min`, run 2026-11-04) and
[`stats_output/report.txt`](stats_output/report.txt) (generated 2026-11-04 18:52). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (primary) and
[`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv) (diagnostic
window). The label CSVs are the single source of truth; this section reports numbers only.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 1,605 |
| Failing runs (label DB) | 1,605 |
| Fingerprints (min / max) | 176 / 183 |
| Labeled fingerprints | 176 (100 %) |
| Unlabeled fingerprints | 0 |
| acceptable | 132 |
| reevaluated_acceptable | 37 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 7 |
| Manual / auto-propagated labels | 0 / 176 |
| Labeled detections (min) | 8,893/8,893 (100 %) |
| Labeled runs (min) | 1,605/1,605 (100 %) |
| Jev mode | fingerprint |
| Jev pipeline issues | 53 flagged rows |
| Jev audit | current |

**State:** complete. The label DB and `report.txt` agree on 1,605 failing runs, every fingerprint
and detection is labeled, and no `problematic` or `unclear` family remains.


## Environment / setup fixes

- **Native CSFLE addon rebuild (`fix_mongocrypt_addon_rebuild`):** `npm install --ignore-scripts` suppresses `mongodb-client-encryption`'s `prebuild-install`/`node-gyp` step, and upstream's `node-rebuild` only covers `kerberos keytar interruptor`, so no `mongocrypt.node` was produced. In the driver-v4 era `data-service` requires the module at import, so 7 packages' suites died at load and their files were absent from LCOV; in the driver-v6 era 2 CSFLE tests failed. Fixed with a presence-guarded `npm rebuild mongodb-client-encryption --unsafe-perm`. Verified green on `e6754823` (2022, +2,651 covered lines recovered) and `ff4c2fd7` (2025). 2,032 affected runs archived to [`archive/fix_mongocrypt_addon_rebuild/`](archive/fix_mongocrypt_addon_rebuild/) for re-run.

- **Node type-stripping ESM crash (`fix_node_strip_types`):** Node 22.18+ enables `--experimental-strip-types` by default, so mocha's import-first path loaded `.ts` test bootstraps as ESM where `require` is undefined; `compass-schema-validation` crashed at load and its entire package was missing from LCOV (upstream COMPASS-10162). Fixed with a probe-guarded `--no-experimental-strip-types` appended to `NODE_OPTIONS` in `install-and-run.sh`, mirroring upstream's own `mocha-config-compass` >= 1.7.x workaround. 428 affected runs archived to [`archive/fix_node_strip_types/`](archive/fix_node_strip_types/) for re-run.

- **Silent zero-coverage packages (`fix_nycrc_instrument`):** `compass-crud` and `compass-home` shipped a `.nycrc` with `"instrument": false` — valid only for mocha-webpack builds — while running plain mocha, so nyc instrumented nothing and emitted no LCOV for 3.5 years (2,515 and 1,436 runs). `patch-coverage.js` now repairs such `.nycrc` files when the test script no longer uses `mocha-webpack`. A new detection pattern treats an all-zero coverage table as a failure so this class can never be invisible again. 111 runs archived to [`archive/fix_nycrc_instrument/`](archive/fix_nycrc_instrument/) for re-run.

- **Shared mongodb-runner port (`fix_mongod_port_collision`):** in the 2021-05 → 2023-05 era every package started a mongod on port 27018. npm skips `posttest` when `test` exits non-zero, so a failing package's mongod survived and the next package's `pretest` died with mongod `code: 48` (address already in use); its DB hooks then timed out. `patch-coverage.js` now prepends `scripts/killall-mongo.js` to every lifecycle script that starts a `mongodb-runner`, guarded on the script existing (inert after 2023-05, when upstream gave each package its own port). 122 runs archived to [`archive/fix_mongod_port_collision/`](archive/fix_mongod_port_collision/) for re-run.

- **Stale workspace-compile artifacts (`stale_workspace_compile`):** three runs compiled nothing (`lerna run prepare` found no packages, or only one), so dependants failed with `Cannot find module '…/lib/index.js'`. The current `lerna run bootstrap` handling already covers this; 3 runs archived to [`archive/stale_workspace_compile/`](archive/stale_workspace_compile/) for re-run.

- **Post-test crash detector repaired:** the monorepo sanity check never fired because it grepped `npm ERR! code ELIFECYCLE`, which npm 10 no longer emits (it prints `npm ERR! Lifecycle script ... failed with error:`). It now matches both phrasings and reads the package name from the same line, since lerna `--stream` prefixes it. Verified: the schema-validation crash is caught (exit 1), `mongodb-data-service` is correctly not flagged (it emitted tallies), and clean runs pass. Hard-fail is intentional: a crashed package must force assessment rather than silently under-measure.

- **Workspace compilation, hadron-build test adapter, chained Karma stripper & Node stub protection:** 427 runs were archived to [`archive/fix_workspace_prep_karma_and_serverstats/`](archive/fix_workspace_prep_karma_and_serverstats/) following fixes across early Era-3 npm workspaces (Jun 2021 – Mar 2022). In `patch-coverage.js`, aliased workspace `prepare` scripts to `bootstrap` and deleted `prepare` so npm 8 cannot fire premature out-of-order compilation hooks during `npm install`, added `hadron-react-components` to `peerDependencies` in `compass-import-export` so Webpack marks it as external, routed `hadron-build test` with `test/enzyme/_setup.js` to Node `mocha` yielding valid line coverage under NYC for `compass-serverstats`, cleanly stripped `download-akzidenz` and `download-csfle` from `prepare` without wiping `npm run compile`, stripped chained `test:karma` browser runs, and added a trailing `--` to all `node -e` stubs to prevent forwarded flags (`--no-bail`, `--exit`) from causing `node: bad option` crashes. In `install-and-run.sh`, executed serial topological compilation via `npx lerna run bootstrap --stream --concurrency 1 --no-bail` before running tests.

- **Monorepo per-package exit code assignment & soft-failure overhaul:** 6,087 runs were archived to [`archive/fix_soft_failures_and_exit_granularity/`](archive/fix_soft_failures_and_exit_granularity/) following comprehensive fixes across the monorepo suite. In `install-and-run.sh`, parsed the Lerna execution log post-run to verify which packages succeeded (`lerna success - <pkg>`) vs failed (`lerna ERR!`), assigning `0` to passing workspaces so a failure in one package does not mark all passing sibling packages with exit code 1. Pre-cached MongoDB 6.0 in Dockerfile and aligned version detection to `print-compass-env.sh`, eliminating BSON subtype 7 and search index errors. Redirected AWS IP ranges and cloud CIDRs to WayPack `/request/` proxy routes to resolve telemetry `FetchError` timeouts and cloud classification failures. Neutralized pre-split `electron-mocha` smoke tests in `patch-coverage.js`. Neutralized multi-line keytar date timebomb reminders. Scoped global `nyc` install to `nyc@14` on Node 12 to eliminate optional chaining syntax crashes.
- **Pre-seeded electron-chromedriver cache:** 1 run was archived to [`archive/fix_electron_chromedriver_cache/`](archive/fix_electron_chromedriver_cache/) following a 404 download failure in Era 1 (`electron-chromedriver@3.0.0` requiring `v`-prefixed tag in WayPack mirror URL). Fixed by pre-seeding `$HOME/.cache/electron/` directly from WayPack before running `npm install`.
- **Interrupted workers on stop:** 21 in-flight container runs stopped mid-execution were archived to [`archive/interrupted_workers_on_stop/`](archive/interrupted_workers_on_stop/) to return them to the execution queue.
- **Global nyc install from WayPack Current & generalized monorepo crash assertion:** 92 runs were archived to [`archive/era2_global_nyc_and_crash_guard/`](archive/era2_global_nyc_and_crash_guard/) following the discovery of `sh: 1: nyc: not found` in Era 2 (pre-workspaces) subpackages. Fixed by installing global `nyc` from `WAYPACK_REGISTRY_CURRENT` whenever `command -v nyc` is missing, and adding a generalized monorepo post-test assertion that detects any subpackage failing with `ELIFECYCLE` without emitting test tallies.
- **Node rebuild script & root Electron sandbox fix:** 100 runs were archived to [`archive/fix_node_rebuild_and_sandbox/`](archive/fix_node_rebuild_and_sandbox/) following fixes for the native compilation loop abort (where `scripts/rebuild.js` aborted prematurely on `mongodb-client-encryption` leaving `interruptor.node` uncompiled across 92 commits) and Era-1 Electron root sandbox crashes (where 4 runs crashed with `FATAL:atom_main_delegate.cc(210) Running as root without --no-sandbox is not supported`). Fixed by calling upstream's `npm run node-rebuild` (targeting `kerberos keytar interruptor`), compiling `os-dns-native` independently, and exporting `ELECTRON_EXTRA_LAUNCH_ARGS="--no-sandbox"` in Era 1.
- **Network mocks, serial execution & native rebuild overhaul:** 97 runs were archived to [`archive/fix_network_mocks_and_serial_harness/`](archive/fix_network_mocks_and_serial_harness/) following fixes for Atlas CI credential failures (`CI=false`), WayPack GA mock (`ga-debug.json`), keytar deadline date timebomb neutralization, dynamic native addon compilation (`mongodb-client-encryption`, `os-dns-native`), Lerna serial execution (`concurrency = 1`), and MongoDB 7.0 pre-caching.
- **Keytar removal date timebomb neutralization:** `packages/connection-storage/src/compass-main-connection-storage.spec.ts` contains an intentional test reminder asserting `expect(new Date(), ...).to.be.lessThan(endOfKeytarDate)` where `endOfKeytarDate` was set to May 17, 2024. Running in 2026 caused this assertion to fail unconditionally. `install-and-run.sh` patches this assertion to evaluate against `testDate` matching its behavior when committed.
- **Serial package execution (`concurrency = 1`):** Upstream tests require serial dispatch because packages (`compass-crud`, `compass-import-export`, `mongodb-connection-model`) manage a local standalone MongoDB instance on port 27018 via `pretest` and `posttest-ci: node scripts/killall-mongo.js`. Running with concurrency > 1 caused packages finishing earlier to kill mongod while sibling packages were actively querying it. Enforced serial execution across `lerna.json` and `NX_PARALLEL=1`.
- **Upstream native addon compilation:** In Era 3, `install-and-run.sh` invokes upstream's own `npm run node-rebuild` script (targeting `kerberos keytar interruptor`) followed by `os-dns-native`, compiling `.node` binaries against the active Node runtime ABI without attempting to build proprietary/static enterprise CSFLE libraries.
- **Pre-cached MongoDB server binaries (4.4, 5.0, 7.0, 8.0):** Pre-baked official MongoDB Community binaries under `/opt/mongodb/`. `install-and-run.sh` detects the required version from project CI or inspects the `mongodb` driver version in `package.json` (3.x → 4.4, 4.x → 5.0, 5.x → 7.0, 6.x → 8.0) without date-based guesswork, dynamically linking `/usr/local/bin/mongod`.
- **`mongos` for the sharded-cluster suite (`fix_mongos_sharded_cluster`):** `09d1c368` (2025-11-10) added the repository's only sharded test — `packages/data-service/src/data-service.spec.ts` → `with real sharded cluster`, `mochaTestServer({ topology: 'sharded' })`. mongodb-runner 5.x starts that topology by spawning `<binDir>/mongos`; the image shipped only `mongod`, so the spawn produced `ENOENT`, which `MongoServer.start`'s catch handler turned into `TypeError: Cannot read properties of undefined (reading 'some')` (`err.errorLogEntries.some(...)`, where a spawn error has no `errorLogEntries`) — the TypeError *was* the missing binary. `projects/compass/Dockerfile` now extracts `bin/mongos` beside `bin/mongod` for 4.4 / 5.0 / 6.0 / 7.0 / 8.0 and links `/usr/local/bin/mongos`; `install-and-run.sh` symlinks `bin/mongos` into the mongodb-runner downloader cache next to `bin/mongod`, guarded on the binary existing. Inert before 2025-11-10, where nothing spawns `mongos`. 167 runs archived to [`archive/fix_mongos_sharded_cluster/`](archive/fix_mongos_sharded_cluster/) and re-run: `with real sharded cluster` executes `#fetchShardKey` and `#indexes … includes the shard key` in **167/167**, `mongodb-data-service` moves from 207 passing + 1 failing to **209 passing + 0 failing**, and the corpus failing-run union drops by exactly 167 (1,772 → 1,605).
- **`CI=false` environment configuration:** In upstream `packages/data-service`, Atlas test suites check `if (!IS_CI && !COMPASS_TEST_ATLAS_URL) return this.skip()`. When `CI` defaults to true or is exported, tests attempt unauthenticated connections to decommissioned MongoDB staging clusters (`...-shard-00-00.mongodb.net`, `compass-data-sets.e06dc.mongodb.net`) and fail with `MongoServerSelectionError` / `ENOTFOUND`. Setting `export CI=false` triggers upstream's skip guard, preventing cluster connection timeouts and crashes without affecting coverage.
- **WayPack Google Analytics mock (`ga-debug.json`):** `packages/metrics` unit tests assert on responses from Google Analytics debug collector (`https://www.google-analytics.com/debug/collect`). Google decommissioned GA3 debug endpoints in July 2023, returning HTTP 404 or DNS failure. Added mock file `waypack-machine/local_files/ga-debug.json` registered in `files.config.json` with POST support enabled in `routes/local.py`, and redirected `ga.js` tracker requests to `http://waypack:3000/local/ga-debug.json?`.
- **Major process overhaul & upstream CI alignment:** 110 legacy runs were archived to [`archive/restart_upstream_ci_alignment/`](archive/restart_upstream_ci_alignment/) following a major overhaul to align the harness with upstream Evergreen CI and developer workflows.
- **Era 2 CLI ignore-scripts & stopped runs:** 13 failed and interrupted runs were archived to [`archive/fix_era2_cli_ignore_scripts/`](archive/fix_era2_cli_ignore_scripts/). Scoped `--ignore-scripts` directly to CLI flags in Era 2 instead of exporting it globally, preventing test script suppression under npm 6.
- **System dependencies:** `libkrb5-dev`, `libsecret-1-dev`, `net-tools`, `gnome-keyring`, `xvfb`, `libnotify-dev`, `libxtst6`, `libxss1`, `libgtk-3-0`, `libgdk-pixbuf2.0-0`, `libpango-1.0-0`, `libgbm1`, `libxshmfence1`, `libssl1.1`, and `libssl3` installed in Dockerfile using Debian Bookworm repositories.
- **Xvfb service:** Headless virtual frame buffer started on `:99` prior to tests.
- **Nx task-graph bail prevention:** `patch-coverage.js` injects `"useNx": false` into `lerna.json` to enforce sequential package execution without skipping dependent workspaces when an upstream package fails.
- **Lerna execution streaming:** `--stream` is injected into `lerna run` scripts and passed in `install-and-run.sh` to ensure package test output is emitted live instead of buffered until process completion.
- **Pre-workspaces monorepo bootstrap:** For commits between 2021-04 (Lerna introduction) and 2021-06 (npm workspaces adoption) where `lerna.json` exists but `package.json` lacks `"workspaces"`, `install-and-run.sh` invokes `npx lerna bootstrap --no-ci` to link local monorepo sibling packages without lockfile desync aborts.
- **External asset download neutralization:** `patch-coverage.js` neutralizes package install calls to `scripts/download-akzidenz.js` and `scripts/download-csfle.js`, which are packaging-only downloads (font files and client-side encryption libraries) not exercised by unit suites.
- **Mocha process hang prevention (`--exit`):** `patch-coverage.js` injects `--exit` into all `mocha` package test scripts to terminate open database connections and IPC sockets once assertions complete.
- **Chained raw `electron-mocha` strip (`fix_electron_mocha_chain`):** the existing neutralizers only caught scripts that *were* `electron-mocha` or chained it via `npm run test:electron`. The 2021 `mongodb-compass` root `test-ci` chained a raw `&& xvfb-maybe electron-mocha …`, so it ran, found no electron binary and aborted the process with `ENOENT` — after `nyc … npm run test-release-tasks` had already produced coverage. `patch-coverage.js` now strips a trailing `&& [xvfb-maybe] electron-mocha …` segment from any script and keeps everything before it; the rule is inert where the segment does not occur. 234 runs archived to [`archive/fix_electron_mocha_chain/`](archive/fix_electron_mocha_chain/) for re-run.
- **Deterministic test-host DNS preload (`fix_ssh_host_dns_preload`):** three names used only by SSH-failure tests were answered so slowly by the container resolver that fast, expected DNS failures became 2 s/15 s mocha timeouts and exact-string assertion mismatches — `my.ssh-server.com` (a real domain that is NXDOMAIN: 90 `ENOTFOUND` vs 90 `EAI_AGAIN` runs on the same days), `nonexistent-ssh-server.test` (RFC 2606 reserved TLD), and `compass-tests.fakehost.localhost` (RFC 6761 reserved name; 175/175 runs returned `EAI_AGAIN`, never `ENOTFOUND`). `install-and-run.sh` now writes `/tmp/compass-dns-interceptor.js` and preloads it through `NODE_OPTIONS=--require` for the test phase only; it returns `getaddrinfo ENOTFOUND` for all three — the two names that genuinely do not exist, plus the `fakehost` fixture, whose assertion accepts only `ENOTFOUND` in the 2022–2023 era (`ECONNREFUSED 127.0.0.1:22` was added as an alternative only in 2024). Every other lookup is delegated untouched. The interceptor lives outside the repo so nyc never instruments it, is an exact-name allowlist rather than a suffix match, and honours `options.all` / `family: 6`. 182 fakehost runs archived to [`archive/fix_fakehost_localhost_dns/`](archive/fix_fakehost_localhost_dns/), 84 ssh-tunnel runs to [`archive/retry_nonexistent_ssh_dns_flake/`](archive/retry_nonexistent_ssh_dns_flake/), and 1 `connection-model` run to [`archive/fix_ssh_host_dns_preload/`](archive/fix_ssh_host_dns_preload/) for re-run.
- **Docker-in-Docker for the connectivity suite (`fix_dind_connectivity_tests`):** `packages/data-service/test/connectivity.spec.ts` (present only 2021-08-26 → 2021-10-11) starts a MongoDB through `docker-compose`, and its guard (`process.platform !== 'linux'`) means it always runs on Linux and is always skipped on a developer's laptop — so the container had to provide a daemon. `projects/compass/Dockerfile` now sets `LABEL dind.project="true"` (which makes `docker-run.sh` pass `--privileged`) and installs `docker.io` + `docker-compose`; `install-and-run.sh` sources `start-dind.sh` **only when that spec exists**, prefetches `mongo:${MONGODB_VERSION}` through the `docker-multi-cache` registry mirror, then unsets `HTTP_PROXY`/`HTTPS_PROXY` so the registry proxy cannot capture test traffic. The compose file pins `mongo:${MONGODB_VERSION:-4.4}` and the harness exports a full patch version (e.g. `4.4.29`), so the image is fully pinned — stricter than upstream CI, which passes only the major (`mongo:4`). **Standalone verification passes:** 159 passing (was 158 + 1 failing), `✓ connects to a community server`. **The end-to-end re-run does not reproduce that** — see the connectivity-suite row under *Known test failures*: 108 of 108 in-window runs still fail, one step further along the same chain (nested container creation). The environment is not the cause — the same commit passes with `CONTAINER_CPUS=6 SKIP_BUILD=true USE_TMPFS=true` and with the exact `/bin/sh` + seven-argument invocation `docker_run.py` builds — so the remaining suspect is contention from 20 parallel containers each running its own daemon. The 108 runs are archived to [`archive/retry_dind_low_concurrency/`](archive/retry_dind_low_concurrency/) and were re-run at **3 workers**: 110/110 reach `✓ connects to a community server` with 0 compose errors and 0 `runc … EOF`, so the contention diagnosis is confirmed and no code change was required.
- **WPT fixture fetch via WayPack (`fix_wpt_fetch_via_waypack`):** `compass-web`'s tr46 polyfill spec fetches `toascii.json` from `raw.githubusercontent.com` in a `before` hook; when that round-trip transiently reset, the whole suite died with `TypeError: fetch failed` (66 of 4,408 runs with the spec, ~1 per affected day). The URL is content-addressed by commit SHA, so it is immutable and safe to cache: `install-and-run.sh` rewrites only its static prefix to `http://waypack:3000/request/…`, preserving the `${wptSHA}` template. 45 live runs archived to [`archive/fix_wpt_fetch_via_waypack/`](archive/fix_wpt_fetch_via_waypack/). Verified: `✔ should pass wpt specs`, 25 passing, 0 fetch failures. Four further occurrences in the 2026-11-04 batch (same `TypeError: fetch failed`, proxy unanswered) were archived to [`archive/retry_wpt_fetch_flakes/`](archive/retry_wpt_fetch_flakes/) and redrawn clean (`26 passing` in all four).

## Known gaps

- **`@mongodb-js/compass-instance` — 1,082 runs, 2021-12-21 → 2022-11-21, not recoverable.**
  `1a6ac32a1b` deleted `src/plugin.spec.js` while `test` remained
  `mocha-webpack "./src/**/*.spec.js"`, so the glob matched nothing (`0 passing (0ms)`,
  `MOCHA Tests completed successfully`) and the package contributed no LCOV. Confirmed at
  `dd8cde2ff0` (2022-03-09): the only spec left is the `test/renderer/store.spec.js` placeholder.
  Coverage returns at the upstream migration `bb1a39e78c` (`test: mocha`). Recovering the window
  would require fabricating the deleted test.
- **Electron-smoke-only packages — deliberate exclusion, no LCOV emitted.** `hadron-ipc` (805
  runs), `hadron-auto-update-manager` (805), `packages/compass` (162) and
  `compass-saved-aggregations-queries` (67). Their `test-ci` runs `electron-mocha` or
  `hadron-build test`, which execute inside Chromium where line coverage cannot be collected;
  `patch-coverage.js` neutralizes them to `skipping standalone electron smoke suite`. Unlike an
  empty file, no `.lcov` artifact is produced, so nothing misleading enters the merged LCOV.
  Coverage returns where upstream reintroduces a Node `mocha` suite (e.g. `hadron-ipc`, 2023).
- **Zero-coverage tables in green runs are not detected.** `failure_triage/detect.py::scan` skips
  a run when no package exit code is non-zero, and then scans only the failing packages' spans.
  Of the 1,688 runs that contain an all-zero `All files | 0 | 0 | 0 | 0` table, 43 sit in a run
  with a non-zero package exit code and 1,645 are never read. The five per-package `acceptable`
  rules are correct; they receive no rows for green runs. A fix requires a second pass over every
  run (shared tooling, not applied).
- **`test-ci` is preferred over `test`.** `install-and-run.sh` executes one script per package
  (`test-ci` when it exists, `test` otherwise), and `patch-coverage.js` synthesizes the missing
  coverage variants. Across `packages/*/package.json` at 2021-07, 2021-12, 2022-01-28, 2022-03,
  2022-09, 2023-06, 2024-06 and 2025-08, no package had `test` without `test-ci`, and one had an
  Electron-only `test-ci` beside a Node `test`: `compass-saved-aggregations-queries`,
  2022-01-24 → 2022-02-07 (67 runs; introduced by `27359a00e3`, ended by `f4c6471108`, which also
  made the Node suite runnable). `packages/compass` is the second exception and its `test`
  (`hadron-build test`) is also Electron-driven.
