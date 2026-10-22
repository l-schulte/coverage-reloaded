# Jev audit — sequelize

**Source:** `label_analysis/failure_labels_jev_min.csv` (fingerprint mode)
**Snapshot:** mode `fingerprint`; rows `87`; flagged `is_pipeline_issue == True` `5` (`ports_and_networking`: `2`, `none`: `2`, `runner_env_config`: `1`); Jev `labeled_at` max `2026-10-22T15:42:00.492034+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-22T14:41:56.838060+00:00`; fingerprints `87`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|:---:|---|---|---|
| DB2 Adapter Error Test Output | 2024-04-05 `05860c1e9b4ec9c122e451b91179b4c4636f1164` | 1 | `ports_and_networking` | `console.log(error.message)` during passing negative test assertion in `packages/core/test/integration/sequelize.test.js:144` (`triggers the actual adapter error`). Jev statelessly mistook DB2 socket timeout stdout for a dead service. | upstream defect / false positive |
| DB2 Deadlock / Lock Timeout (SQL0911N) | 2024-04-09 `abca3e1c27a7f66b0e5d8d70b10b60c426ccba4b` | 2 | `none` | Flaky DDL lock contention during post-test schema cleanup (`clearDatabaseInternal` dropping foreign keys via `Promise.all` in `test/integration/support.ts`). Affected 12 runs; suite executed 580 passing tests without bail. | upstream defect |
| MariaDB Connection Timeout | 2025-01-23 `a64c807298e43f19d9399b6ad0797c8b390fabe2` | 1 | `ports_and_networking` | Transient socket creation timeout (>999ms) in `beforeEach` hook of `packages/core/test/integration/model/create.test.js:220` hammering 50 concurrent `findOrCreate` calls. Affected 1 run; 1,821 tests passed without bail. | upstream defect |
| MSSQL CREATE DATABASE File Failure | 2024-12-21 `0272bd7f4c563c8b5c0cfd906d3ee86ea02d569a` | 1 | `runner_env_config` | Database file creation collision (`CREATE DATABASE dummy_db`) in `list-tables.test.ts:63`. Affected 1 run; 1,801 tests passed without bail. | upstream defect |

## Conclusion

0 confirmed pipeline defects and 5 commit-era upstream defects / benign negative test outputs. Zero Jev flags trace to our container environment, harness, or registry mirror. All 87 fingerprints represent valid, non-bailed test executions with complete coverage collection.

## Label outcome

- Remaining `acceptable`: 85
- Reclassified `reevaluated_acceptable`: 2 (`0a5c363498450e66` DB2 test stdout, `766f4d60473a8e92` Postgres port RangeError test stdout)
- Remaining `problematic`: 0 in active runs (rule `96c1ad357c23` retained in `failure_patterns.json` for flake tracking; 1 flaked commit archived to `archive/rerun_mysql_deadlock_flake/` and re-run cleanly)
