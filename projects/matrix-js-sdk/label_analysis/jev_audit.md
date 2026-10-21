# Jev audit — matrix-js-sdk

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; Jev rows 310; flagged 44; Jev `labeled_at` max `2026-10-21T14:48:18.370242+00:00`; human fingerprints 1247; human `labeled_at` max `2026-10-21T14:46:45.322494+00:00`.
**Human labels:** `label_analysis/failure_labels_project_min.csv`

## Flagged fingerprints

The Jev snapshot evaluated 310 fingerprints across failing runs. 44 carry `is_pipeline_issue == True`, spanning 14 union runs. All 44 verdicts were audited against git history and proven to be genuine commit-era developer mistakes or short-lived author branch issues (Hypothesis B) rather than container or pipeline defects:

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| `Cannot find module .../client` | 2021-06-02 `8a1d34c419` | 1 (7 runs) | `missing_build_step` | Author Travis Ralston temporarily renamed `src/client.js` to `src/1client.ts` during intermediate branch commits before restoring it as `src/client.ts`. | upstream defect |
| `TypeError: Cannot read property 'init' of undefined` & `E2EE not supported: load olm` | 2021-05-21 `56a2eeac77`; 2024-08-06 `4e2831764d` | 24 (4 runs) | `runner_env_config` (23), `module_resolution` (1) | Hubert Chathi bumped the olm package name without updating `spec/olm-loader.js` (fixed 24 minutes later in `9e30c4f7d`); Michael Telatynski accidentally dropped `@matrix-org/olm` during merge `4e2831764` (restored 14 minutes later in `8c3b24956`). | upstream defect |
| Jest environment hint / `ReferenceError: navigator is not defined` | 2022-02-18 `7a249e3ef5` | 19 (3 runs) | `runner_env_config` | Robert Long introduced `navigator.mediaDevices.addEventListener` without a Node environment guard in `src/webrtc/mediaHandler.ts` (reverted/moved 5 days later in `17f5ab41917`). | upstream defect |

## Conclusion

No Jev flag traces to the container, harness, or registry mirror: 0 confirmed pipeline defects. All 44 flagged fingerprints — a union of 14 distinct runs — attribute to upstream developer errors. No work order for `install-and-run.sh` or `Dockerfile` is required.

## Label outcome

All 44 flagged fingerprints correspond to genuine upstream defects and are classified as `acceptable` (25) or `reevaluated_acceptable` (19) in `failure_labels_project_min.csv`. Remaining `problematic`: 0.
