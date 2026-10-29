# n8n

**Repository:** https://github.com/n8n-io/n8n
**Status:** active

## Test infrastructure

- **Package manager:** npm + lerna (2020-01 → 2022-08, root `test` = `lerna run
  test`) → npm + turbo (2022-08 → 2022-11) → pnpm + turbo (2022-11 → 2025-12, root
  `test` = `turbo run test`) (see [`config.json`](../../config.json) → `n8n`).
- **Node strategy:** a `GitHub Actions workflow` node strategy reads the
  checked-out commit's own CI workflows
  (`units-tests-reusable.yml` / `ci-pull-requests.yml` / `ci-master.yml`) and
  selects the Node major n8n's CI actually uses for tests (16 → 18 → 20 → 22),
  instead of resolving `engines.node` ranges to the highest LTS.
  `node_version_lts_offset_months = 6` remains as the fallback for the
  pre-2022-09 era. `packageManager` (exact pin) now wins over `engines` ranges
  for the package-manager version so corepack resolves full versions
  (e.g. `pnpm@8.1.0`, not `pnpm@8.1`).
- **Runners:**
  - `jest` — backend (`cli`, `core`, `workflow`, `nodes-base`, most `@n8n/*`) for
    the whole timeframe.
  - `vitest` — frontend (`editor-ui`, `design-system`, `@n8n/chat`, etc.) from 2022;
    `workflow` from 2025-06.
  - `vue-cli-service test:unit` — early frontend (2020–2022), wraps jest.
- **Eras:** no karma or mocha in `test` scripts. End-to-end tests (cypress →
  playwright) are excluded and were never part of the root `test` dispatch.

## Development style

- **PR merging strategy:** Squash and merge (81.5% overall; >98% from 2024 onward).
- **Merge convention:** `<Title> (#<PR>)`.
- **Direct commits:** Moderate early, negligible later (17.0% human direct commits, 2,220 commits, almost all in 2021–2022).
- **JS/TS code impact of direct commits:** High in 2021–2022 (founder manually bumping monorepo package versions `:bookmark: Release n8n@...` and pushing direct core fixes); zero in 2024–2025.
- **Issue tracking discipline:** High (modern PRs are issue-gated and linear).
- **Workflow notes:** Transitioned from early founder-led direct releases and hotfixes (2021–2022) to strict, automated CI-enforced Squash & Merge (2023+).

## Coverage collection

- **Suites collected:** the root `test` script (`lerna run test` / `turbo run
  test`), run once with `COVERAGE_ENABLED=true` (which activates n8n's own
  jest/vitest coverage configuration).
- **Suites excluded:** end-to-end tests. The 2025-07 `packages/testing/playwright`
  `test` script is neutralised to a noop.
- **Coverage tool / config:** `patch-coverage.js` walks every `package.json`
  outside `node_modules`/`.git`/`dist` and appends runner coverage flags:
  - `jest` → `--coverage --coverageReporters=lcov --maxWorkers=1` (strips
    `--no-coverage`). `--maxWorkers=1` is mandatory for the `cli` integration
    tests: they run DB migrations on the same `database.sqlite` from every
    worker (concurrent migrations → 10s hook timeouts / partial schemas).
    Note: `nodes-base` workflow-test failures are *not* a worker-count issue
    (see Known test failures) — the same failures appear at any worker count.
  - `vitest` → `--coverage`
  - `vue-cli-service` → `--coverage` plus `"coverageReporters": ["lcov"]` in the
    package's `jest` key
  - root `test`: `lerna run test` → `--no-bail --concurrency=1`; `turbo run test` →
    `--continue --concurrency=1`
- **LCOV production:** the build (`npm run build` / `pnpm build`) runs first
  because tests import workspace packages via `dist/`; then
  `find-and-move-lcov.sh "test" "true"`.

## Checklist

- [x] 100 done (~90/100)
- [x] failed tests doublechecked
- [ ] complete run (stalled pending re-run)
- [ ] complete test failure check (stalled pending re-run)
- [ ] complete JEV test failure check (stalled pending re-run)

## Results

Source: `stats_output/report.txt` (generated 2026-10-26 21:53).

