# Jev audit — pf2e

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)  
**Snapshot:** mode `fingerprint`; rows `68`; flagged `is_pipeline_issue == True` `1` (`runner_env_config`: `1`); Jev `labeled_at` max `2026-10-22T07:50:36.292364+00:00`  
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T07:49:06.295917+00:00`; fingerprints `68`)  

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| Un-shimmed `BaseItemDataPF2e` in obsolete test suites | 2022-03-07 `1646692728_dfde0852f057c4a2d5168f918bf9c0d8d143ec96` | 1 | `runner_env_config` | Commit `dfde0852f057` refactored damage files, importing `BaseItemDataPF2e` into un-shimmed test suites (`modifiers.test.ts` and `runes.test.ts`), triggering `ReferenceError: foundry is not defined`. Author deleted `runes.test.ts` 35 mins later in `549d70ea4f70` and deleted `modifiers.test.ts` in `eb35c85ad562`. | upstream defect |

## Conclusion

0 confirmed pipeline defects and 1 commit-era upstream defect.  
No Jev flag traces to the container, harness, or registry mirror.

## Label outcome

Remaining `acceptable`: 20.  
Reclassified `reevaluated_acceptable`: 13.  
Remaining `problematic`: 0.
