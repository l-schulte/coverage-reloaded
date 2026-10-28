# babel

**Repository:** https://github.com/babel/babel
**Status:** active

## Test infrastructure

- **Package manager:** Yarn Berry, 2.4.0 through 4.x, selected by the bundled
  `.yarn/releases` file referenced from `.yarnrc.yml` (see
  [`config.json`](../../config.json) → `babel`).
- **Node strategy:** `use_exact_node_version` is enabled. CircleCI-sourced
  commits use the exact `cimg/node` versions in their config (`20.5`, `21.7`,
  `22.1`, `22.4.1`, `22.10`); other commits use major versions from
  `package.json` or the release-date LTS fallback. Timestamp overrides raise
  Node 16 to 18 for 2023-11-14 – 2024-01-19 (Yarn 4) and Node 20 to 22 from
  2025-09-05 (`asserts.ts` type-stripping build; this also covers the later
  `Gulpfile.mts` build).
- **Runners:** Jest, with `jest-light-runner` from 2021-09 onward.
- **Eras:**
  - 2021-01-01 – 2022-09-20: `babel-plugin-istanbul` instruments the build;
    coverage is produced by `jest --coverage`.
  - 2022-09-21 – 2026-01-01: coverage is produced by `c8` using `.c8rc`.
  - `make bootstrap` installs dependencies, generates TypeScript configuration,
    and builds `src` into `lib` before either coverage command.
- **Package-manager correction:** `package_manager_skip_engines` is enabled
  because `engines.yarn` contains the range `>=1.4.0`, which was previously read
  as `yarn@1.4.0`. A timestamp override pins the pre-`packageManager` commits
  (through 2021-09-16) to `yarn@2.4.0`.

## Development style

- **PR merging strategy:** Squash and merge (84.1% of 3035 first-parent commits,
  2021-01-01 – 2026-01-01).
- **Merge convention:** `<Title> (#<PR>)`.
- **Direct commits:** 15.9% of first-parent commits are not squash merges;
  14.2% of all first-parent commits are release, changelog, version-bump, or
  materialize bookkeeping.
- **JS/TS code impact of direct commits:** 16 commits (0.5% of all first-parent
  commits) touch JavaScript or TypeScript outside release bookkeeping; the
  remainder are release operations, fixture updates, or lint fixes.
- **Issue tracking discipline:** High for feature work, which is PR-gated.
  Direct commits are release or operational changes.
- **Workflow notes:** Feature work lands through squash-merged pull requests on
  `main`. Releases are tagged directly on `main`. The repository also contains
  ancestry from the merged `facebook/regenerator` history.

## Coverage collection

- **Suites collected:**
  - `unit`: Jest over `packages/*/test`, `codemods/*/test`, and
    `eslint/*/test`. This includes Babel's integration-style CLI, register,
    node, core-transform, preset, and ESLint tests.
- **Suites excluded:**
  - `test:esm`: package `exports` and ESM module-resolution smoke test. It
    imports `@babel/runtime/helpers/wrapNativeSuper` and the corejs3 equivalent,
    which loads six generated helper modules (`wrapNativeSuper`, `getPrototypeOf`,
    `setPrototypeOf`, `isNativeFunction`, `construct`, `isNativeReflectConstruct`);
    the helper bodies are not called. The executed files are generated, are not
    committed (`helpers/*.js` is gitignored), and carry no source maps.
  - `test:runtime:node` and `test:runtime:bundlers`: execute generated runtime
    helpers (`objectWithoutProperties`, `inheritsLoose`, and the core-js-pure
    `Set` wrapper) in Node, webpack 3/4/5, and Rollup. The executed files are
    generated and have no source maps.
  - `test-flow`, `test-typescript`, and `test-test262`: external parser corpora.
    They exercise `packages/babel-parser/lib` but require cloning external
    repositories and use allowlists. They are not collected in the prototype;
    the parser is covered by the Jest suite.
  - E2E workflows (`e2e-tests*.yml`, the CircleCI e2e jobs, and
    `scripts/integration-tests/e2e-*.sh`): they publish Babel and run downstream
    applications. They provide no source-line attribution.
- **Coverage tool / config:** Jest/istanbul before 2022-09-21; `c8` with
  `.c8rc` from 2022-09-21 onward.
- **Coverage invocation:** c8 era uses the project's `make test-ci-coverage`
  target (bootstrap, then `BABEL_COVERAGE=true yarn c8 jest`), invoked with
  `YARN=/coverage_reloaded/yarn-workers-shim`; the shim caps the target's
  hardcoded `--maxWorkers=100%` at `BABEL_JEST_WORKERS` (default 2). Istanbul
  era uses the same target's steps (`BABEL_COVERAGE=true make bootstrap`, then
  `TEST_TYPE=cov ./scripts/test-cov.sh`) plus `make build-standalone`: the
  Istanbul target skips the standalone bundle while its Jest config does not
  ignore the unbuilt standalone tests. Istanbul keeps the project's 4-worker
  setting.
