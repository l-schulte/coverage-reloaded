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
- [stalled] complete run (26 commits archived awaiting re-run when machine capacity frees up)
- [x] complete test failure check (100% of failure fingerprints labeled in v2 database)
- [ ] complete JEV test failure check (not started)

## Results

Source: `stats_output/report.txt` (generated 2026-10-21 21:52).

| Metric | Value |
|---|---|
| Commits processed | 11698 |
| Without test failures | 4011 |
| With test failures | 6685 |
| Not applicable | 0 |
| Hard errors | 1002 |
| Coverage produced | 91.4% |
| Commits not yet processed | 26 |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py opencrvs-core --stats` (window `min`, run 2026-10-21) and
`stats_output/report.txt` (generated 2026-10-21 21:52). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 6685 |
| Failing runs (label DB) | 6684 |
| Fingerprints (min / max) | 4337 / 6155 |
| Labeled fingerprints | 4337 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 3606 |
| reevaluated_acceptable | 558 |
| problematic | 127 |
| unclear | 0 |
| false_positive | 46 |
| Manual / auto-propagated labels | 76 / 4261 |
| Labeled detections (min) | 49459/49459 (100.0%) |
| Labeled runs (min) | 6684/6684 (100.0%) |
| Jev mode | n/a |
| Jev pipeline issues | n/a |
| Jev audit | n/a |

**State:** complete (stale by 1 run against `report.txt`; re-run `python check_failures_v2.py opencrvs-core --build --window both` to sync DB with post-archive output).

| Label | Suite | Signature / Root Cause | Rule / Fingerprints | First..Last Run | Runs (Union) |
|---|---|---|---|---|:---:|
| `problematic` | `gateway` / `auth` | Docker Hub 502 Bad Gateway during `redis:5` pull | `2b917bf380fc` (40 fps) | 2024-06..2025-12 | 8 |
| `problematic` | `gateway` / `auth` | DinD Redis startup hook timeout (> 30s) | `6e90b25dc3c3` (38 fps) | 2024-08..2024-09 | 4 |
| `problematic` | `gateway` / `auth` | Missing DinD image `redis:5` | `1be1c22e152d` (36 fps) | 2024-09 | 1 |
| `problematic` | `search` | DinD socket drop (`No Docker client strategy found`) | `f4c49fa7ba0d` (2 fps) | 2025-03..2025-10 | 5 |
| `problematic` | `gateway` | Docker Hub rate limit deadline exceeded (`redis:5`) | `7659d5eac4e8` (2 fps) | 2024-03 | 2 |
| `problematic` | `gateway` | DinD Redis connection stall (`flushall` undefined / 30s timeout) | `4dba89ac8cd8` & `9b955853` (3 fps) | 2024-03..2024-05 | 2 |
| `problematic` | `search` | Missing DinD image `elasticsearch:8.14.3` | `55b559175c2d` (1 fps) | 2025-02..2025-03 | 2 |
| `problematic` | `config` / `metrics` / `client` | Transient Jest 5s/30s CPU saturation timeout flakes | `701263588408`, `43987c8a`, `2a735564` (3 fps) | 2022-03..2024-05 | 2 |
| `problematic` | `gateway` | DinD container start failures | `edc61877`, `4c9f96b1` (2 fps) | 2024-09..2025-03 | 2 |

*Note: All 26 runs affected by these problematic infrastructure/flake issues have been archived into [`projects/opencrvs-core/archive/`](archive/) to be cleanly re-run once capacity frees up.*

## Environment / setup fixes

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

## Known gaps

- **Postinstall hook** (`node development-environment/link-ts6-api.js`): left to
  run; it may fail in the container if it expects specific paths.
- **April 2022 `config` test hang timeouts:** 3 consecutive commits (`1650709773`,
  `1650719343`, `1650719806`) time out after 5400s (90m) during
  `formDraft/createOrupdateFormDraft/handler.test.ts`.