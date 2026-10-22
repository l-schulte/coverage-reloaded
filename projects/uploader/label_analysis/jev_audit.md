# Jev audit — uploader

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)  
**Snapshot:** mode `fingerprint`; rows `82`; flagged `is_pipeline_issue == True` `1` (`runner_env_config`: `1`); Jev `labeled_at` max `2026-10-22T08:04:52.704299+00:00`  
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T08:06:58.502926+00:00`; fingerprints `82`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| Electron 12 `remote.getGlobal` deprecation | 2021-02-12 `59005b9343c057b2f52eb762568744e13b714c21` | 1 | `runner_env_config` | Deprecation of `electron.remote` during Electron 12 migration in `59005b9343c057b2f52eb762568744e13b714c21`; author resolved in follow-up commit `6e330bf4e9513b46b4cf903d385c730c154bdf00` (*"switch to @electron/remote"*) | upstream defect |

## Conclusion

0 confirmed pipeline defects and 1 commit-era upstream defect.
Zero Jev flags trace to the container, harness, or registry mirror.

## Label outcome

Remaining `acceptable`: 81. Reclassified `reevaluated_acceptable`: 1. Remaining `problematic`: 0.
