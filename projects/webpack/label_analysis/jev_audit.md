# Jev audit — webpack

**Source:** `label_analysis/failure_labels_jev_min_dedup_error.csv` (dedup-error mode: one Jev
verdict per `(suite, normalized error line)` family, falling back to the test name when the block
only carries a generic header).
**Snapshot:** mode `dedup-error`; rows `13,684` families covering `36,570` of `36,596` fingerprints
(`26` fingerprints / `2` families were rejected by the provider — see *Unlabeled slice* below); flagged
`is_pipeline_issue == true` on `7,180` families / `10,525` fingerprints / `2,125` of `2,642` failing
runs (subsystems: `none` 398, `missing_build_step` 5,491, `node_runtime_syntax` 842,
`module_resolution` 377, `ports_and_networking` 10, `runner_env_config` 60, `memory_exhaustion` 2);
Jev `labeled_at` max `2026-10-30T15:10:48Z`.
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-30T13:45:50Z`; `36,596` fingerprints — `33,270` `acceptable`, `3,326`
`reevaluated_acceptable`, `0` `problematic`).

Status: **complete (2026-10-31).** Every flagged cluster is covered below, including the §4 re-run
result.

### Unlabeled slice

Two requests were rejected by the provider, leaving `2` families (`26` fingerprints) without a Jev
verdict. This is not a transport failure and a retry would not help: Eden AI returned HTTP 400
`{"error_type": "max_tokens_exceeded"}` for both, i.e. the assembled prompt exceeded the model's context
limit, so the same request fails identically every time.

| run | line | fingerprint | family |
|---|---|---|---|
| `1706090709_5a9ed6dc…` | `34480` | `63b7262f2c10cfe2` | `TestCases › minimized-source-map › cjs-tree-shaking › reexports` — `SyntaxError` |
| `1634799127_6c0056c2…` | `97535` | `f0adbd978ee0e321` | `TestCases › minimized-source-map › resolving › issue-11555` — `TypeError` |

Both are `minimized-source-map` cases, whose failure blocks are large enough to overflow the prompt
budget. They stay unlabeled by Jev; the human labels stand (`acceptable`, rules `43f9588b43ca` and
`7fbbefbb4d35`), and they are covered by the same commit-era reasoning as the rest of that suite
(§6). Reducing `--context-below` for these two would be the only way to obtain a Jev verdict, at the
cost of changing the input for those two families only.

## Agreement

| Human label | Jev `acceptable` | Jev flagged |
|---|---|---|
| `acceptable` | 24,253 | 8,991 |
| `reevaluated_acceptable` | 1,792 | 1,534 |

71 % agreement on fingerprints. Because the human set contains no `problematic`, every Jev flag is a
disagreement; the review decides, per family, whether Jev found something the human pass missed.

## Findings

| Family | Date / exemplar run | Fingerprints | Runs (union) | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|---|
| `ChunkLoadError: Loading chunk <n> failed.`, reported under watch-case test names | 2023-04 → 2025-12 | 628 (+19 named-chunk families) | 2,039 | `none` (confidence 0.53) | See §1 | **upstream test-side defect** (dangling `import()` in a cache-variant case, misattributed) — `acceptable` stands |
| `ENOENT: no such file or directory, open 'test/js/<case>/bundle.js'` | 2021-03 → 2025-04, 12 short windows | 7,415 | 33 | `missing_build_step` | See §2 | **upstream defect** (compile cascade) — `acceptable` stands |
| Message-less blocks keyed on `test/js/<case>/bundle.js:<line>` | 2021-02 → 2024-11, 8 short windows | 777 | 16 | `node_runtime_syntax` / `module_resolution` | See §3 | **upstream defect** (compile cascade) — `acceptable` stands |
| Hot-backend loss: `ECONNREFUSED 127.0.0.1:<ephemeral>`, `ECONNRESET`, `No update available` | 2021-05-31 · 2025-05 → 2025-11 | 209 | 22 | `ports_and_networking` | See §4 | 2021 window = **upstream defect** (5/5 reproduced); 2025 = **timing flake, 0/17 reproduced on an idle re-run**, no coverage effect |
| `Errors while compiling:` (test-name fallback) + `Cannot find module 'test/js/<case>/__webpack_require__.p1.bundle.js'` | 2023-01-25 → 2023-02-09 (`workerPublicPath`) | 65 | 28 | `node_runtime_syntax` / `missing_build_step` / `module_resolution` | See §5 | **upstream defect** (feature-branch window) — `acceptable` stands |
| Tail: `css-modules`, scope-hoisting `side-effects`, wasm `getNumber`, `dll-plugin/manifest0.json`, wasm OOM | 2021-06 → 2024-11 | ~200 | 110 | mixed / `none` | See §6 | **upstream defect** — `acceptable` stands |

### §1 — `ChunkLoadError` in the watch-case suites

**What fails.** 628 fingerprints on 2,039 runs. The failing test *name* is always a watch case
(`WatchTestCases › cache › …`, `WatchCacheUnaffectedTestCases › context › …`), but the failing *code* is
not: the stack points into a `ConfigCacheTestCases` bundle.

```
● WatchTestCases › cache › reexport-mangle › exported tests 1 › should compile the next step

