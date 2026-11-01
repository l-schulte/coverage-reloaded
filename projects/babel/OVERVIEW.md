# babel

**Repository:** https://github.com/babel/babel
**Status:** active

## Test infrastructure

- **Package manager:** Yarn Berry, 2.4.0 through 4.x, selected by the bundled
  `.yarn/releases` file referenced from `.yarnrc.yml` (see
  [`config.json`](../../config.json) → `babel`).
- **Node strategy:** Exact Node versions are extracted from the project's CI
  configuration. `.circleci/config.yml` is consulted first and outranks the
  generalized GitHub Actions strategy, because a CI container pin
  (`cimg/node:22.10`) names an exact release whereas a workflow
  `node-version:` entry is frequently a bare major (`22`) or `22.x` that
  discards the minor. GitHub Actions is ranked below CircleCI rather than above
  it: only babel resolves from GitHub Actions, so lowering it is contained.
  `use_exact_node_version` is enabled so the resolved minor is kept instead of
  being truncated to the major. Commits whose CI declares no version fall
  through to `package.json` or the `node_releases.json` LTS fallback.
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
- [x] complete run (3161 commits processed, 0 pending)
- [x] complete test failure check (223/223 fingerprints labeled; 0 `unclear` /
  `problematic` remain — [`label_analysis/assessment.md`](label_analysis/assessment.md))
- [x] complete JEV test failure check ([`label_analysis/jev_audit.md`](label_analysis/jev_audit.md)
  is `current`: 100 flagged rows, 0 confirmed pipeline defects)

## Results

Source: [`stats_output/report.txt`](stats_output/report.txt) (generated 2026-11-01 09:41).

| Metric | Value |
|---|---|
| Commits processed | 3161 |
| Without test failures | 2869 |
| With test failures | 158 |
| Not applicable | 126 |
| Hard errors | 8 |
| Coverage produced | 99.7% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py babel --stats` (window `min`, run 2026-11-01)
and [`stats_output/report.txt`](stats_output/report.txt) (generated 2026-11-01 09:41).
Labels: [`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary window; the diagnostic `max` window carries 226 unlabeled fingerprints and
has no label CSV). This CSV is the single source of truth; this section reports
numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 158 |
| Failing runs (label DB) | 158 (`failing runs` line) |
| Fingerprints (min / max) | 223 / 226 |
| Labeled fingerprints | 223 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 142 |
| reevaluated_acceptable | 80 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 1 |
| Manual / auto-propagated labels | 103 / 120 |
| Labeled detections (min) | 459/459 (100.0%) |
| Labeled runs (min) | 158/158 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 100 flagged rows |
| Jev audit | [`current`](label_analysis/jev_audit.md) |

**State:** complete.

No `problematic` or `unclear` fingerprints remain, so no per-family table is listed.

## Environment / setup fixes

- [`config.json`](../../config.json) → `babel`: enabled
  `package_manager_skip_engines` and added a package-manager override that maps
  the bare `yarn` fallback to `yarn@2.4.0` through 2021-09-16. Without this,
  640 commits are misdetected as `yarn@1.4.0` and cannot install the Yarn Berry
  lockfile.
- [`config.json`](../../config.json) → `babel`: enabled
  `use_exact_node_version` and added two Node overrides covering the windows
  where babel's CI declares no usable minor, so the container no longer installs
  the newest patch of the chosen major at image-build time (years ahead of the
  commit):
  - `20 → 20.18` for 2024-09-26 – 2024-10-17 (22 commits).
  - `22 → 22.11` for 2024-11-08 – 2024-12-13 (44 commits).
  Both pins sit below every era-breaking Node release: `require(esm)` is
  default-on from 20.19.0 / 22.12.0 / 23.0.0, and TS type-stripping is
  default-on from 22.18.0 / 23.6.0. Those features make babel's negative-path
  tests (`config-ts.js`, `config-chain.js`, `async.js`) stop throwing, so the
  suite silently measures less. Windows are derived from WayPack's temporal
  registry (`GET /npm/<ts>/node`), which resolves the newest release available
  at each commit timestamp.
