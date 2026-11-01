# Jev audit — babel

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `223`; flagged `is_pipeline_issue == True` `100`
(`module_resolution`: 77, `runner_env_config`: 12, `none`: 8, `node_runtime_syntax`: 3);
Jev `labeled_at` max `2026-10-31T16:22:42.821273+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max
`2026-10-31T16:23:07.076278+00:00`; fingerprints `223`)

Snapshot history: at audit time the human CSV held `226` fingerprints and Jev had
evaluated 223 of them. The 3 unevaluated ones (`3d4a02def1…`, the 14-run
`BINARY_OPERATORS` flaky build-order family whose runs are archived in
`archive/flaky_incomplete_lib_build_r2/`; `e696785f…`, 1 run, `@babel/eslint-parser`
parsing error; `6f9479ba…`, 1 run, `WorkerClient.receiveMessageOnPort` TypeError)
were dropped as stale by the 2026-11-01 label-DB rebuild after those runs went green
or were superseded. The human CSV and the Jev CSV are at exact row parity (`223`
/ `223`); the flagged set is unchanged. The Jev file was not regenerated.

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| `Cannot find package 'babel-plugin-proposal-class-*'` in decorators 2023-05 fixtures | 2023-05-22 `79fa18149e`, `920b78c0` | 77 | module_resolution | PR #15570 landed fixtures whose `options.json` referenced the renamed `proposal-*` plugin packages (gone on the Babel 8 branch). Upstream fixed it the same day: `ced7be82b9` "Fix tests after merging PRs" renames them to `transform-*` (9 files) — that run is green. | upstream defect |
| `Test suite failed to run` + fixture `ReferenceError: require is not defined` (regenerator fixtures CJS-in-ESM) | 2025-03-28 `928f8050`, `97105cb9`, `b953a8fb` | 12 | node_runtime_syntax (3) + runner_env_config (9) | PR #17205 landed in stages: regenerator's CJS fixtures moved into the `"type": "module"` `babel-plugin-transform-regenerator` package while upstream's `testRegex` collected them. The PR's own final commit `ab3fef3d61` adds `test/regenerator-fixtures/package.json` = `{"type":"commonjs"}` — green. Jev over-split one root cause across two subsystems. | upstream defect |
| `babel-cli --watch` fixture `EXECUTOR TIMEOUT` | 2022-02 → 2024 (120 runs) | 1 | runner_env_config | The fixture's hard-coded first-watch-build wait (5000 ms, widened to 120000 ms by `install-and-run.sh`) elapses before the watcher fires on Node 16; plausibly because the repo is copied to an in-memory `/coverage_reloaded/repo` and `--watch` depends on fs events. All affected runs still yield full valid `unit.lcov` (23598/23599 tests passing, bail disabled) — valid partials. Assessed and **accepted** 2026-10-31 (see `assessment.md` / `OVERVIEW.md`); no viable fix within budget. | env-sensitive, accepted (not a pipeline defect in effect) |
| `Requires Babel "^7.16.0", but was loaded with "7.15.8"` in safari-id-destructuring plugin tests | 2021-10-29 `e33186c6` | 2 | runner_env_config | `e33186c6` "Pre-release updates" raises the plugin's `api.assertVersion("^7.16.0")` while `packages/babel-core/package.json` still says 7.15.8 — a deterministic release-prep inconsistency. Fixed 39 s later by the release commit `45308f3cba` "v7.16.0" — green. Only run of 47 neighbors showing the mismatch. | upstream defect |
| `TypeError: babel.loadOptions is not a function` (8 fp: `@babel/register > babel 7` + `bin/babel-node` tests, incl. downstream `SyntaxError: Unexpected token / in JSON`) | 2022-01-11 `db08d945` | 8 | none | `db08d945` (#14136) changed `babel.loadOptionsSync(...)` → `babel.loadOptions(...)` in `babel-register/src/worker/transform.js`, but the compat facade `worker/babel-core.js` never exports `loadOptions`. Fixed 27 min later by `928f06ca` "Follow up to #14136 (#14137)" (`new babel.OptionManager().init(...)`) — green. Only red run of 64 neighbors. | upstream defect |

## Conclusion

**0 confirmed pipeline defects.** No Jev flag traces to the container, harness, or
registry mirror: four of the five families are commit-era upstream breakage with the
author's own fix commit green in our run set (39 s – 24 h after the breaking commit),
and the fifth is an already-accepted, coverage-neutral environment limitation. Jev's
stateless view consistently reads the module-resolution and module-type symptoms as
pipeline issues; git history contradicts it in 99 of 100 flagged fingerprints.

## Label outcome

No label changes from this audit. Remaining `acceptable`: `142` (incl. the 11
fingerprints of the `--watch`, pre-release-window, and `loadOptions` families —
human verdicts confirmed here). Reclassified `reevaluated_acceptable`: `0` by this
audit (`80` from the same-day `assessment.md` pass remain). Remaining `problematic`:
`0`. No work orders — `install-and-run.sh` and `Dockerfile` need no changes.
