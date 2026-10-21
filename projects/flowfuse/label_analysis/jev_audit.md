# Jev audit — flowfuse

**Source:** `label_analysis/failure_labels_jev_min_dedup.csv` (automated System 1
labels, dedup-keyword mode), cross-checked against
`label_analysis/failure_labels_project_min.csv` and the project's git history.

**Snapshot:** mode `dedup-keyword`; Jev rows 760; flagged 42; Jev `labeled_at` max
`2026-10-21T21:48:22.764477+00:00`; human fingerprints 20288; human `labeled_at` max
`2026-10-21T21:46:17.422610+00:00`.

The audit was performed on 2026-10-20 against the 758-family artifact. The Jev file
was regenerated on 2026-10-21 after the failure-detection re-anchoring; that run
produced 760 families and the flagged set is unchanged (42). No re-analysis was
performed for this record.

Jev flags 42 of 760 families, all at confidence 0.50–0.79, across `forge_unit` (31),
`system` (6), `unit` (4) and the frontend suite (1). Each flag was checked against
the project's git history and the human labels: all 42 are genuine upstream developer
mistakes at the failing commit or human-confirmed false positives (application console
output captured as a failure). None traces to the container, the harness, the registry
mirror or the runner configuration, so no `install-and-run.sh` or Dockerfile change is
required.

Nine flagged rows cannot be expanded to a family in the current human CSV. Six differ
only by the 120-character truncation of the stored `keyword`; their fingerprints are
present and labeled in `failure_labels_project_min.csv`. The remaining three
(`b0d05a3ece86bc0c`, `52c5fabe586dd0d8`, `eec8b93a5faf3cb3`) are representatives of
the pre-2026-10-21 frontend `FAIL <path>` anchoring that was re-anchored onto the
`Error: [vite-node]` line; the same upstream defect is covered by the current families.

**Conclusion:** no Jev flag traces to the pipeline. The affected fingerprints are
labeled `acceptable`, `reevaluated_acceptable` or `false_positive` in
`failure_labels_project_min.csv`.