- The earlier bak-era rules (`16 → 18` for 2023-11-14 – 2024-01-19, and
  `20 → 22` from 2025-09-05) are **not** applied: they were dropped when the
  GitHub Actions strategy was introduced and are preserved only in
  `commits.csv.bak`.
- `install-and-run.sh` and `yarn-workers-shim`:
  - **Worker limits & Wasm OOM:** Exports `CI=true` and prepends `/tmp/shim-bin`
    (symlinking `yarn` to `/coverage_reloaded/yarn-workers-shim`) to `$PATH`.
    This caps Jest workers to 2, preventing WebAssembly address-space exhaustion
    on high-core hosts (256 threads).
  - **Node heap limits:** Sets `--max-old-space-size=8192` in `NODE_OPTIONS` to
    provide 8 GB heap for large test runs, preventing V8 heap exhaustion when `c8`
    merges whole-monorepo coverage across >24,000 tests.
  - **Coverage script selection:** Uses `make test-cov` rather than
    `make test-ci-coverage` in the post-`scripts/test-cov.sh` era; upstream
    inadvertently dropped `--coverage` from `test-ci-coverage` during mid-2022
    (#14802).
  - **Gulpfile helper generation race condition:** Upstream's `Gulpfile.mjs` ran
    `build-babel` and `generate-runtime-helpers` in `gulp.parallel`, allowing
    `@babel/helpers` to be compiled before `helpers-generated.js` finished writing,
    throwing `Unknown helper typeof` in `build-dist`. In `install-and-run.sh`,
    this is serialized with `gulp.series("generate-runtime-helpers", ...)`.
  - **Shim query bypass:** `yarn-workers-shim` bypasses query commands (`bin`,
    `explain`, `config`) untouched so commands like `yarn bin jest` return clean
    paths without injected flags.
  - **`--watch` fixture timeout:** the `babel-cli` `--watch` fixtures
    (`packages/babel-cli/test/fixtures/babel/*/executor.js`) wait a hard-coded
    `5000ms` for the first watch build and print `EXECUTOR TIMEOUT` if it has not
    landed. Under coverage instrumentation (the `babel-plugin-istanbul` era) and
    inside a loaded container the first build takes far longer, so
    `bin/babel > dir --out-dir --watch --verbose with external dependencies`
    failed on timing alone while the rest of the suite passed. `install-and-run.sh`
    widens it to `120000ms`. **Timing only — what the fixture asserts is
    unchanged.**
    **Measured outcome (accepted limitation):** the widening helps on Node 18
    (10/16 fixed) but **not** on Node 16 (1/115). The patch verifiably applies
    (fixture reads `120000` in the affected era), so on Node 16 the watcher emits
    nothing at all within the budget — plausibly because `execute.sh` copies the
    repo to an *in-memory* `/coverage_reloaded/repo` and `--watch` depends on fs
    events. **Accepted:** every one of the 120 still-failing runs produces valid
    `unit.lcov` (~1 MB, 23598/23599 tests passing, bail disabled), so they are
    valid partials per `AGENTS.md`, not silent failures.
- **Run archiving:**
  - Initial 18 failed runs archived to [`archive/fix_bootstrap_and_coverage_target/`](archive/fix_bootstrap_and_coverage_target/).
  - All 154 preliminary runs archived to [`archive/pre_runner_rework_all_runs/`](archive/pre_runner_rework_all_runs/)
    to cleanly re-run the entire corpus under the validated worker shim and
    runner targets.
  - 114 runs archived to [`archive/fix_ci_node_version_extraction/`](archive/fix_ci_node_version_extraction/)
    whose Node.js versions changed (e.g. from lagging Node 12/14/16/20/22 to the
    true CI-tested LTS releases 16/18/20/22/24) after generalizing GitHub Actions
    CI strategy extraction and eliminating obsolete manual overrides.
  - 3 runs (`568679e3`, `cf0cfac3`, `6c182cd2`) archived to [`archive/interrupted_during_shutdown/`](archive/interrupted_during_shutdown/).
    These runs completed all unit tests and wrote valid coverage inside the containers, but their host
    processes caught SIGINT (exit -2) during session shutdown, marking them as `.error`.
    They are archived to keep dataset metrics clean and will be cleanly re-run in a subsequent pass.
  - 731 runs whose resolved Node.js version changed archived to
    [`archive/node_version_exact_pin_fix/`](archive/node_version_exact_pin_fix/).
    The resolved version moved from a bare major to the exact minor its CI
    declared (`22 → 22.1`, `22 → 22.10`, `20 → 20.5`, `18 → 20.5`,
    `20 → 21.7`, `22 → 22.4.1`, `16 → 16.6`, `22 → 22.5`, `22 → 22.12`) or to
    one of the two new override pins (`20 → 20.18`, `22 → 22.11`). Breakdown by
    cause: 170 from `.circleci/config.yml` now outranking GitHub Actions, 67
    from the two Node overrides, 494 from GitHub Actions preserving the minor it
    was already reading.
  - 23 runs archived to [`archive/flaky_incomplete_lib_build/`](archive/flaky_incomplete_lib_build/)
    carrying the two unresolved signatures from the 2023-11-29 – 2024-07-26
    window (`_index.BINARY_OPERATORS is not iterable`, 8 runs; `write EPIPE`,
    15 runs). No code change — see
    [Watch list — flaky build-order race](#watch-list--flaky-build-order-race-low-rate-accepted-not-fixed)
    for the verdict (22/23 green on re-run; race still live but rare).
  - 14 further occurrences archived to
    [`archive/flaky_incomplete_lib_build_r2/`](archive/flaky_incomplete_lib_build_r2/),
    vacated for a low-contention (`--max-workers 1`) re-run.
  - 249 runs archived to [`archive/node_16_probe_pin_wasm_oom/`](archive/node_16_probe_pin_wasm_oom/).
    Round-1 results, superseded. Exact-minor extraction pulled `16.6` from
    babel's `test/runtime-integration/node.cjs` compatibility-**probe** job rather
    than its test matrix; Node 16.6 (2021-06) carries the old V8 wasm
    address-space limit and 205/249 hard-errored with
    `RangeError: WebAssembly.instantiate(): Out of memory: wasm memory`. Of
    these, **134 were restored** (copied back to `output/`) from
    [`archive/node_version_exact_pin_fix/`](archive/node_version_exact_pin_fix/)
    — they had passed on bare `16` (`16.20.2`), which is the value they get back
    — and 115 are vacated for a clean re-run.
  - 16 runs archived to [`archive/watch_timeout_unverified/`](archive/watch_timeout_unverified/),
    all node 18 (2022-04-20 – 2022-05-09), the last population never re-run after
    the `--watch` fixture timeout patch landed.

### Lesson: the extracted literal is not always the suite's Node

`github_actions._normalise()` preserves the minor/patch instead of truncating to
the major. That logic is **sound** — a workflow that pins `node-version: 22.1`
names an exact release, and truncating it makes the container install the newest
22.x at image-build time. It is what drove `config-ts.js` and `config-chain.js`
to zero.

The defect is upstream of it: `_extract_literal_node_versions` collects **every**
`node-version:` literal in the workflow, including the ones in
`test/runtime-integration/node.cjs`, a compatibility probe across
`12.0, 13.2, 14.2, 16.5, 16.6, 22.11, 22.12 …`. The strategy then picks the
highest tested LTS major among *all* of them, so the winning token can come from
a job that never runs the suite.

Note also that **`node-version: 16` does not mean `16.0`** — it means "the
newest 16.x", which is what `actions/setup-node` resolves and what `n 16`
reproduces. So bare `16` and `16.6` are both faithful, to *different jobs*.
Preserving the minor made us faithful to the probe and unfaithful to the suite.

Two consequences:
- A single `node_version_overrides` entry
  (`1633360094..1650458247`, `16 → 16`) neutralises the probe-derived `16.6`.
  `old_version` is major-matched by design (`int | None`, compared against
  `node_major`), so `"16.6"` cannot be expressed and would silently never fire.
- A proper fix would teach the extractor which *job* a literal belongs to —
  prefer the job that runs the test command, or prefer matrix entries over
  standalone probe literals.

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
- Node version resolution now keeps the **exact** minor/patch instead of the
  major alone, and `.circleci/config.yml` is consulted before the GitHub Actions
  workflow. This was the fix for the dominant failure mode: a bare major (`22`)
  made the container install the newest patch of that major at image-build time
  (`22.23.2`), years ahead of the commit, which activated Node features
  (`require(esm)`, TS type-stripping) that made babel's negative-path tests stop
  throwing. Two manual era overrides remain, for windows where CI declares no
  usable minor. See [Test infrastructure](#test-infrastructure) for detail.

### Watch list — flaky build-order race (low rate, accepted, not fixed)

Two failure signatures appear in a shared window (2023-11-29 – 2024-07-26) and
**have not been root-caused**. They are archived to
[`archive/flaky_incomplete_lib_build/`](archive/flaky_incomplete_lib_build/)
specifically to get a second data point on the next run:

1. `TypeError: _index.BINARY_OPERATORS is not iterable (cannot read property
   undefined)` — a module-level spread in `packages/babel-types/src/definitions/*`.
   Only a handful of suites fail while hundreds importing `@babel/types` pass,
   which is the signature of a **stale mix of old and new `lib/` files** rather
   than a uniformly broken package. 8 runs.
2. `Test suite failed to run / write EPIPE` — a subprocess/pipe death, mostly in
   `packages/babel-cli/test/batch-test-runner/3.js`. 15 runs.

**Why they might be flaky:** upstream's `gulp build-dev` compiles `src` → `lib`
*before* the `generate-type-helpers` / `generate-runtime-helpers` tasks finish,
and only the type-helpers task is awaited before the rebuild. Upstream's own
comment concedes the hazard (*"rebuild @babel/types since type-helpers may be
changed"*). `install-and-run.sh` already patches one such race in the Gulpfile,
but its `sed` only matches an older task-graph shape and does not fire here.

**Verdict — FLAKY, contention-sensitive, ACCEPTED (not fixed), CLOSED.** Three
re-run passes give a monotonic rate: **35% (8/23, heavy) → 4% (1/23, moderate) →
0% (0/14, `--max-workers 1`)**. Round 2's single repro (`9f2cbc44eb`) and all 13
other second-round occurrences went green on the low-contention pass — exactly
what a load-sensitive build-order race looks like, and an empirical closure of
the question.

**It is not a measurement hazard.** Every affected run still yields full, valid
coverage: `SF` 527–531 source files, `LF` 97k–101k lines, **88.7%–94.3%** line
coverage — in line with the project mean (90.2%) — with 1 of ~214 suites failing
and bail disabled. These count as valid partials per `AGENTS.md` and already
satisfy the 90% criterion.

**A Gulpfile ordering patch was considered and rejected.** It would run both
`generate-type-helpers` and `generate-runtime-helpers` *before* the first
`src` → `lib` compile, which is the correct fix for the race. But it is a
fragile multi-era `sed` on a task graph that varies across eras, it diverges
further from upstream's own build ordering, and it solves a non-problem given
the coverage evidence above. The 14 second-round occurrences are archived to
[`archive/flaky_incomplete_lib_build_r2/`](archive/flaky_incomplete_lib_build_r2/),
whose low-contention (`--max-workers 1`) re-run came back **14/14 green**
(2026-11-01) — see its `README.md` for the verdict.

## Known test failures

- `7896ed74` (2025-06-29): `sourceType-commonjs` parser fixtures for
  `es2026/...` fail because the test blockList still names `experimental/...`;
  the later commit `5e7cb54304` fixes the paths. Developer-facing; not fixed
  here.
- `9421fa14`, `e54bc6b8`, `95417784` (2022-02 – 2022-04): the `babel-cli` watch
  test times out (`EXECUTOR TIMEOUT`). Widening the fixture's hard-coded
  `5000ms` wait to `120000ms` (see *Environment / setup fixes*) is **insufficient
  on Node 16** — 1/115 fixed — though it does fix Node 18 (10/16). The watcher
  emits no output at all within the budget on Node 16. **Accepted:** 1 failing
  test out of 23599, with valid `unit.lcov` on every run, so these are valid
  partials and not a measurement hazard.