ChunkLoadError: Loading chunk 48 failed.
(timeout: https://test.cases/path/48.js)
   at Object.__webpack_require__.f.j (test/js/ConfigCacheTestCases/plugins/manifest-plugin/…)
```

**Mechanism.** `createLazyTestEnv` re-points Jest's current-test state (already recorded in
`OVERVIEW.md`), so an asynchronous error is reported against whichever test is running when it
surfaces. These are dangling chunk loads from cache-variant `ConfigCacheTestCases` cases: the case fires
`import()` without awaiting it, the fake-browser timer settles after that test has finished, and the
rejection lands during the next file of the same suite — the watch longtest. The `(timeout: …)` suffix
is the evidence that the request was never answered, not that a file was missing.

**Two phases.**

| phase | span | origin case | runs | status |
|---|---|---|---|---|
| 1 | 2023-04-14 → 2025-10-08 | `ConfigCacheTestCases › web › fetch-priority` | 1,859 | fixed upstream in `1f0d77484` (2025-10-08, in range) |
| 2 | 2025-10-09 → 2025-12-26 | `plugins › manifest-plugin` (161 logs), `web › prefetch-preload-module-jsonp` (32 logs) | 180 | same class, not fixed inside the window |

The boundary is exact: **every** ChunkLoadError log up to epoch `1759…` names `fetch-priority` (100 %),
**none** after `1760…` (0 %).

**Why the first reading was wrong.** An earlier pass of this audit treated the cluster as a watch-suite
failure with an unknown mechanism. The failing *file* in the Jest summary is the watch longtest only
because that is where the running test was registered; the origin is visible only in the stack frames.
`OVERVIEW.md` already carried the `fetch-priority` explanation for phase 1.

**Why coverage is unaffected.** The chunk import happens after the compile step has run the code under
test; the same files are hit at the same rates in the passing and failing eras:

| run (commit date) | `lib/Watching.js` LH | `lib/FileSystemInfo.js` LH | `lib/node/NodeWatchFileSystem.js` LH | `lib/` hit rate, `integration_b.lcov` |
|---|---|---|---|---|
| 2023-06 | 171 / 239 | 1,084 / 1,639 | 52 / 75 | 84.8 % |
| 2024-06 | 172 / 240 | 1,092 / 1,653 | 52 / 75 | 85.0 % |
| 2025-06 | 173 / 239 | 1,097 / 1,661 | 52 / 75 | 86.1 % |

**Verdict.** **Upstream test-side defect** — a dangling `import()` in a cache-variant case whose
rejection is misattributed to the watch test name. `acceptable` stands and no pipeline change follows:
phase 1 was fixed by webpack itself (`1f0d77484`), phase 2 is the same pattern in two other cases. The
earlier "unknown mechanism" reading in this audit, and the corresponding `Known gaps` entry in
`OVERVIEW.md`, are withdrawn.

**Jev's own consistency here is poor:** it flags the numeric-chunk family but not the 19
near-identical named-chunk families (`style_css`, `css`, `index_css`, `async_js`, …) that fail in the
same suites with the same message. One verdict per error line, applied to a whole family, is a
pointer, not proof.

### §2 — `ENOENT … open 'test/js/<case>/bundle.js'`

**What fails.** The test harness opens the compiled test bundle and the file is not there. 7,415
fingerprints across 5,857 families, but only **33 runs** — i.e. whole-suite cascades, not isolated
defects.

**Causal evidence.**

1. **Windows, not scattered commits.** The 33 runs fall into twelve short windows on consecutive
   commits: 2021-03-15, 2021-06-23, 2021-09-23, 2021-10-05, 2023-03-20 (×6, package-type / loader
   work), 2024-10-09 (×8, Container Reference Hoisting), 2024-10-22 (×3, asset-module entrypoints),
   2024-10-31 (×2, the acorn refactor — the known-broken `b5209044` / `79b8f00e`), 2024-11-12
   (`0ab5b9e0`, uncommitted `.check.js`), 2024-11-29, 2025-04-22. A missing build step in our image
   would fail identically on every commit, not in windows.
2. **The window's own error is in the log.** On `755bf161b` (2024-10-09) every case dies on
   `TypeError: ModuleFederationPlugin.getCompilationHooks is not a function` — a half-landed API
   rename in that commit. The test case cannot compile, so no bundle is emitted and the harness then
   reports the ENOENT.
3. **Consistent with the human label.** All 7,415 fingerprints are `acceptable` under rules
   `abb4f7704625` (7,263) and `bec5be79ccb5` (152), i.e. the human pass had already classified the
   windows as commit-era.

**Verdict.** Jev's `missing_build_step` names the right *symptom* and the wrong *cause*: nothing is
missing from the image — the case never compiled because the commit itself was broken. **Upstream
defect**, `acceptable` stands, documented as a compile cascade.

### §3 — Blocks whose only message is `test/js/<case>/bundle.js:<line>`

**What fails.** 741 families / 777 fingerprints / **16 runs**, all `acceptable` (rules
`21f4d3ea6aa5`, `0f495ddf5c5a`, `43f9588b43ca`, `9e8368f1039d`, `dedf4865f93d`).

The detection block for these contains no message at all:

```
● TestCases › production › scope-hoisting › reexport-star-external-cjs › … should load the compiled tests

test/js/production/scope-hoisting/reexport-star-external-cjs/bundle.js:120
```

**Runs.** Short feature-branch windows only: 2021-02-10 (×2), 2021-03-15 (×3), 2022-01-25/26 (×3,
`importMeta` section), 2023-06-03 (×5, `importMetaName` work), 2024-01-24 (inner graph), 2024-10-02
(module chunk-format fallback), 2024-11-13 (wasm loading). Same shape as §2 — a compile break inside
a commit, reported at the location of the throw.

**Verdict.** **Upstream defect**, `acceptable` stands.

**Tooling defect exposed here.** 844 fingerprints (2.3 % of the CSV) carry a `<path>:<line>` line as
their only "message". `error_line()` accepts it as the family key, so one commit-era breakage splits
into hundreds of families (`bundle.js:120`, `bundle.js:132`, …). Those 741 families stand for roughly
20 real signatures. **Decision (2026-10-30): recorded, not fixed** — skipping a bare location as a key
would merge them, but it invalidates the current representatives and changes the artifact for no
labelling gain, since every one of them is already `acceptable`.

### §4 — Hot-backend losses (`ECONNREFUSED`, `ECONNRESET`, `No update available`)

**What fails.** A `HotTestCases*` file loses its hot backend: the client dials a port the backend has
chosen but is not accepting on.

```
FAIL test/HotTestCasesWeb.test.js
  ● HotTestCases › web › define › issue-6962 › issue-6962 should compile
    Problem communicating active modules to the server: connect ECONNREFUSED 127.0.0.1:40009
  ● HotTestCases › web › css › with-lazy-compilation › exported tests › should work
    No update available
```

**Blast radius (log-derived, not DB-derived).** 22 runs, each carrying exactly one of:

| signature | runs |
|---|---|
| `ECONNREFUSED 127.0.0.1:<ephemeral>` only | 5 |
| `ECONNREFUSED` + `No update available` | 9 |
| `ECONNRESET` + `No update available` | 2 |
| `No update available` only | 6 |

**5 runs on 2021-05-31** (one day, consecutive commits) and **17 runs spread over 2025-05 → 2025-11**
on isolated commits.

**The port data identifies the mechanism.** Fourteen distinct ephemeral ports, each appearing exactly
twice in its log — so it is not a fixed-port collision and not a stale listener: the client connects
before the backend listens. The failing file varies: across the 22 logs `HotTestCasesWeb` 24,
`HotTestCasesAsyncNode` 18, `HotTestCasesNode` 16, `HotTestCasesWebWorker` 12 occurrences (several can
fail in one run), i.e. whichever hot file is in flight when the backend drops.

**Flake, measured on same-commit re-runs** (7,679 original/re-run pairs, any hot suite):

| year | pairs | P→F | F→P | F→F | P→P | flip % |
|---|---|---|---|---|---|---|
| 2021 | 1,983 | 1 | 21 | 36 | 1,925 | 1.1 % |
| 2022 | 847 | 3 | 16 | 5 | 823 | 2.2 % |
| 2023 | 1,688 | 22 | 47 | 64 | 1,555 | 4.1 % |
| 2024 | 2,394 | 46 | 78 | 30 | 2,240 | 5.2 % |
| 2025 | 767 | 19 | 42 | 5 | 701 | 8.0 % |

`F→P` is inflated by our own environment fixes landing between original and re-run, so the honest
"still unstable" figure is `P→F`: 91 commits that passed and later failed. Corroboration from the
other direction: of the 17 DB-flagged 2025 runs, **9 now show a passing hot suite in the current log**
(the DB accumulates detections across repeated runs of a commit, while `logs/` holds only the latest).

**Coverage.** Unaffected — affected run `50119bb9b` has HMR `LH 509 / 535`, identical to its
neighbours before and after.

**Verdict.** 2021-05-31 is a commit-era window; the 2025 half is a **confirmed test-side race** in the
hot harness, covered by none of our code and costing no coverage. Not a pipeline defect.

**Action taken (2026-10-30).** All 22 runs archived to
[`archive/hot_backend_flake_rerun/`](../../archive/hot_backend_flake_rerun/) and re-run on an idle box
at 5 workers, starting 30 minutes after babel/opencrvs-core finished and after gatsby's container build
(`~/.local/share/coverage_reloaded/webpack_rerun.sh`).

**Re-run result (2026-10-30 20:01 → 21:11).** 22/22 commits produced coverage, no `.error`; per-suite
coverage matches the archived originals on **61/61 suite pairs (median ΔLH 0.00 %, range −0.01 % …
+0.14 %)**.

| group | runs | hot-backend failure reproduced |
|---|---|---|
| 2025 (2025-05 → 2025-11) | 17 | **0 / 17** — gone |
| 2021-05-31 window | 5 | **5 / 5** — reproduced |

The split therefore holds: 2025 is a **timing flake** that disappears without contention; 2021-05-31 is
a deterministic commit-era window. The 17 re-run commits now fail only `WatchTestCases.longtest.js`,
i.e. §1. Caveat: at an ~8 % flake rate, seventeen consecutive clears would have probability ≈ 0.24, so
the re-run alone is not proof — the both-direction flip history (91 `P→F` vs 204 `F→P`) is what makes
the load/timing reading solid.

### §5 — `workerPublicPath` window (two families, one era)

Two Jev families fire on the same branch:

| | set A | set B |
|---|---|---|
| families / fingerprints | 35 / 35 | 30 / 30 |
| runs | 15 | 13 |
| span | 2022-01-25 → 2023-02-09 | 2023-01-25 → 2023-02-09 |
| subsystem | `node_runtime_syntax` 31, `module_resolution` 4 | `missing_build_step` 18, `module_resolution` 12 |
| signature | test-name fallback, block is only `Errors while compiling:` | `Cannot find module 'test/js/<case>/__webpack_require__.p1.bundle.js'` |

Both are the `workerPublicPath` refactor: the window opens at `0df564bc9 Make workerPublicPath optional
and update docs` (2023-01-25) and closes at `0d91c55f7` (2023-02-09), during which the worker cases
cannot find the emitted worker bundle. Set A additionally carries 2022-01-25 (the `importMeta`
section) and the two 2024-10-31 acorn commits, both already classified.

Set A's blocks carry no message at all (`Errors while compiling:` and nothing else), so Jev fell back
to the test name and produced 31 families for one window — the same detection weakness as §3, and the
reason this cluster looks larger than it is.

**Verdict.** **Upstream defect** (feature-branch window), `acceptable` stands; already documented in
`OVERVIEW.md` under the workerPublicPath window.

### §6 — The tail (110 remaining flagged runs)

| cluster | runs | span | shape |
|---|---|---|---|
| `ConfigCacheTestCases › css › css-modules[*]` | 11–12 | 2023-04-25 · 2024-10-31 · 2024-11-07 → 11-19 | generic `Errors while compiling:` |
| `TestCases › cache pack › scope-hoisting › side-effects-*` | 12 | 2022-02-24 → 2024-10-31 | test-name fallback |
| wasm `_wasm_wat_*.getNumber is not a function` | 9 | 2021-12 → 2023-06 | real error line |
| `Cannot find module '../../../js/config/dll-plugin/manifest0.json'` | 9 | 2021-12 → 2024-11 | uncommitted fixture |
| wasm `Out of memory` (jest-27 branch) | 8 | 2021-06 → 2021-07 | documented in `OVERVIEW.md` |
| singletons | ~50 | all | one commit each |

Common structure: every one of them lands on a feature-branch window — the css-modules runs sit on
`feat: implement CssModule` (2023-04-25 ×3) and the `@value` CSS work (2024-11-07 → 11-19), plus the
known-broken acorn commits and `0ab5b9e0` — or on a single already-classified commit. Most carry
`env_subsystem = none`, i.e. Jev itself could not attribute them to an environment subsystem, and
their confidence sits at 0.5–0.6, barely above the decision threshold.

**Verdict.** **Upstream defect**, `acceptable` stands. No container change is indicated.

## Conclusion

All 7,180 Jev-flagged families (10,525 fingerprints on 2,125 of 2,642 failing runs) reduce to six
families of cause, and **none is a pipeline defect that changes the exposure variable**:

- chunk-load failures misattributed to the watch suites (§1) — dangling `import()` in
  `ConfigCacheTestCases`, no coverage effect, phase 1 fixed upstream in `1f0d77484`;
- compile cascades inside broken commits (§2, §3, §5, §6) — upstream defects on feature windows;
- hot-backend loss (§4) — a timing flake (0/17 reproduced on an idle re-run) plus a deterministic
  2021 window; no coverage effect;
- documented single-cause items (wasm OOM on the jest-27 branch, uncommitted fixtures).

Jev is right that these runs *failed*; it is wrong about *why* in the cases where it names a subsystem.
`missing_build_step` in particular is systematically misapplied: nothing is missing from the image —
the commit never compiled, so no bundle was emitted. The two clusters where the label alone would have
misled are §1 (2,039 runs, `none`) and §2 (7,415 fingerprints, `missing_build_step`) — together 77 % of
the flagged runs.

**No work order follows.** The two candidate pipeline defects Jev proposed (a missing build step, a
container/network problem) do not exist: the first is a compile cascade, the second is an ephemeral-port
race inside the hot test harness.

## Label outcome

Unchanged from the human pass: **33,270 `acceptable`**, **3,326 `reevaluated_acceptable`**, **0
`problematic`** in both windows. The 10,525 Jev-flagged fingerprints are Jev false positives relative
to the human labels, with the single exception of §4, which is a real (but environment-side, non-fatal)
test flake and is now under re-run. The one labelling artefact this audit adds is the `Known gaps`
entry for §1 — an unknown persistent error with no effect on coverage.
