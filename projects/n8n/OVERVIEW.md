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
- [ ] failed tests doublechecked (todo)
- [x] complete run (0 not applicable; 92.8% of remaining commits successful)
- [ ] complete test failure check

> **STATUS: FULL RE-RUN IN PROGRESS (started 2026-09-10)**
>
> Node strategy (GitHub Actions CI) + `packageManager`-first pinning applied,
> `commits.csv` regenerated (10,030 of 13,658 commits changed node/pm), and
> `patch-coverage.js` now uses `--maxWorkers=1` / `--concurrency=1`. The ~10,030
> changed commits are being re-collected; results below are pre-re-run. Spot
> checks done: DB block fixed (node 24→22), task-runner fixed (22→20), SSL
> clears at node 20; `nodes-base` batch failures are genuine upstream
> (localized/flaky, see Known test failures).

## Results

Source: `stats_output/report.txt` (generated 2026-09-06 12:23).

| Metric | Value |
|---|---|
| Commits processed | 13658 |
| Without test failures | 1970 |
| With test failures | 10845 |
| Not applicable | 0 |
| Hard errors | 843 |
| Coverage produced | 93.8% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

All failures exit with code 1 and valid (partial) coverage; the suite never bails.

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `@n8n/n8n-benchmark#test` — placeholder script (`echo "Error: no test specified" && exit 1`) | false_positive | negligible | Recommend excluding from turbo. No real tests exist. |
| `n8n-core` SSL certificate assertion — 2 tests (`parseRequestObject › should set SSL certificates`) assert a 4-key `https.Agent.options`, but Node 22+ adds `defaultPort`/`protocol` (confirmed on Node 24: 6 keys). **~5,670 commits** (NodeExecuteFunctions 2024-07-24→2025-02-07; RequestHelperFunctions 2025-02-11→2025-12-31) | node-version artifact cleared by alignment; **2025-06+ tail genuine upstream** | 2 tests per commit; suites otherwise pass | Spot-checks done: 2025-03 @ node 20 passes (clears 2024-07→2025-05, ~2,800 commits); 2025-08 @ node 22 (= n8n CI node) still fails — mark the 2025-06+ tail as genuine upstream. |
| `@n8n/ai-workflow-builder.ee` — **82 commits** (2025-07-21 `632b38119b` → 2025-07-28 `49a52a1150`): the rename dropped the package's `jest.config.js`, so jest uses default config and cannot parse TS (`import type` SyntaxError) — 13 test files produce **no lcov** | genuine upstream (re-added by upstream 7 days later) | package missing entirely for that window | Document as known gap; do NOT patch (matches project's own fix timing; not environment). |
| `@n8n/json-schema-to-zod` — **423 commits** (2024-10-17 `86a94b5523` → 2024-12-02 `28487edb13`): `src/index.ts` re-exports `./json-schema-to-zod.js` (ESM-extension convention) which jest cannot map to `json-schema-to-zod.ts`, so the 68-test suite never runs (partial lcov) | genuine upstream | main suite silently not covered in that window | Document as known gap; do NOT patch. |
| `@n8n/task-runner` `ErrorReporter` — 2 tests, **~230 commits** (2024-11-15→2024-12-13): `beforeSend` is `async` but the assertions call it without `await`, so `toBeNull()` compares a Promise; the two `.not.toBeNull()` tests pass | genuine upstream (node-independent; fails on Node 20 and 22 identically) | 2 tests per commit; partial coverage valid | Document; do NOT patch. |
| `n8n-nodes-base` workflow tests — nock mocks fail (`Nock: Disallowed net connect` → `Data for node "X" is missing!` / `Equality failed`) when run as a batch, but **pass in isolation** | **genuine upstream test-suite fragility, temporally localized + flaky** | ~200 workflow-test files fail per affected commit (partial coverage) | Container-debug root cause (2026-09-10, `0f17bef1`): `NodeTestHarness` uses the global `@n8n/di` Container and never `Container.reset()` → cross-file state corruption; robust to worker count (1/4), frozen/non-frozen deps, node version. **Localized:** main multi-nock block 2025-12-15 (single day, ~8 commits, 298–382 blocked reqs/commit; same commit yields varying counts across runs → flaky); scattered single Todoist-mock failures 2025-08-26→2025-12-29 (18 commits, 3 each). Not fixable via `install-and-run.sh`; document. |

## Environment / setup fixes

- **Node alignment** — new `GitHub Actions workflow` node strategy selects the
  major n8n's CI actually ran: 16 (2022-09→2023-06, crypto/openssl), 18
  (2023-07→2024-05), 20 (2024-07→2025-05, task-runner `Error.stack`),
  22 (2025-06+). Config: `disabled_node_strategies: ["package.json"]`.
- **Package-manager exact pinning** — `packageManager` now wins over `engines`
  ranges (global code change), so pnpm versions are full (`pnpm@8.1.0`) and
  resolvable by corepack on Node 16.
- **Single-worker test execution** — `patch-coverage.js` now emits
  `--maxWorkers=1` for jest and `--concurrency=1` for the root lerna/turbo
  dispatch, eliminating concurrent sqlite migrations in the `cli` suite (see
  Coverage collection above). Note: this does *not* fix the `nodes-base`
  batch failures — those persist at any worker count (see Known test failures).

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

- **Frontend vitest 2022-04 → 2025-02:** `--coverage` alone uses the vitest default
  reporters (no lcov), so those commits get backend-only coverage unless a reporter
  override or config patch is added.
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