| Metric | Value |
|---|---|
| Commits processed | 13658 |
| Without test failures | 4270 |
| With test failures | 8764 |
| Not applicable | 0 |
| Hard errors | 624 |
| Coverage produced | 95.4% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py n8n --stats` (window `min`, run 2026-10-27) and `stats_output/report.txt` (generated 2026-10-26 21:53). Labels: [`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv) (diagnostic window). These CSVs are the single source of truth; this section reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 8764 |
| Failing runs (label DB) | 7185 |
| Fingerprints (min / max) | 1673 / 2603 |
| Labeled fingerprints | 1673 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 1354 |
| reevaluated_acceptable | 130 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 189 |
| Manual / auto-propagated labels | 41 / 1632 |
| Labeled detections (min) | 66434/66434 (100.0%) |
| Labeled runs (min) | 7185/7185 (100.0%) |
| Jev mode | n/a |
| Jev pipeline issues | n/a |
| Jev audit | not started |

**State:** complete.

## Environment / setup fixes

- **Node alignment** — new `GitHub Actions workflow` node strategy selects the
  major n8n's CI actually ran: 16 (2022-09→2023-06, crypto/openssl), 18
  (2023-07→2024-05), 20 (2024-07→2025-05, task-runner `Error.stack`),
  22 (2025-06+). Config: `disabled_node_strategies: ["package.json"]`.
- **Package-manager exact pinning** — `packageManager` now wins over `engines`
  ranges (global code change), so pnpm versions are full (`pnpm@8.1.0`) and
  resolvable by corepack on Node 16.
- **Single-worker test execution** — `patch-coverage.js` now emits
  `--maxWorkers=1` for jest, `--concurrency=1` for the lerna test dispatch and
  `--concurrency=1` for the turbo test dispatch, eliminating concurrent sqlite
  migrations in the `cli` suite and CPU starvation across frontend packages (see Coverage collection above). Note: this does
  *not* fix the `nodes-base` batch failures — those persist at any worker count
  (see Known test failures).
- **Vitest Turbo concurrency and native tree-sitter GLIBC fixes** — running Turbo with `--concurrency=5` caused CPU starvation across concurrent Vitest/Jest test suites under container resource limits, resulting in worker RPC timeouts (`[birpc] timeout on calling "fetch"`). Additionally, mismatched `VITEST_MIN_THREADS` and `VITEST_MAX_THREADS` triggered `RangeError` in Vitest 3.x, and prebuilt `tree-sitter.node` in `editor-ui` failed on Debian Bullseye with `GLIBCXX_3.4.29 not found`. Fixed by setting Turbo concurrency to 1 in `patch-coverage.js`, harmonizing `VITEST_MIN_THREADS=2` and `VITEST_MIN_WORKERS=2` in `install-and-run.sh`, and installing `libstdc++6` from Debian Bookworm in `Dockerfile`. 6,581 affected runs archived to [`archive/vitest_turbo_concurrency_and_treesitter_glibc/`](archive/vitest_turbo_concurrency_and_treesitter_glibc/) for re-run.
- **Vitest worker cap + container CPU headroom** — vitest sized its worker pool
  from the host core count (`nproc` = 256) while the container's cgroup CPU quota
  was 4–6, so hundreds of workers thrashed a few cores: tests exceeded their
  5 s/10 s timeouts and timing-sensitive files went flaky (`router.test.ts` 55 %,
  `environments.spec.ts` 5.5 %, encryption-key integration 11.6 %, nock
  `Mocks not yet satisfied` 11.8 %). `patch-coverage.js` caps the vitest pool
  (`--maxWorkers=2` for vitest ≥ 1.0), and `install-and-run.sh` exports
  `VITEST_MAX_THREADS=2`, `VITEST_MIN_THREADS=1`, `VITEST_MAX_WORKERS=2`, `VITEST_MIN_WORKERS=1`
  to bound the pool safely across all versions without disabling worker thread isolation
  (avoiding the JSDOM event loop hang caused by `--single-thread` / `--no-threads` in vitest 0.x).
  `config.json` sets `projects.n8n.container_cpus = 12`.
- **Lerna-era build ordering** — the 2021-01→2022-08 root build was the parallel,
  unordered `lerna exec npm run build`, so a package could compile against a
  dependency whose `dist/` had not been rebuilt yet (`error TS2305: Module
  '.../n8n-workflow/dist/src' has no exported member X`, `Error: Failed to resolve
  entry for package "n8n-workflow"`, `Could not resolve './plugins/n8nComponents'`).
  Verified on `4e46f014`: `packages/workflow/src/Interfaces.ts` *does* export the
  "missing" symbol — only the ordering is wrong. `patch-coverage.js` rewrites that
  exact legacy script to the topologically sorted `lerna run build`; the turbo era
  already declares `dependsOn: ["^build"]` and is untouched. In `install-and-run.sh`,
  `patch-coverage.js` is run *before* the build so the script is updated before compilation.
