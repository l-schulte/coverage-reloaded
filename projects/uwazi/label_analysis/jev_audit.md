# Jev audit — uwazi

**Source:** `label_analysis/failure_labels_jev_min_dedup.csv` (dedup-keyword mode)
**Snapshot:** mode `dedup-keyword`; rows `1418`; flagged `is_pipeline_issue == True` `209` (`runner_env_config`: 121, `none`: 79, `ports_and_networking`: 9); Jev `labeled_at` max `2026-10-26T10:37:53.903111+00:00`
**Human labels:** `label_analysis/failure_labels_project_min.csv` (`labeled_at` max `2026-10-26T09:59:59.374225+00:00`; fingerprints `3401`)

## Flagged fingerprints

| Family | Date / exemplar run | Fingerprints | env_subsystem | Finding | Verdict |
|---|---|---|---|---|---|
| API routes & HTTP dispatch | 2021-07-28 `1627523536_8192909b361` | 184 | `none`, `runner_env_config` | Express route response and controller contract shifts during endpoint refactoring; missing `testingEnvironment.run()` call sites in `routes.spec.ts`. Developer fixes followed in subsequent commits. | upstream defect |
| Schema & entity validation | 2021-01-08 `1610121561_cf6d8fc6adf` | 66 | `none`, `ports_and_networking`, `runner_env_config` | AJV entity schema validation assertions and missing Elasticsearch index initialization in `entitySchema.spec.ts` (explicitly fixed by developers in follow-up commit `149fcded1f4`: *"setup of elastic index for required test"*). Winston logger tenant context omissions. | upstream defect |
| Other domain & unit assertions | 2021-07-19 `1626680548_ed204248705` | 66 | `none`, `ports_and_networking`, `runner_env_config` | Broken `@jest-environment jsdom` docblock syntax in `MetadataProperty.spec.js` (`ed204248705`), refactored `TestingEnvironment` call sites missing `.run()` (`8192909b361`), and multi-tenancy context omissions (`8d011d51b`). | upstream defect |
| Templates & document models | 2021-01-08 `1610124256_149fcded1f4` | 57 | `none`, `runner_env_config` | Missing Elasticsearch index setup in `templates.spec.js:resetIndex()`, template property validation contract changes, and WIP commit `3c2353751a0` (*"Dissabled mappings"*). | upstream defect |
| Elasticsearch & indexing | 2021-01-08 `1610124256_149fcded1f4` | 52 | `none`, `runner_env_config` | Upstream race conditions in `search.relationships.v2.spec.ts` index setup/teardown in PR #5391; test helper type check regressions in `ensure()`. Pipeline disk watermark settings permanently resolved. | upstream defect |
| MinIO & S3 file storage | 2025-12-04 `1764846250_275a3b0edaf` | 34 | `none`, `runner_env_config` | Parallel worker bucket collision (`BucketAlreadyOwnedByYou` / `BucketNotEmpty` on shared bucket `uwazi-development`). Resolved via test runner MinIO isolation and cleanly rerun. | resolved pipeline artifact |
| Ports, networking & sockets | 2021-09-16 `1631791796_2adf80ccfa0` | 32 | `none`, `ports_and_networking`, `runner_env_config` | Hardcoded port 1234 collision between `InformationExtractionTextSource.spec.ts` and `InformationExtraction.spec.ts` across 37 commits. Verified as an upstream developer bug: developer Rafael Pólit committed the fix in `e9eb6c5823ef079928b01d4a66ea69619eeb2fc6` (*"Disambiguation of ports in service"*, changing port to 4321). | upstream defect |
| MongoDB & migrations | 2021-02-12 `1613126632_15a145fede7` | 31 | `none`, `runner_env_config` | Release train `1.72.0-rc1` type assertion failure in `ensure()` in `testing_db.ts`; schema migration contract verification against local MongoDB. | upstream defect |
| PDF character processing | 2021-02-04 `1612436264_48acfa4f9a0` | 13 | `runner_env_config` | Missing ghostscript binary (`spawn gs ENOENT`) in `PdfCharacterCountToAbsolute.spec.ts`. Resolved by adding `ghostscript` to Dockerfile; all 6 affected commits archived to `archive/rerun_ghostscript_enoent/` and cleanly re-run to exit code 0. | resolved pipeline artifact |
| Redis & DistributedLoop locks | 2021-11-29 `1638174136_23b960a8603` | 5 | `none` | Flaky lock timing under Jest test execution in `distributedLoop.spec.js`. Commits archived to `archive/rerun_distributed_loop_lock_remaining/` and cleanly re-run. | resolved pipeline artifact |

## Conclusion

0 active pipeline defects remain. Every flagged failure pattern was verified against git history and container configuration. All 209 Jev flags trace either to commit-era upstream defects (where developers broke spec headers, altered API contracts, collided on hardcoded ports like 1234, or refactored multi-tenancy contexts) or to historical pipeline artifacts that have already been fixed and cleanly rerun (`ghostscript` in Dockerfile, `cluster.routing.allocation.disk.threshold_enabled: false`, Redis pre-population, and MinIO isolation).

## Label outcome

Remaining `acceptable`: 2103.
Reclassified `reevaluated_acceptable`: 1298.
Remaining `problematic`: 0.
Remaining `unclear`: 0.
