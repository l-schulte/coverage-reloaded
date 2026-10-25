# Jev audit — wowanalyzer

**Source:** `label_analysis/failure_labels_jev_min_dedup.csv` (dedup-keyword mode)
**Snapshot:** mode `dedup-keyword`; rows `4380`; flagged `is_pipeline_issue == True` `11` (`runner_env_config`: `11`); Jev `labeled_at` max `2026-10-25T16:32:01.256099+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-25T16:44:29.368421+00:00`; fingerprints `29076`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| Jest 27 `setImmediate` in integration tests | 2022-02-10 `88676a7f7a` | 28 | runner_env_config | Author bumped `react-scripts` to v5 (`8196e64a6e`) which bundled Jest 27. Jest 27 dropped the `setImmediate` polyfill from JSDOM, causing `ReferenceError: setImmediate is not defined` inside `decompress-unzip`/`yauzl`. Upstream author Martijn Hols fixed this in `src/setupTests.js` via `ee89b88547` (*"fix: Fix integration tests — Jest 27 removed setImmediate polyfill"*). | upstream defect |

## Conclusion

0 confirmed pipeline defects and 11 commit-era upstream defects (28 covered fingerprints across 12 union runs).
No Jev flag traces to the container, harness, Verdaccio proxy, or registry mirror.

## Label outcome

- Remaining `acceptable`: 24,358
- Reclassified `reevaluated_acceptable`: 4,688
- Remaining `false_positive`: 30
- Remaining `problematic`: 0
- Remaining `unclear`: 0