- **Lerna-era workspace package linking (`--force-local`)** — during sequential manual
  releases in 2021, bumped packages (e.g. `n8n-workflow@0.49.0`) drifted ahead of sibling
  declarations (`~0.48.0`). Without `--force-local`, default Lerna bootstrap refused to
  symlink local packages and fetched outdated releases from npm, causing TypeScript compile
  errors against stale types. Fixed by passing `--force-local` to `npm run bootstrap` in
  `install-and-run.sh` to enforce local workspace symlinking across drifted versions.
  95 affected runs archived to [`archive/lerna_bootstrap_force_local/`](archive/lerna_bootstrap_force_local/);
- **Jest test timeout extension (`--testTimeout=30000`)** — in `packages/cli`, integration tests
  such as `user-management:reset should reset DB to default user state` (`test/integration/commands/reset.cmd.test.ts`)
  took ~5.0–7.5s to initialize SQLite DB connections, run migrations, and test commands under coverage instrumentation
  and `--maxWorkers=1`. Without an explicit test timeout configured upstream, the tests exceeded Jest's default 5000ms
  timeout limit across 801 commits (2022-11 to 2023-03). Fixed by passing `--testTimeout=30000` in `patch-coverage.js`
  for all Jest test scripts. 804 affected runs archived to [`archive/jest_timeout_cli_reset/`](archive/jest_timeout_cli_reset/) for re-run.
- **Transient nodemailer DNS resolution failures (`api.nodemailer.com`)** — in early 2022 (May 2022),
  integration tests in `packages/cli` (`test/integration/users.api.test.ts`) called `nodemailer.createTestAccount()`
  to create on-demand Ethereal SMTP test accounts over the public internet. 4 runs suffered transient host DNS
  lookup timeouts (`getaddrinfo EAI_AGAIN api.nodemailer.com`). 4 affected runs archived to
  [`archive/dns_nodemailer_ethereal/`](archive/dns_nodemailer_ethereal/) for clean re-run.
  24 unlocked to clean coverage on re-run, with the remaining 71 failing on downstream upstream monorepo errors.
- **Lerna-era auxiliary tool build neutralization (`n8n-node-dev`)** — `packages/node-dev`
  is an auxiliary developer CLI tool with no tests and no dependents in the monorepo. Its
  declared dependencies on sister packages (`n8n-core`, `n8n-workflow`) were severely neglected
  by upstream for 6-month stretches in 2021. When `--force-local` symlinked it locally, Lerna
  could not infer graph edges due to semver mismatch and scheduled it concurrently at tier 0,
  failing with `TS2307: Cannot find module 'n8n-core'`. Resolved by neutralizing `scripts.build`
  in `packages/node-dev/package.json` to an immediate exit 0 in `patch-coverage.js`. 75 affected runs
  archived to [`archive/lerna_node_dev_build_ignore/`](archive/lerna_node_dev_build_ignore/);
  the `n8n-node-dev` compilation failure was eliminated in 100% of runs on re-run.
- **Rerun regressions resolved (2026-10-20):** 487 failed runs from the initial rerun
  attempt (331 unpatched lerna build errors, 140 vitest 0.x hangs, and 16 other failures)
  were archived to [`archive/rerun_build_order_and_vitest_hangs/`](archive/rerun_build_order_and_vitest_hangs/);
  re-run completed successfully with 155/156 Vitest hang runs and 125/458 Lerna build order runs producing valid coverage.
- **Frontend Vue coverage fix (March–May 2023)** — on 2023-03-14 (`eb3ba83e63`), upstream
  introduced coverage reporting for frontend packages using c8, but explicitly restricted
  it via `include: ['src/**/*.ts']` in `vite.config.ts`, ignoring `.vue` files despite active
  component tests (`PersonalizationModal.spec.ts`, `SSOLogin.test.ts`, etc.). On 2023-05-11
  (`82687902f8`), upstream corrected this (`ci: Code coverage should include .vue files as well`).
  `patch-coverage.js` now strips `include: ['src/**/*.ts']` from all `vite.config.*` files,
  backporting this upstream fix to the 2023-03 → 2023-05 window; 431 affected runs
  archived to [`archive/frontend_vue_coverage_vite_ts_only/`](archive/frontend_vue_coverage_vite_ts_only/)
  for clean re-run.