- **Coverage environment:** `FORCE_COLOR=true` (the Makefile exports it only to
  make recipes) and `BROWSERSLIST_IGNORE_OLD_DATA=true` (wall-clock runs would
  otherwise emit stale caniuse-lite warnings). The
  `browserslist-child-env.cjs` preload also injects the Browserslist flag into
  sanitized child spawns. The coverage run drops `cap_dac_override` and
  `cap_dac_read_search` with `setpriv`, so `babel-register/test/cache.js` sees
  real file-mode failures.
- **LCOV production:** the active runner writes `coverage/lcov.info`, which
  `find-and-move-lcov.sh` moves with `PREPEND_PATHS=false`.

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (100-sample logs reviewed)
- [ ] complete run (3057 commits not yet processed)
- [ ] complete test failure check (no v2 labels)
- [ ] complete JEV test failure check (no Jev CSV)

## Results

Source: [`stats_output/report.txt`](stats_output/report.txt) (generated 2026-10-28 18:12).

| Metric | Value |
|---|---|
| Commits processed | 104 |
| Without test failures | 63 |
| With test failures | 36 |
| Not applicable | 5 |
| Hard errors | 0 |
| Coverage produced | 100.0% |

3057 commits not yet processed; the complete run is pending.

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

State: not started. `stats_output/report.txt` reports 36 failing runs. No v2
label artifacts exist yet (`failure_labels_project_min.csv` is absent).

## Environment / setup fixes

- [`config.json`](../../config.json) → `babel`: enabled
  `package_manager_skip_engines` and added a package-manager override that maps
  the bare `yarn` fallback to `yarn@2.4.0` through 2021-09-16. Without this,
  640 commits are misdetected as `yarn@1.4.0` and cannot install the Yarn Berry
  lockfile.
- [`config.json`](../../config.json) → `babel`: added a Node override that maps
  Node 16 to 18 for 2023-11-14 – 2024-01-19, where Yarn 4 requires Node 18 or
  newer.
- [`config.json`](../../config.json) → `babel`: enabled
  `use_exact_node_version` so the 172 CircleCI-sourced commits use the exact
  Node minor their CI used, and added an override that maps Node 20 to 22 from
  2025-09-05 onward. The boundary is the commit that added
  `packages/babel-types/scripts/generators/asserts.ts` (type-stripping build);
  it also covers the later `Gulpfile.mts` failure.
- `install-and-run.sh`: delegates coverage to the project's own targets:
  `make test-ci-coverage` in the c8 era; in the Istanbul era,
  `BABEL_COVERAGE=true make bootstrap`, `make build-standalone`, then
  `TEST_TYPE=cov ./scripts/test-cov.sh`. It exports `FORCE_COLOR`,
  `BROWSERSLIST_IGNORE_OLD_DATA`, and `BABEL_JEST_WORKERS` (default 2); the c8
  target's `--maxWorkers=100%` is rewritten by `yarn-workers-shim`. The
  `NODE_OPTIONS` preload `browserslist-child-env.cjs` propagates
  `BROWSERSLIST_IGNORE_OLD_DATA` into sanitized child spawns. It drops
  `cap_dac_override` / `cap_dac_read_search` with `setpriv` around the coverage
  run so `babel-register/test/cache.js` exercises its read/write failure cases.

Prototype validation (2026-10-28): eleven commits spanning 2020-12 to 2025-12
(Node 12.22.12, 14.21.3, 20.5.1, 21.7.3, 22.1.0, 22.10, and 22) completed with
exit 0 and `src`-path LCOV. This includes the 2025-09-05 boundary commit
`092d2e20`, the former hard failure `1a689094`, and the revalidated
`7965c155` / `a943f576`.

## Known gaps

- 126 commits (4.0%) are merged `facebook/regenerator` ancestry with no Babel
  root `package.json`; `install-and-run.sh` marks them `not_applicable`. If
  `not_applicable` counts in the denominator, the 90% criterion requires 2845
  passing commits out of the 3035 Babel commits (93.7%).
- `test:esm` and the runtime-interop suites are intentionally not collected:
  they execute generated artifacts without source maps.
- The external parser corpora are deferred. Including them later would add
  parser-only coverage at substantial clone, runtime, and allowlist cost.
- LCOV `SF:` paths are `src` paths in the sampled pre-c8 and c8 commits; this
  must also hold for the full run.
- Jest/istanbul before 2022-09-21 likely does not capture CLI child-process
  coverage; c8 captures it from 2022-09-21. This scope change must be verified.
- Most 2021–2025 commits resolve their Node version from the release-date LTS
  fallback because the shared GitHub Actions strategy does not read Babel's
  `.github/workflows/ci.yml`. The project overrides cover Yarn 4, `asserts.ts`,
  and `Gulpfile.mts`; a general fix would extend the shared strategy to generic
  `ci.yml` workflows.

## Known test failures

- `7896ed74` (2025-06-29): `sourceType-commonjs` parser fixtures for
  `es2026/...` fail because the test blockList still names `experimental/...`;
  the later commit `5e7cb54304` fixes the paths. Developer-facing; not fixed
  here.
- `9421fa14`, `e54bc6b8`, `95417784` (2022-02 – 2022-04): the `babel-cli` watch
  test times out (`EXECUTOR TIMEOUT`). Timing/flaky in the container; not fixed
  here.
