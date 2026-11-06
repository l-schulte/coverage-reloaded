# webpack

**Repository:** https://github.com/webpack/webpack
**Status:** active

## Test infrastructure

- **Package manager:** yarn (classic, `yarn@1`; `packageManager` pinned to `yarn@1.22.22`) — see [`config.json`](../../config.json) → `webpack`
- **Node strategy:** default (LTS active at commit date, 3-month stabilisation delay) plus overrides `22 → 22.20` and `24 → 24.7` for the collection window (see `config.json`)
- **Runners:** Jest only (`node_modules/jest-cli/bin/jest`, driven through the project's `test:base` / `cover:base` scripts)
- **Eras:** baseline jest with config inline in `package.json` (through 2021-02); `--experimental-vm-modules`/`--expose-gc` and the `cover:integration:a`/`:b` split (2021-02-24); memory tuning (2021-06/07); `travis:*`/`appveyor:*` shim scripts removed (2022-01, 2023-03); script renames (`code-lint` → `lint:code`, etc.) (2025-04-30); `test:base`/`cover:base` introduced (2025-05-20/22); Deno/Bun runtime suites added (2025-12)

## Development style

- **PR merging strategy:** Hybrid — Merge commit (2021–2023) → linear/direct (2024) → Squash and merge (2025+)
- **Merge convention:** `Merge pull request #<PR> from <branch>` (2021–2023), `Title (#<PR>)` (2025+); 2024 direct pushes carry no PR reference
- **Direct commits:** Moderate — lead maintainers (Tobias Koppers, Alexander Akait) push core logic to `main` directly, alongside Dependabot and release bots
- **JS/TS code impact of direct commits:** Core logic & tests — the majority of in-window commits are non-first-parent branch intermediates, so single-parent commits that were never green in isolation are common
- **Issue tracking discipline:** Partial — 2025 squash commits reference PRs (for example `Title (#<PR>)`); many 2024 direct commits reference no issue
- **Workflow notes:** Conventional-commit prefixes (`fix:`, `feat:`, `refactor:`, `chore:`, `ci:`). Merge-commit PRs through 2023 mean most PR branch commits are ancestors of `main` and are collected individually; such commits often fail in isolation (for example stale snapshots) although the PR head was green.

## Coverage collection

- **Suites collected:** `unit` → `cover:unit`; `integration-a` → `cover:integration:a`; `integration-b` → `cover:integration:b` (falls back to `cover:integration` when the split is absent)
- **Suites excluded:** `benchmark` (`*.benchmark.*`); spec-conformance (`test:test262`, `test:html5lib`, `test:css-parsing`, `test:xmlconf`, `test:minify-corpora`, `test:js-fuzz`, `test:test262-parser`, `test:syntax-equivalence`); Deno/Bun runtime suites; browser-driven `ProfilingPlugin.unittest.js` and `WebpackDevServer.longtest.js`
- **Coverage tool / config:** Jest coverage, driven through the project's own `cover:*` scripts so each era's `testMatch` is honoured; `coveragePathIgnorePatterns` from `jest.config.js` (or the inline config in earlier eras)
- **LCOV production:** the project config emits only `json`; `install-and-run.sh` appends `--coverageReporters=lcov`, and `find-and-move-lcov.sh` moves each suite's `lcov.info` (`unit`, `integration-a`, `integration-b`)

## Checklist

- [x] 100 done (100/100)
- [x] failed tests doublechecked (2,642 failing runs reviewed; no `problematic` or `unclear` fingerprints remain)
- [x] complete run (5,607/5,607 commits, 0 pending)
- [x] complete test failure check (36,596/36,596 fingerprints labeled, 100 %)
- [x] complete JEV test failure check (`failure_labels_jev_min_dedup_error.csv`: 13,684 families, 7,180 flagged; all reviewed in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-10-31 12:44).

| Metric | Value |
|---|---|
| Commits processed | 5,607 |
| Without test failures | 2,918 |
| With test failures | 2,642 |
| Not applicable | 0 |
| Hard errors | 47 |
| Coverage produced | 99.2% |

Full statistics and plots: [`stats_output/`](stats_output/).

All 5,607 commits in the 5-year study window have completed processing (0 commits pending). The 47 hard errors are 32 accepted `--frozen-lockfile` mismatches, 14 90-minute timeouts, and 1 genuine Jest `RangeError` crash. Archived historical batches: 446 runs in [`archive/fix_browserslist_node_18/`](archive/fix_browserslist_node_18/), 165 runs in [`archive/fix_browserslist_config_file/`](archive/fix_browserslist_config_file/), 47 runs in [`archive/stale_docker_run_edit_race_2/`](archive/stale_docker_run_edit_race_2/), 100 runs in [`archive/fix_browserslist_urls_deprecations/`](archive/fix_browserslist_urls_deprecations/), 722 runs in [`archive/fix_http_url_and_browserslist_node/`](archive/fix_http_url_and_browserslist_node/), 84 runs in [`archive/dns_codeload_github/`](archive/dns_codeload_github/), 13 runs in [`archive/assert_suite_ran_binary_log/`](archive/assert_suite_ran_binary_log/), 8 runs in [`archive/stale_docker_run_edit_race/`](archive/stale_docker_run_edit_race/), and 4 runs in [`archive/waypack_registry_500/`](archive/waypack_registry_500/). The 2026-10-29/30 re-run of the 814 archived commits completed with 813 producing coverage; the single failure (`1710501085`) stalled in `yarn install` and hit the 90-minute cap.

## Failure triage

Source: `python check_failures_v2.py webpack --stats` (window `min`, run 2026-10-31) and
`stats_output/report.txt` (generated 2026-10-31 12:44). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 2,642 |
| Failing runs (label DB) | 2,642 (`failing runs` line) |
| Fingerprints (min / max) | 36,596 / 40,149 |
| Labeled fingerprints | 36,596 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 33,270 |
| reevaluated_acceptable | 3,326 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 2,533 / 34,063 |
| Labeled detections (min) | 105,984/105,984 (100.0%) |
| Labeled runs (min) | 2,642/2,642 (100.0%) |
| Jev mode | dedup-error |
| Jev pipeline issues | 7,180 flagged families (10,525 fingerprints / 2,125 runs) |
| Jev audit | current |

**State:** complete.

## Environment / setup fixes

- **Browserslist query pinning:** `test/configCases/ecmaVersion/browserslist/package.json` configures `target: ["browserslist"]` with the query `"maintained node versions"`. The `browserslist` package resolves this query by checking the `node-releases` schedule against `Date.now()`. When collected years later, all historical Node versions in the commit's lockfile schedule are past their End-of-Life date, so the query returns an empty list (`[]`). Webpack's internal feature compatibility check (`list.every(...)`) then evaluates vacuously to `true`, causing snapshot mismatches. `install-and-run.sh` substitutes `"maintained node versions"` with era-correct Node queries matching each period's snapshots and lockfile capabilities: `node 10, node 12, node 14` for pre-Feb 2022 commits expecting `dynamicImport: false`, `node 14, node 16` for 2022 to mid-2026 commits (avoiding `Unknown version 18 of Node.js` when lockfiles predate Node 18's release), and `node 20, node 22, node 24` for mid-2026+ commits asserting `nodeBuiltinModuleGetter`. Additionally, `test/configCases/ecmaVersion/browserslist-query-with-config-file/webpack.config.js` is substituted with `node 18, node 20` to preserve the `importMetaDirnameAndFilename: false` snapshot. 446 runs archived to [`archive/fix_browserslist_node_18/`](archive/fix_browserslist_node_18/) and 165 runs archived to [`archive/fix_browserslist_config_file/`](archive/fix_browserslist_config_file/) for clean re-run.
- **`CODE_OF_CONDUCT` HTTP(S) mock interceptor:** `test/configCases/asset-modules/https-url` (2020–2021) and `test/configCases/asset-modules/http-url` (2021–2025, specifically the `no-cache` target) request `https://raw.githubusercontent.com/.../CODE_OF_CONDUCT.md`. Because the GitHub branch was renamed from `master` to `main` and the file was deleted upstream in 2025, these requests returned HTTP 404. `mock-code-of-conduct.js` (copied in `Dockerfile` and loaded via `NODE_OPTIONS="--require /coverage_reloaded/mock-code-of-conduct.js"`) intercepts `http`/`https` requests for `CODE_OF_CONDUCT.md` and serves the local checked-out `CODE_OF_CONDUCT.md`, matching committed SHA-512 lockfile integrity. There is no substituted fallback body: if the file is missing the request fails loudly, because a missing file means a broken checkout rather than an expected state. The interceptor is **not limited to the code of conduct**: every `https://raw.githubusercontent.com/webpack/webpack/<ref>/<path>` request is served from the checked-out commit when that path exists (`README.md` is what `asset-modules/http-url` also pins), with the unnormalized `//` form still answered by a locally synthesized 301 and unknown paths or other repositories still going to the network so that cases asserting real 404s keep their semantics. Without that generalization the README integrity check failed against the commit's lockfile and the case reported `More errors (10 instead of 6) while compiling than expected` — 50 runs archived to [`archive/fix_asset_url_readme_mock/`](archive/fix_asset_url_readme_mock/). This supersedes the previous `fs.unlinkSync` and lockfile-copying workaround in `install-and-run.sh`. 4,979 affected runs archived to [`archive/fix_code_of_conduct_urls/`](archive/fix_code_of_conduct_urls/) for clean re-run. The mock also serves a stable SHA-1 `ETag` and answers `304` when the request carries a matching `if-none-match`: webpack's `HttpUriPlugin` builds `{ "if-none-match": cachedResult.etag || undefined }` on revalidation, and Node throws `TypeError: Invalid value "undefined" for header "if-none-match"` when a cached response was stored without one, which failed `asset-modules/http-url` and its 40 s/60 s cache passes. 2 runs archived to [`archive/fix_mock_etag_if_none_match/`](archive/fix_mock_etag_if_none_match/). Two earlier runs of the same case predate the mock entirely and failed with `getaddrinfo EAI_AGAIN raw.githubusercontent.com` (container DNS); they are archived to [`archive/network_dns_retry/`](archive/network_dns_retry/) for a re-run that the mock should now satisfy.
- **jest worker spawn failures:** 2 runs on 2021-02-13 lost one test suite to `Call retries were exceeded` at `jest-worker` `ChildProcessWorker.initialize` while 45 other suites and 37,510 tests ran normally — a host-level process/resource hiccup, not a test failure. Archived to [`archive/jest_worker_spawn_rerun/`](archive/jest_worker_spawn_rerun/) for re-run under nominal load.
- **WASM OOM on the jest-27 branch:** 8 runs (Node 14, 2021-06-21 → 07-12) fail every affected suite with `● Test suite failed to run` → `RangeError: WebAssembly.instantiate(): Out of memory: wasm memory`, while the rest of the suite passes (34–68 failed tests per run). All 8 are commits of the jest 27 upgrade branch (`fix createLazyTestEnv for new jest major version`, `update jest dependencies`, three merges of `dependabot/npm_and_yarn/jest-27.0.4`), and the dominant case is `wasm/two-files-loader`, whose wasm payload is a few KB — so the cause is the half-migrated jest 27 harness, not host pressure and not a large module. **Restored rather than re-run** (the failure is reproducible on those commits, so a re-run would only reproduce it); the finding is recorded in [`archive/wasm_oom_jest27_branch/README.md`](archive/wasm_oom_jest27_branch/README.md), and the 8 runs keep their original logs and lcov.
- **JS-heap OOM on a wasm-heavy commit:** 1 run (`1632420870`, Node 16, `7644f85e77 add wasm-bindgen example`) died with V8 `CALL_AND_RETRY_LAST` at the project's own `--max-old-space-size=4096`, losing 18 of 46 suites; the visible failures are the `wasm › v128` cases. Unlike the jest-27 OOMs this is a JS-heap ceiling under coverage instrumentation, expected to recur. Archived to [`archive/heap_oom_wasm_v128_rerun/`](archive/heap_oom_wasm_v128_rerun/) for a re-run under nominal load; if it recurs, raise the heap cap for that commit only.
- **`NODE_OPTIONS="--no-deprecation"`** (`install-and-run.sh`): silences standard `DeprecationWarning`s only. It does **not** cover the import-attribute warning: Node emits `'assert' is deprecated in import statements; use 'with' instead` with warning type `V8`, which `--no-deprecation` does not filter (logs written after the flag was in place still contain it). Keep this line for ordinary deprecations; the import-attribute case is handled by the Node pin below.
- **Node 20 patch pin** (`config.json`): `20 -> 20.9`. The import-attribute deprecation warning first appears in Node 20.10, so a modern 20.x patch (20.20.2 in the base image) turns every commit whose `test/configCases/externals/import-attributes` still uses `assert { type: "json" }` into a spurious `Errors/Warnings during build` failure — 221 runs across 2023-05 to 2024-06. Pinning the whole node-20 era (Node 20 resolves only for commits between 2023-05 and 2024-07) to the last patch before the deprecation keeps the major version the resolver chose while removing the warning path. In the later `with { type: "json" }` era the affected cases are filtered to `v22+` (`import-attributes`) and `v16-19|21` (`import-assertion`), so they never execute under Node 20 and the pin is behaviourally inert there. 714 node-20 runs archived to [`archive/fix_node20_assert_deprecation/`](archive/fix_node20_assert_deprecation/) for clean re-run.
- **Node-version override** (`config.json`): `22 → 22.20`, `24 → 24.7`. Node's new `vm.SourceTextModule.instantiate()` (added in 22.21.0 / 24.8.0) makes the commit-era harness throw `Module status must be unlinked` after `esm.link()`, dropping approximately 390 `TestCasesModule` tests. The override keeps the major version while pinning below the API. Note: one observed instance (run `1731693286`, commit `71ea4502`) used the pinned **22.20** and still threw it on `css/basic-esm-target-node` and `css/basic-esm-target-web`, so the pin does not cover those two cases. The project fixed the harness itself in 2026-01 (`22e17876f`), after the collection window.
- **`GITHUB_ACTIONS=true`** (`projects/webpack/Dockerfile`): webpack's `isColorSupported()` treats `CI=true` as colour-capable only when a known CI marker (`GITHUB_ACTIONS`, `GITLAB_CI` or `CIRCLECI`) is also present. The base image sets only `CI=true`, so `Cli › createColors › simple (colors by default)` failed. The project Dockerfile now sets `GITHUB_ACTIONS=true`, matching webpack's GitHub Actions environment.
- **webpack self-link:** `install-and-run.sh` creates the `node_modules/webpack` symlink the tests require (equivalent to the project's `setup/setup.js` / `yarn link`).
- **Browser-driven files excluded:** `test/unitCases/ProfilingPlugin.unittest.js` and `test/WebpackDevServer.longtest.js` require a real Chrome.
- **Initial 100-commit archive:** 100 sample runs affected by the initial investigation pass were archived to [`archive/fix_browserslist_urls_deprecations/`](archive/fix_browserslist_urls_deprecations/).
- **Archived runs for http-url and browserslist fixes:** 722 runs affected by the external GitHub 404 in `dev-defaults` and Node 20 Browserslist errors were archived to [`archive/fix_http_url_and_browserslist_node/`](archive/fix_http_url_and_browserslist_node/) for clean re-run.
- **DNS pinning for GitHub hosts** (`execute.sh`): `codeload.github.com` and `raw.githubusercontent.com` were not in the `resolve_and_pin` list, so `yarn install` intermittently failed with `EAI_AGAIN` while fetching git/tarball dependencies. Both hosts are now pinned; lockfiles that reference the unreachable internal mirror `bnpm.byted.org` (webpack `93d12eb`) have those URLs rewritten to the WayPack yarn registry. 84 affected runs archived to [`archive/dns_codeload_github/`](archive/dns_codeload_github/).
- **`assert_suite_ran` binary-log parsing** (`helper/assert-suite-ran.sh`): webpack's test output embeds NUL bytes (dumped binary fixtures), so `grep` treated the suite log as binary, wrote `binary file matches` to stderr, and returned no summary; the strict guard then aborted a suite that had actually run. `_asr_grep` now passes `grep -a`, and the Jest "ran" patterns accept `skipped`/all-failed summaries (`Test Suites: 10 failed, 10 total`). 13 affected runs archived to [`archive/assert_suite_ran_binary_log/`](archive/assert_suite_ran_binary_log/); the one genuine Jest `RangeError: Invalid array length` crash (`1758244645`) is left as a hard error.
- **Stale post-completion error markers** (`src/docker/docker_run.py`): a successful attempt now removes any leftover `output/<run>.error` marker, and failure markers record the host exit code. The 8 dir+error conflicts from the 2026-10-16 11:42 `docker-run.sh` mid-run edit are archived to [`archive/stale_docker_run_edit_race/`](archive/stale_docker_run_edit_race/) for re-run.
- **WayPack 500 runs:** 4 transient `500 Internal Server Error` install failures archived to [`archive/waypack_registry_500/`](archive/waypack_registry_500/) for re-run.
- **Mid-run `docker-run.sh` edit artifacts (2026-10-20 & 10-22):** 47 runs during the re-run failed due to host syntax errors while `docker-run.sh` was modified mid-run (with `Unterminated quoted string` or `"else" unexpected`). The test suites and LCOV collection inside containers succeeded; all 47 runs were archived to [`archive/stale_docker_run_edit_race_2/`](archive/stale_docker_run_edit_race_2/) for clean re-run.

## Known gaps

- **The soft-failure share (2,642 of 5,607 runs, 47.1 %) is dominated by one family.**
  2,045 runs (77.4 %) carry a `ChunkLoadError` block and 1,699 (64.3 %) fail on nothing
  else; without it the share would fall to 16.8 %. From 2023-07 onward the block is present
  in essentially every run (2024: 1,135 of 1,141; 2025: 680 of 680). These are not tens of
  thousands of independent defects: the failing title is a
  `WatchTestCases`/`WatchCacheUnaffectedTestCases` cache case (`reexport-mangle`,
  `unsafe-cache-duplicates`, `new-split-chunk-entry-node`, `delete-in-context`), while the
  stack belongs to a `ConfigCacheTestCases` bundle (`web/fetch-priority` until 2025-10-08,
  `plugins/manifest-plugin` after) — the misattribution detailed in the next bullet, which
  counts the two named phases (628 fingerprints / 2,039 runs). The remaining 22.6 % is
  diffuse: `StatsTestCases`/`ConfigCacheTestCases` snapshot cases, `Cli` flags, `warmup`,
  and the timeout runs listed below.
- **Unresolved timeouts — 341 fingerprints on 48 runs.** Heavy `ConfigTestCases` / `ConfigCacheTestCases` / `HotTestCases` / `WatchSuspend` cases carry their wall-clock budget inside the project's own harness (`it(name, fn, 30000)` in `test/ConfigTestCases.template.js`, `jest.setTimeout(5000)`, `it(..., 20000)` in the hot suites), which our coverage-instrumented container exceeds. They are deterministic, not flaky — re-running 35 archived runs reproduced **30 with an identical timeout count** (`48→48`, `8→8`, `3→3`, …) — and cannot be relaxed from `test.config.js`; the only remaining lever would be a bounded timeout multiplier injected into the jest setup, which would change the experiment for every commit and is therefore not applied. **Why coverage is unaffected:** a timeout stops that one test, but the lines it would execute are also executed by sibling tests of the same suite at that commit, so the per-suite `LH` of the affected run stays within **0.5 % of same-layout neighbouring runs (median 0.0 %, worst −0.5 %)** and the run's lcov is complete. The exposure variable therefore measures the same code as a clean run; only one assertion per case never runs. The timeout rules in `label_analysis/failure_patterns.json` carry this note.
- **Misattributed chunk-load errors with no effect on coverage — 628 fingerprints on 2,039 runs.** `WatchTestCases.longtest.js` and `WatchCacheUnaffectedTestCases.longtest.js` report `ChunkLoadError: Loading chunk N failed. (timeout: https://test.cases/path/N.js)`, but the failing code is a `ConfigCacheTestCases` bundle: `createLazyTestEnv` re-points Jest's current-test state, so a dangling `import()` from a cache-variant case surfaces in the next file of the suite. Two phases: `web › fetch-priority` from 2023-04-14 to 2025-10-08 (**1,859 runs**, fixed upstream in `1f0d77484`), then `plugins › manifest-plugin` (161 logs) and `web › prefetch-preload-module-jsonp` (32 logs) from 2025-10-09 to 2025-12-26 (**180 runs**, same pattern, not fixed inside the window). Every log before the boundary names `fetch-priority`, none after. **Why coverage is unaffected:** the chunk belongs to another test file's bundle, so no code under test in the affected run goes unexecuted; the watch machinery itself is hit at the same rates in passing and failing eras (`lib/Watching.js` LH 171 / 172 / 173, `lib/FileSystemInfo.js` 1,084 / 1,092 / 1,097 for 2023-06 / 2024-06 / 2025-06). Accepted as `reevaluated_acceptable`; evidence in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md) §1.
- **Hot-backend flake, 22 runs re-run (2026-10-30):** `HotTestCases*` occasionally lost its dev server — `ECONNREFUSED 127.0.0.1:<ephemeral-port>` (14 runs), `ECONNRESET` (2) or `No update available` (6) — on 5 runs of 2021-05-31 and 17 runs spread over 2025-05 → 2025-11. Same-commit original/re-run comparison showed both-direction flips (91 `P→F` vs 204 `F→P` over 7,679 pairs; 0 flips 2021–2024, 8 % in 2025), i.e. a timing race rather than commit-era breakage. All 22 runs archived to [`archive/hot_backend_flake_rerun/`](archive/hot_backend_flake_rerun/) and re-run on an idle box at 5 workers: **the 17 2025 runs came back clean of the failure (0/17), the 5 runs of the 2021 window reproduced it (5/5)**. Per-suite coverage of the re-runs matches the archived originals on 61/61 suite pairs (median ΔLH 0.00 %, range −0.01 … +0.14 %). The 17 now fail only `WatchTestCases.longtest.js`, i.e. the known gap above.
- **Two single-run environment caps.** `1632420870` aborts with `FATAL ERROR: CALL_AND_RETRY_LAST` at the project's own 4096 MB heap cap (wasm-heavy `v128` commit) and `1613247228` loses one suite to a `jest-worker` spawn failure (`Call retries were exceeded`). Both are environment limits outside the project code; they affect one run each and are accepted rather than re-run.
- Per-family classification is not restated here. It lives in [`label_analysis/failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv) (`auto_rule_id` resolves through `label_analysis/failure_patterns.json`), with the previously `problematic` set re-assessed in [`label_analysis/problematic_reevaluation.md`](label_analysis/problematic_reevaluation.md) and the six Jev clusters in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md).
- `ConfigTestCases` and `ConfigCacheTestCases` run the same `test/configCases/**` fixtures; both suites' `lcov.info` is combined per commit, so a cache-variant failure does not remove that code from the measurement.
- The failing test name in a log is unreliable: `createLazyTestEnv` re-points Jest's current-test state, so an asynchronous error is attributed to whichever test is running when it surfaces.
- Spec-conformance suites not collected (they require `test/external` Git submodules, absent by design).
- Deno and Bun runtime suites not collected.
