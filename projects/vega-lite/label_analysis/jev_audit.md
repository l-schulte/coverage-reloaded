# Jev audit — vega-lite

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)  
**Snapshot:** mode `fingerprint`; rows `2`; flagged `is_pipeline_issue == True` `0`; Jev `labeled_at` max `2026-10-22T08:56:29.555300+00:00`  
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T08:56:10.860604+00:00`; fingerprints `2`)

## Flagged fingerprints

No flagged fingerprints.

## Conclusion

0 confirmed pipeline defects and 0 commit-era upstream defects flagged by Jev. Jev agreed 100% with the human labels, evaluating both failure fingerprints as genuine application test failures (`is_pipeline_issue = False`, confidence 0.88–0.90). No Jev flag traces to the container, harness, or registry mirror.

## Label outcome

Remaining `acceptable`: 2. Reclassified `reevaluated_acceptable`: 0. Remaining `problematic`: 0.