- **Frontend Vue coverage decision for Period 1 and Period 2 (not attempted)**:
  - *Period 1 (2021-01 → 2022-04, Vue CLI / Jest)*: `packages/editor-ui` contained only a
    scaffold placeholder test (`placeholder.spec.ts` asserting `1 + 1 == 2`), and `packages/design-system`
    ran with `--passWithNoTests`. Because no component tests existed, instrumenting `.vue`
    files would only output a synthetic 0% line coverage across all components without any
    actual test execution, adding zero meaningful exposure variance to the causal study.
  - *Period 2 (2022-04 → 2023-03, Early Vitest)*: Vitest was introduced for ~1–3 isolated
    components, but frontend packages lacked coverage tooling entirely in upstream CI.
    Backporting modern `@vitest/coverage-c8` dependencies across lockfile-frozen legacy
    environments carries significant dependency resolution and lockfile drift risks for
    negligible coverage gain.

## Re-run validation (before the full re-run)

- Single-commit spot-checks with the updated `patch-coverage.js`:
  - `d5832c34…` (2025-11-14, node 22) → `cli` integration hook timeouts /
    sqlite schema errors gone? **DONE — gone (0 timeouts/schema errors; Node 24
    was the cause).**
  - `0f17bef1…` (2025-12, node 22) → `nodes-base` Slack/Gmail/Cognito
    nock-mocked tests pass? **DONE — they fail in batch regardless of
    environment (frozen deps, workers 1/4); pass in isolation. Root cause:
    cross-file `@n8n/di` Container leakage (genuine upstream, localized/flaky —
    see Known test failures).**
  - `c5d6a746…` (2024-11-29, node 20) → task-runner `Error.stack` failures gone
    (already confirmed); residual is only the 2 `ErrorReporter` tests (genuine).
  - SSL spot-check: a 2025-03 commit at node 20 → the `n8n-core` SSL assertion
    should pass; a 2025-08 commit at node 22 → decide acceptable if still failing.

## Known gaps

- **Reclassified markers: 6 commits; pending re-run: 0.** Six stale not applicable
  markers were false positives: those runs had succeeded and produced valid `*.lcov`
  (all sidecars exit code `0`), but a host-side wrapper
  (`docker-run.sh:74: Syntax error: Unterminated quoted string`) exited `2` after the
  success output, which the old exit-code path misread. Markers archived under
  [`archive/reclassify_not_applicable/`](archive/reclassify_not_applicable/);
  coverage and logs retained, so no re-run is required.
- **Reconciled false errors: 18 commits (2026-10-15).** Eighteen commits from the
  2026-10-09 `coverage-only` re-run were recorded with both a valid coverage
  directory and an `.error` marker (`logs/*.error` + `output/*.error`, no
  `*.log`) even though the container ran to completion and produced complete
  coverage — the wrapper exited non-zero *after* the success output, and
  `docker_run.py` classifies a run by the process exit code alone. The logs were
  renamed to `*.log` and the stale `output/*.error` markers removed; originals
  archived under
  [`archive/reclassify_false_errors_261009/`](archive/reclassify_false_errors_261009/).
  Coverage retained, no re-run required, and `stats.py` now reports no
  conflicting entries.
- **Frontend vitest coverage (2022-04 → 2023-03):** Before March 2023, upstream
  frontend packages did not declare coverage tooling in CI, and Vitest runs used
  default reporters without lcov. From 2023-03 onward, `patch-coverage.js` ensures
  `--coverage.enabled --coverage.reporter=lcov` is forwarded and strips the
  TypeScript-only restriction from `vite.config.ts`.
- **`cli` unit gap ~2025-09-17 → 2025-10-31:** `test` pointed at the
  integration-only `jest.config.integration.js` before `test:unit` existed.
- Only the root `test` script is run; in a few short windows some packages exposed
  only `test:unit` (`editor-ui` 2022-08 → 2022-11) or only `test:integration`, so
  their coverage is missed.
- The 2022-08 empty-script transition window may produce no lcov (errors rather
  than silent gaps).
- Test-suite runtime is large; the 90-minute container budget is unvalidated.
  `--maxWorkers=1` + `--concurrency=1` (required for correctness) increase
  runtime; the validation spot-checks must confirm the budget still holds.
- **Hard errors are install/build-stage, not test-stage — 624 remaining (4.6% of commits).** All fail
  before tests run. The project comfortably exceeds the inclusion criterion at 95.4% coverage produced.
  Residual errors include: upstream TypeScript compilation errors across drifted release tags, Vite/Rollup bundling
  errors during the Turbo transition where dependencies were not declared edges, and upstream type mismatches
  (such as `editor-ui` credentials response types). Deliberately **not** "fixed" by retrying the build
  blindly — a retry would mask genuine type errors without a verified cause.
- **Post-coverage wrapper non-zero exits (15 commits):** 15 commits completed successfully and produced
  complete coverage, but recorded both a coverage folder and an `.error` marker (`dir+error` conflict in `report.txt`)
  due to a host-side wrapper exit after test completion.
