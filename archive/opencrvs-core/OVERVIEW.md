# opencrvs-core

**Repository:** https://github.com/opencrvs/opencrvs-core
**Status:** active

## Test infrastructure

- **Package manager:** yarn (workspaces + lerna; runs observed with `yarn@1`),
  see [`config.json`](../../config.json) → `opencrvs-core`.
- **Node strategy:** default.
- **Runners:**
  - `jest` — backend packages (`auth`, `commons`, `gateway`, `notification`,
    `search`, `user-mgnt`, `webhooks`, `workflow`, `config`).
  - `vitest` — `client` (from ~2022-08, replacing craco/jest) and `events`
    (from 2024).
  - `craco test` — `client` early era (2020–2022), wraps jest.
- **Eras:** `packages/e2e` uses Cypress (excluded); `test-storybook` in `client`
  is excluded. Neither is part of the root `test` dispatch.

## Development style

- **PR merging strategy:** Hybrid (Squash and merge for feature PRs ~58.5%; Merge commit for release/integration branches ~34.3%).
- **Merge convention:** `<Title> (#<PR>)` for features; `Merge pull request #<PR> from <branch>` for release branches.
- **Direct commits:** Low (7.2% human direct commits, 194 commits).
- **JS/TS code impact of direct commits:** Low — docs, ACTIONS.md amendments, Docker compose/Swarm config adjustments, and hotfixes by core maintainers.
- **Issue tracking discipline:** High (features and bugs tracked via GitHub issues and PRs).
- **Workflow notes:** Switched from 98% merge commits in 2021 to a GitFlow hybrid: feature branches squash into `develop`, while milestone release branches merge.

## Coverage collection

- **Suites collected:** the root `test` script (`lerna run test`).
- **Suites excluded:** Cypress/Playwright e2e and `test-storybook`; their scripts
  are neutralised to noops.
- **Coverage tool / config:** `patch-coverage.js` walks every `package.json`
  outside `node_modules`/`.git`/`dist`/`build`/`lib` and appends runner coverage
  flags. Vitest handling is version-aware:
  - `jest` / `craco test` → `--coverage --coverageReporters=lcov --maxWorkers=2`.
  - `vitest` ≥ 1 (events) → `--coverage --coverage.reporter=lcov --maxWorkers=2 --minWorkers=2`;
    the provider `@vitest/coverage-v8` (pinned to the resolved vitest version)
    is installed out-of-tree after install.
  - `vitest` 0.x (client, login) → `--coverage.enabled=true --coverage.reporter=lcov`,
    with parallelism capped via `VITEST_MAX_THREADS=2 VITEST_MIN_THREADS=2`.
  - root `test`: `lerna run test` → `--no-bail --concurrency=1`.
- **LCOV production:** `lerna run build` runs first because tests import workspace
  packages via `dist/` (standalone web bundlers `client`/`login` and non-library targets
  `integration`/`build-storybook` are excluded); then `find-and-move-lcov.sh "test" "true"`.
