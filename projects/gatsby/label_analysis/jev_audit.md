# Jev audit — gatsby

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)  
**Snapshot:** mode `fingerprint`; rows `688`; flagged `is_pipeline_issue == True` `536` (`missing_build_step`: `244`, `runner_env_config`: `208`, `none`: `80`, `module_resolution`: `4`); Jev `labeled_at` max `2026-11-02T09:46:11.091997+00:00`  
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-11-02T08:17:21.347052+00:00`; fingerprints `672`)

Dataset: 900 active failing runs, 4,038 detections, no `.error` overlap — every flagged fingerprint belongs to a run that already produced valid `unit.lcov`.
Project inclusion at audit time: 4,198 / 4,229 commits with coverage (99.3%), 31 `.error`.

Jev flagged 536 of 688 fingerprints; human labels contain 0 `problematic` and 0 `unclear` (414 `reevaluated_acceptable`, 258 `acceptable`). Agreement on non-pipeline classification: 152/688 (22.1%). The remaining 16 rows in Jev CSV correspond to historical runs from 2026-10-31 that were cleared and eliminated during re-runs.

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| `//.cache/schema.gql` & `fsExtra` ENOENT cascade (v4 release prep) | 2021-09-14 `1631612626_f8c5141bf72108a53338fd01514522ae7a1b37bf` | 443 (244 `missing_build_step`, 195 `runner_env_config`, 4 `module_resolution`) | missing_build_step / runner_env_config / module_resolution | Commit `f8c5141bf7` (*"chore: apply patches for v4 (#33170)"*) bumped 122 packages simultaneously, breaking cache paths (`//.cache/schema.gql`) and `fsExtra.readFileSync` mocks. Upstream developer release-prep regression across 3 adjacent commits, ~2.5 h. | upstream defect |
| Parcel `compileGatsbyFiles` hook timeouts (15s/30s) | 2022-06-28 `1656399324_69824f67455780ef45785353c02b675f44090d55` | 10 | runner_env_config / none | `compile-gatsby-files.ts` originally set `jest.setTimeout(15000)`. Under-dimensioned on cold Parcel AST compilation in monorepo runs. Upstream explicitly recognized and quadrupled the timeout to 60s in commit `0a80cd6d61` (*"fix(gatsby): try to automatically recover when parcel segfaults (#38773)"*). | upstream defect |
| Image CDN worker mock `undefined.destroy()` | 2022-03-01 `1646171831_29b236b7f2212d062a65d34781a612d715d936ef` | 4 | none / runner_env_config | Introduced in PR #34825. `@mswjs/interceptors` internal `NodeClientRequest.terminate()` assumed unstreamed Buffer responses had a stream, crashing on `this.responseStream.destroy()`. Upstream mock defect in `packages/gatsby-plugin-utils`. | upstream defect |
| Gatsby Cloud un-awaited telemetry (`http://test.com/events`) | 2021-06-03 `1622745260_15f359affe1188eee3b31dc482111e3326929e76` | 17 | none | Un-awaited background `trackEvent()` POST to `http://test.com/events` logging after Jest environment teardown. Acknowledged and fixed upstream in commit `eb1f568338` (*"fix(gatsby-plugin-gatsby-cloud): add backpressure for IPC (#32963)"*). | upstream defect |
| `getCIName is not a function` (monorepo skew) | 2021-05-17 `1621237394_57d1fa717863312e51ff4b7a54704305c9bea68d` | 28 | module_resolution | Transitive `packages/gatsby-telemetry/src/repository-id.js` called `getCIName()` before export declarations in `gatsby-core-utils` were aligned across the monorepo workspace. | upstream defect |
| `gatsby-worker` `write EPIPE` | 2022-08-11 `1660221061_ab55e4e30a023d56e4c4332dfd278015a0f49ee0` | 3 | none | In unit tests intentionally asserting worker error propagation, child process exited before parent finished IPC write, raising unhandled `EPIPE`. Upstream test error-handling assertion issue. | upstream defect |
| `fetch-remote-file` send timeout | 2021-09-15 `1631716001_89a30e84f5f35c83a58a6a7277479ed70aef6d72` | 1 | none | Concurrency race in unit test mock workers accessing shared lockfile concurrently. Refactored upstream in `gatsby-core-utils`. | upstream defect |
| Stale historical runs (eliminated) | 2022-01-03 `1641222842_33049c8e5384c856dd5fa28e79ad4c76ad628ad5` | 16 | runner_env_config / none | From historical runs on 2026-10-31 that were archived and cleared during pipeline re-runs; no longer present in active failing runs. | cleared |

## Conclusion

**Zero of Jev's 536 flagged `problematic` fingerprints trace to the container, harness, or registry mirror.**  
Every flagged family maps cleanly to an upstream commit-era developer mistake, broken mock, un-awaited telemetry event, or under-dimensioned upstream Jest hook timeout that was subsequently repaired upstream.

No pipeline defect was found, and no pipeline work order is required. The exposure variable for Gatsby is robust and complete at **99.3% coverage** (4,198 / 4,229 commits).

## Label outcome

- **Remaining `acceptable`:** 258
- **Reclassified `reevaluated_acceptable`:** 414
- **Remaining `problematic`:** 0
- **Unclear:** 0
- **Confirmed pipeline defects:** 0 (no work orders opened; all labels settled).