- **Install:** `yarn install --frozen-lockfile --ignore-scripts --ignore-engines` (matches the
  project's CI and avoids lockfile rewrites / hoisting drift). `patch-coverage.js`
  runs first and records any required vitest provider in
  `.coverage-providers.json`; the provider is installed after install into
  `node_modules/.coverage-providers/` and symlinked into the consuming package.

## Checklist

- [x] 100 done (100-commit sample reviewed)
- [x] failed tests doublechecked (non-zero-exit runs inspected and classified)
- [wip] complete run (pending 4385 rerun)
- [x] complete test failure check (100% of failure fingerprints labeled in v2 database)
- [x] complete JEV test failure check (4211 fingerprints evaluated; audit: [jev_audit.md](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-22 16:12).

| Metric | Value |
|---|---|
| Commits processed | 11724 |
| Without test failures | 4025 |
| With test failures | 6697 |
| Not applicable | 0 |
| Hard errors | 1002 |
| Coverage produced | 91.5% |
| Commits not yet processed | 0 |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py opencrvs-core --stats` (window `min`, run 2026-10-22) and
`stats_output/report.txt` (generated 2026-10-22 16:12). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 6697 |
| Failing runs (label DB) | 6670 |
| Fingerprints (min / max) | 4202 / 6015 |
| Labeled fingerprints | 4202 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 3598 |
| reevaluated_acceptable | 557 |
| problematic | 3 |
| unclear | 0 |
| false_positive | 44 |
| Manual / auto-propagated labels | 70 / 4132 |
| Labeled detections (min) | 49134/49134 (100.0%) |
| Labeled runs (min) | 6670/6670 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 233 fps flagged; 1 confirmed pipeline defect (`.secrets`, fixed) — see audit |
| Jev audit | [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) |

**State:** complete.

| Label | Suite | Signature / Root Cause | Rule / Fingerprints | First..Last Run | Runs (Union) |
|---|---|---|---|---|:---:|
| `problematic` | `packages_auth_test` | `Cannot find module 'vitest/coverage'` (out-of-tree coverage provider symlink resolved to root Vitest 0.25) | `vitest_coverage_provider_events` (2 fps) | `1731925489`..`1767183993` | 4208 |
| `problematic` | `packages_config_test` | `updateFormDraftHandler handler › should update question using mongoose` (transient 5000ms timeout) | `701263588408` (1 fp) | `1648707415` | 1 |

## Environment / setup fixes

- **Monorepo test suite assertion guard & zero-test crash archiving:** Implemented multi-package
  test execution assertion guard in `install-and-run.sh` to prevent packages from silently crashing
  or reporting 0 tests on non-zero exit codes. Switched `MONGOMS_DOWNLOAD_URL` to `MONGOMS_DOWNLOAD_MIRROR`
  (stopping `DryMongoBinary.parseArchiveNameRegex` crashes in MongoMemoryServer), and neutralized
  unconfigured test stubs (`@opencrvs/dashboards` `echo "Error: no test specified"`). 60 historical runs
  exhibiting zero-test crashes archived to [`archive/assert_zero_test_package_crashes/`](archive/assert_zero_test_package_crashes/),
  and 41 earlier runs exhibiting `MongoMemoryServer` download URL regex errors archived to
  [`archive/mongoms_download_mirror_config/`](archive/mongoms_download_mirror_config/) for re-run.

- **Vitest coverage provider module resolution (`@opencrvs/events`):** In `packages/events`,
  out-of-tree `@vitest/coverage-v8` symlink caused Node ESM to resolve `vitest/coverage` from root
  `node_modules` (Vitest 0.25.5 from client/login) instead of `packages/events/node_modules/vitest`
  (Vitest 2.1.5), causing `@opencrvs/events` to crash on startup and produce 0% coverage. 4,208 affected
  runs archived to [`archive/vitest_coverage_provider_events/`](archive/vitest_coverage_provider_events/)
  for re-run.

- **`@opencrvs/integration` build exclusion:** `packages/integration` was a
  standalone directory of k6 load-testing scripts with no unit test suite,
  never imported by any package, and excluded by the project's own root scripts
  (`--ignore @opencrvs/integration`). Upstream removed its `"build"` script in
  `87eb5c076b` (2021-11-24) to avoid build failures, and removed the package
  entirely in July 2023. Because our pipeline runs `lerna run build` (to compile
  workspace packages skipped by `--ignore-scripts`), `install-and-run.sh`
  neutralizes `packages/integration`'s build script and ignores it during
  `lerna run build` to prevent ambient TypeScript version collisions (duplicate
  `AbortController`/`FormData` TS2300 errors) in 2021 commits.
- **`@vitest/coverage-v8` provider (events):** vitest ≥ 1 requires the coverage
  provider as a separate package. `patch-coverage.js` records it (pinned to the
  resolved vitest version) in `.coverage-providers.json`; `install-and-run.sh`
  installs it out-of-tree (`node_modules/.coverage-providers/`) and symlinks it
  into the package, keeping the frozen workspace tree untouched.
- **Frozen install:** `yarn install --frozen-lockfile --ignore-scripts --ignore-engines`
  matches the project's CI and prevents the lockfile rewrite / dependency re-hoist that a
  non-frozen install performs, while preventing engine validation aborts on container patch-level
  Node mismatches (e.g. Node 18.20.8 vs 18.19.x).
- **Upstream DNS forwarders on Podman network:** configured upstream resolvers
  (`1.1.1.1` and `8.8.8.8`) on the `mining-net` Podman network to prevent host/university
  DNS resolution dropouts when resolving `registry.npmjs.org`.
- **Native addon `iconv` (2022-era notification):** `--ignore-scripts` skips its
  node-gyp build, so the SMS suites fail to run. `install-and-run.sh` detects
  `"iconv"` in `packages/notification/package.json` and runs
  `npm_config_nodedir=... npm_config_python=/usr/bin/python2.7 npm rebuild iconv`
  using the Node installation's local headers.
- **Storybook build exclusion:** in mid-2024 commits, upstream chained `&& lerna run build-storybook`
  to the root `"build"` script. Because Storybook is an excluded UI documentation target (not part of
  the behavioral test suite), its preview build fails in headless containers. `install-and-run.sh`
  strips `build-storybook` from the root build command and neutralizes `packages/components`'s
  `build-storybook` script so only workspace packages are compiled for `dist/`.
- **`@opencrvs/client`, `@opencrvs/login`, `@opencrvs/metrics`, and `@opencrvs/auth` build exclusion:**
  the root `"build"` script invokes `lerna run build`, which attempts to build all workspace packages.
  In `packages/client` and `packages/login`, `"build"` runs Vite, Craco, or Webpack production web
  bundlers to create minified static HTML/JS/CSS assets for container deployments. In ~137 commits,
  asset graph resolution or Rollup/Babel AST parsing errors in these web bundlers abort Lerna before
  unit tests execute. In `packages/metrics` and `packages/auth`, `tsconfig.json` did not exclude
  `src/**/*.test.ts` from compilation, so `tsc` output compiled JavaScript tests into `build/dist/`
  (without copying `.json` fixtures in `metrics`, or breaking module/database mocks in `auth`). Because
  Jest's `testRegex` matched both `.ts` and `.js` prior to March 2022, Jest redundantly executed the
  compiled tests in `build/dist/` and failed. Monorepo audit confirms zero workspace packages depend on
  `client`, `login`, `metrics`, or `auth`, and their test suites run directly against TS/TSX source
  files without importing the production build. `install-and-run.sh` neutralizes their `"build"` scripts
  and adds `--ignore @opencrvs/client --ignore @opencrvs/login --ignore @opencrvs/metrics --ignore @opencrvs/auth`
  to `lerna run build`, while leaving all shared libraries (`commons`, `components`, `events`, `toolkit`)
  under strict build verification.
- **Node heap (client):** `NODE_OPTIONS=--max-old-space-size=16384`, with inline
  per-test overrides normalised by `patch-coverage.js`, prevents the client c8
  coverage report from OOM-ing (exit 134) and dropping client lcov.
- **vitest 0.x flag handling (client, login):** vitest 0.25 has no
  `--maxWorkers` and its CLI rejects `--coverage.reporter=lcov` alongside a bare
  `--coverage`. The patch emits `--coverage.enabled=true
  --coverage.reporter=lcov` and caps parallelism via `VITEST_MAX_THREADS` /
  `VITEST_MIN_THREADS` (threads stay on, preserving per-file isolation).
- **Static typecheck (`test:compilation` / `tsc --noEmit`) exclusion from chained test scripts:**
  multiple packages (notably `@opencrvs/client`, `@opencrvs/metrics`, and in later eras `@opencrvs/events`)
  chained `yarn test:compilation && <runner>` in their `test` script. When strict TypeScript compilation
  errors occurred in the repo, the shell's `&&` aborted execution before the behavioral test runner
  launched, preventing coverage from being collected. `patch-coverage.js` explicitly excludes
  `test:compilation` / `tsc --noEmit` segments from chained test scripts whenever a behavioral runner
  is present, ensuring the test suite always runs and produces coverage while preserving all other
  chained steps.
- **`.dockerignore`:** whitelists `patch-coverage.js` so the project image build
  does not silently fall back to a stale cached image.
- **`MongoMemoryServer` binary caching:** routes `MONGOMS_DOWNLOAD_URL` through Waypack
  caching proxy (`http://waypack:3000/request/https://fastdl.mongodb.org`) to prevent transient
  502/timeouts from `fastdl.mongodb.org` during `@opencrvs/config` tests.
- **Docker-in-Docker conditional start & explicit `DOCKER_HOST`:** packages `@opencrvs/gateway` and
  `@opencrvs/search` use `testcontainers` for Redis and Elasticsearch containers in integration tests.
  `install-and-run.sh` conditionally sources `/coverage_reloaded/start-dind.sh` and explicitly exports
  `DOCKER_HOST="unix:///var/run/docker.sock"` when `testcontainers` is detected in any workspace `package.json`.
  11 historical runs affected by `No Docker client strategy found` were archived to
  `projects/opencrvs-core/archive/dind_testcontainers_docker_client/`.
- **Docker Hub registry 502 / Redis pull failure:** During `@opencrvs/gateway` `testcontainers` execution,
  transient Docker Hub 502 Bad Gateway outages aborted `redis:5` pulls. 8 affected runs archived to
  [`projects/opencrvs-core/archive/docker_hub_registry_502/`](archive/docker_hub_registry_502/) for re-run.
- **Docker-in-Docker socket and image pull timeouts:** During `@opencrvs/search` and `@opencrvs/gateway`
  `testcontainers` execution, transient Docker socket disconnection (`No Docker client strategy found`),
  missing images (`redis:5`, `elasticsearch:8.14.3`), and Docker Hub rate limit timeouts occurred.
  10 affected runs archived to [`projects/opencrvs-core/archive/dind_testcontainers_pull_failures/`](archive/dind_testcontainers_pull_failures/) for re-run.
- **Docker-in-Docker Redis startup hook timeouts:** During `@opencrvs/gateway` `testcontainers` execution,
  transient DinD latency caused Redis container startup to exceed Jest's 30000ms hook timeout or leave
  the Redis client connection uninitialized (`flushall` undefined). 6 affected runs archived to
  [`projects/opencrvs-core/archive/dind_redis_hook_timeout/`](archive/dind_redis_hook_timeout/) for re-run.
- **Runner CPU saturation timeout flakes:** Transient Jest per-test timeouts (5000ms in `@opencrvs/metrics` /
  `@opencrvs/config` or 30000ms Enzyme hook in `@opencrvs/client`) caused by temporary host CPU core saturation.
  2 affected runs archived to [`projects/opencrvs-core/archive/runner_timeout_flakes/`](archive/runner_timeout_flakes/) for re-run.
- **Lerna v8 Nx task runner bailing:** In Lerna v8 (June 2024 onwards), the Nx task runner defaulted
  to `--nx-bail=true`. When any individual workspace package experienced a test failure, Nx aborted
  all downstream and independent packages with `Tasks not run because their dependencies failed or --nx-bail=true:`,
  violating the Bail Rule (§2). Fixed by exporting `NX_BAIL=false` in `install-and-run.sh` and appending `--nx-bail=false` in `patch-coverage.js`.
  85 affected runs archived to [`projects/opencrvs-core/archive/lerna_nx_bail/`](archive/lerna_nx_bail/) for re-run.
- **MongoMemoryServer Waypack cold-cache 502 outage:** Initial restart of 10 concurrent workers on a cold
  Waypack proxy cache triggered HTTP 502 Bad Gateway timeouts downloading the 85MB MongoDB binary
  (`mongodb-linux-x86_64-debian11-7.0.14.tgz`), causing `@opencrvs/events` to report 0 tests.
  Cache has been warmed and verified. 12 affected runs archived to
  [`projects/opencrvs-core/archive/mongoms_waypack_cold_cache_502/`](archive/mongoms_waypack_cold_cache_502/) for re-run.
- **MongoMemoryServer runtime download timeouts / proxy saturation:** Under high worker concurrency
  (10–15 workers), simultaneous runtime downloads of the 85MB MongoDB binary through the single-threaded
  Waypack proxy resulted in extreme latency (>2.5 min), connection drops, and HTTP 502 status errors in
  `@opencrvs/events` and `@opencrvs/config`. Fixed by pre-installing MongoDB 7.0.14 into `/usr/local/bin/mongod`
  directly in `Dockerfile` and exporting `MONGOMS_SYSTEM_BINARY="/usr/local/bin/mongod"` in `install-and-run.sh`
  to bypass runtime network downloads completely. 322 affected runs archived to
  [`projects/opencrvs-core/archive/mongoms_system_binary_preinstall/`](archive/mongoms_system_binary_preinstall/) for re-run.
- **Rollup GLIBC 2.32 requirement:** Vitest 2.x out-of-tree coverage provider in `packages/events` pulled
  prebuilt `@rollup/rollup-linux-x64-gnu` requiring GLIBC ≥ 2.32, which failed on the Debian Bullseye base (GLIBC 2.31).
  Upgraded libc packages to Bookworm (GLIBC 2.36) in `Dockerfile` (matching the pattern in `projects/desktop`).
- **Docker Hub pull timeouts (docker-multi-cache cold blob fetches):** testcontainers
  image pulls (`redis`, `postgres`, `elasticsearch`, `ryuk`) timed out at
  `Get "https://registry-1.docker.io/v2/": context deadline exceeded` when
  `docker-multi-cache` had to fetch cold blobs from upstream over the flaky campus
  egress. In 103 runs the zero-test assertion guard aborted the run (hard errors);
  44 further runs produced coverage but with infra-induced test failures and
  degraded suite coverage. Fixed by warming `docker-multi-cache` with the full
  historical image set host-side through the proxy via
  [`warm-docker-cache.sh`](warm-docker-cache.sh) (run it again after any cache
  wipe). 147 affected runs archived to
  [`archive/docker_multi_cache_cold_pull_timeout/`](archive/docker_multi_cache_cold_pull_timeout/)
  for re-run.
- **`yarn.lock` npmjs `resolved` URLs bypassing WayPack:** yarn v1 fetches tarballs
  from the verbatim `resolved` URL, and `execute.sh`'s lockfile rewrite only
  covered `registry.yarnpkg.com` / `bnpm.byted.org`. This project's lockfiles are
  mixed-host (~half `registry.npmjs.org`), so those tarballs were fetched direct
  over the campus egress — also a temporal-correctness bug (tarballs fetched as of
  now, not the commit timestamp). Transient 502/503 on one tarball aborted
  `yarn install` (68 × 502, 1 × 503). `execute.sh` now rewrites
  `resolved "https://registry.npmjs.org/` and `http://` variant to
  `$WAYPACK_YARN_REGISTRY` too (validated 2019–2025 lockfiles: 0 public-registry
  `resolved` URLs remain; only this project showed live failures). 69 affected
  runs archived to
  [`archive/yarnlock_npmjs_resolved_bypasses_waypack/`](archive/yarnlock_npmjs_resolved_bypasses_waypack/)
  for re-run.
- **Docker registry auth-handshake timeouts:** residual of the cold-blob issue —
  after warming `docker-multi-cache`, all image blobs are LAN cache hits (zero
  cache misses in the 2026-10-30 re-run), but the uncachable registry handshake
  (`/v2/` ping → 401 → `/token`) still round-trips upstream per pull and
  intermittently 502s or times out on the flaky campus egress (proxy log showed
  5 × `/v2/` 502; failing runs paired up across concurrent workers). 16 runs
  archived to
  [`archive/docker_registry_handshake_timeout/`](archive/docker_registry_handshake_timeout/)
  for re-run. Pending mitigations (not yet applied): bounded `docker pull` retry
  before tests (cheap — blobs are cache hits) and/or `registry-mirrors` pointed
  at docker-multi-cache's local mirror endpoint so `/v2/` is answered locally.
- **vitest 0.x tinypool worker race (`client`/`login`):** with ≥2 concurrent
  workers, tinypool's stale-task-response race throws
  `Error: Unexpected message from Worker: { taskId, result: undefined, error: null }`
  in `WorkerInfo.onMessage` and hard-kills the runner mid-suite (~5–10 % rate;
  timing-sensitive, lineage-agnostic — 82 % branch-intermediate vs 81.5 %
  baseline). 91 runs hard-failed and 11 runs emitted potentially silently
  truncated lcov. Reproduced 2/2 at 2 workers and eliminated at 1 worker
  (container debug on `15150548…`, 2026-10-31); `--no-threads` is unusable
  (cross-file state pollution: 113/114 files fail with 0 tests).
  `patch-coverage.js` now emits `VITEST_MAX_THREADS=1 VITEST_MIN_THREADS=1` for
  vitest 0.x. 102 affected runs archived to
  [`archive/vitest0x_tinypool_worker_race/`](archive/vitest0x_tinypool_worker_race/)
  for re-run.
- **Build-phase `tsc` artifacts of the dist-based flow:** (1) workspace libs
  (e.g. `@opencrvs/commons`, early-2022 window) emit no type declarations
  (plain `tsc`, no `declaration`, no `types` field), so `noImplicitAny`
  dependents fail `TS7016` before `dist/` exists — the dev's tests run against
  source and never needed the build. (2) Other eras' builds fail on
  declaration-check noise *inside* `node_modules` `.d.ts` files (`apollo-link`'s
  `ExecutionResult` merge conflict with `graphql`; `apollo-server-hapi`
  importing the renamed `hapi`) via `TS2430`/`TS2307`, while emit is unaffected.
  `install-and-run.sh` now runs a declaration-only emit pass
  (`tsc --declaration --emitDeclarationOnly`) for untyped workspace packages
  (inert for `tsc -d` / `declaration: true` eras) and patches workspace
  tsconfigs with `skipLibCheck: true` for the build only. 260 affected runs
  archived to
  [`archive/tsc_build_decls_and_skiplib/`](archive/tsc_build_decls_and_skiplib/)
  for re-run. Remaining `tsc` hard failures (~280 pipeline-candidates not yet
  addressed: test-file compiles, path aliases, missing exports) and ~439
  dev-real build breakages are documented follow-up work.
- **Jest timeout in `@opencrvs/config` (`updateFormDraftHandler`):** 5000ms async
  timeout in `updateFormDraftHandler handler › should update question using mongoose`
  on commit `1648707415_2909a538f6dd...`. Originally classified as a transient
  CPU-saturation flake (1 run archived to
  [`archive/config_mongoose_jest_timeout/`](archive/config_mongoose_jest_timeout/)),
  but four re-runs (2026-11-01/02, the last on an almost idle host) reproduced it
  every time: the whole `updateFormDraft` suite takes 11.4 s and this mongoose
  test sits at/over the 5 s jest budget at that commit. Coverage remains valid
  (soft failure); accepted as a known gap (see below) rather than raising jest
  timeouts.

## Known gaps

- **Postinstall hook** (`node development-environment/link-ts6-api.js`): left to
  run; it may fail in the container if it expects specific paths.
- **April 2022 `config` test hang timeouts:** 3 consecutive commits (`1650709773`,
  `1650719343`, `1650719806`) time out after 5400s (90m) during
  `formDraft/createOrupdateFormDraft/handler.test.ts`.
- **`updateFormDraftHandler` 5000ms timeout at `1648707415` (Apr 2022):** the
  single remaining `problematic` fingerprint (`701263588408`). Reproduces on
  every re-run (**4/4**, 2026-11-01/02 — the fourth on an almost idle host,
  load ≈ 6/256 cores, so **not load-induced**): the `updateFormDraft` suite runs
  11.4 s and this mongoose updateQuestion test deterministically exceeds jest's
  5 s async budget at this commit. Coverage is valid (soft failure, 12 lcov
  files); the flaky test signal is accepted and the label kept `problematic` so
  a genuine regression still resurfaces.