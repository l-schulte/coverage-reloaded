# uwazi

**Repository:** https://github.com/huridocs/uwazi
**Status:** active

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `uwazi`).
- **Node strategy:** override Node 16 → `14` for epoch `1626742218`–`1659708655`.
- **Runners:** `jest`.
- **Eras:** jest `24.8.0` → `27.5.1` → `29.7.0`. Suites run with `--maxWorkers=10 --forceExit --testTimeout=60000` (worker isolation prevents V8 compilation-cache heap leaks across ~800 suites without container sharding).

## Development style

- **PR merging strategy:** Transitioned / Dual merge (Merge commit in 2021 → Squash and merge for feature PRs post-2021 + Merge commit for production release trains).
- **Merge convention:** `<Title> (#<PR>)` for feature PRs; `vX.Y.Z` (e.g., `v1.228.0`) for release merges into `production`.
- **Direct commits:** Minimal human (2.5%, 45 commits); moderate bot (25.1%, 446 commits).
- **JS/TS code impact of direct commits:** Negligible — small batching logic hotfixes and console cleanup.
- **Issue tracking discipline:** High (features and bugfixes mapped to GitHub issues).
- **Workflow notes:** Dual-branch model where features squash into development, and milestone releases merge into `production`.

## Coverage collection

- **Suites collected:** the behavioral suite, with coverage.
- **Suites excluded:** none.
- **Coverage tool / config:** runner-native coverage.
- **LCOV production:** jest `lcov` reporter.
- **Services:** Elasticsearch via Docker-in-Docker, MongoDB 7.0 (replica set for 2022+ / bundled 4.4.8 for MMS era), and `redis-server`.

## Checklist

- [x] 100 done (97/100)
- [x] failed tests doublechecked (failures below are known; none are bails)
- [x] complete run
- [x] complete test failure check
- [x] complete JEV test failure check (Jev CSV in dedup-keyword mode with 209 flagged families; audited in label_analysis/jev_audit.md)

## Results

Source: `stats_output/report.txt` (generated 2026-10-26 12:26).

| Metric | Value |
|---|---|
| Commits processed | 8907 |
| Without test failures | 2736 |
| With test failures | 6146 |
| Not applicable | 0 |
| Hard errors | 25 |
| Coverage produced | 99.7% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py uwazi --stats` (window `min`, run 2026-10-26) and
`stats_output/report.txt` (generated 2026-10-26 12:26). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 6146 |
| Failing runs (label DB) | 6132 (`failing runs` line) |
| Fingerprints (min / max) | 3401 / 3908 |
| Labeled fingerprints | 3401 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 2103 |
| reevaluated_acceptable | 1298 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 191 / 3210 |
| Labeled detections (min) | 27740/27740 (100.0%) |
| Labeled runs (min) | 6132/6132 (100.0%) |
| Jev mode | dedup-keyword |
| Jev pipeline issues | 209 flagged rows (families in dedup-keyword mode) |
| Jev audit | current |

**State:** complete. *(Note: 14 runs exited with code 1 due to obsolete Jest snapshot warnings rather than test assertion failures, accounting for the 6,132 vs 6,146 run-count difference; 100.0% of detected failure patterns are assessed).*

## Environment / setup fixes

- **DistributedLoop Redis lock contention archiving:** Archived 6 commits affected by Redis lock timing under Jest test execution (`distributedLoop.spec.js`) in [`archive/rerun_distributed_loop_lock_remaining/`](archive/rerun_distributed_loop_lock_remaining/) for clean re-run.
- **Ghostscript binary installation & archiving:** Added `ghostscript` to Dockerfile (`PdfCharacterCountToAbsolute.spec.ts` depends on `gs` binary to calculate PDF character positions). Archived 6 affected historical commits from Feb 2021 (`spawn gs ENOENT`) in [`archive/rerun_ghostscript_enoent/`](archive/rerun_ghostscript_enoent/) for clean re-run; all 6 passed with exit code 0.
- **Transient WayPack 502 recovery:** Archived 1 commit (`bff5feade8cb`) affected by transient proxy gateway failure during yarn install in [`archive/rerun_transient_502/`](archive/rerun_transient_502/) and cleanly re-ran to valid coverage.

- **MinIO concurrent bucket collision archiving (round 2):** Archived 2 commits affected by `BucketNotEmpty: The bucket you tried to delete is not empty` collisions during parallel execution of `S3FileStorage.spec.ts` and `storage.spec.ts` sharing bucket `uwazi-development` in [`archive/rerun_minio_bucket_collision_round2/`](archive/rerun_minio_bucket_collision_round2/) for re-running.

- **Hardcoded spec timeout archiving:** Archived 3 commits affected by transient timing flakiness under hardcoded 10s spec limits (`distributedLoop.spec.js` test timeout on Redis lock release in `2ba2ce1d29bc` and `e75a9cb018c9`; and `csvLoaderSelects.spec.js` 10s `beforeAll` hook timeout in `722a82e6fcb1`) in [`archive/rerun_hardcoded_spec_timeouts/`](archive/rerun_hardcoded_spec_timeouts/) for clean re-run.

- **Elasticsearch flood-stage disk watermark archiving:** Archived 91 commits executed on remote host `132.231.141.24` where host root partition usage exceeded 95% (`/dev/nvme0n1p2` at 98%), triggering Elasticsearch's internal disk watermark allocator (`cluster_block_exception: [TOO_MANY_REQUESTS/12/disk usage exceeded flood-stage watermark, index has read-only-allow-delete block]`) and causing write failures in `syncWorker.spec.ts` as well as 20000 ms `beforeAll` setup timeouts in `search.spec.js`. Added `"cluster.routing.allocation.disk.threshold_enabled": false` to Elasticsearch cluster settings in [`install-and-run.sh`](install-and-run.sh) and relocated all 91 runs to [`archive/rerun_elasticsearch_disk_watermark/`](archive/rerun_elasticsearch_disk_watermark/) for clean re-run on the main local server.

- **MinIO concurrent bucket collision archiving:** Archived 4 commits affected by `BucketNotEmpty: The bucket you tried to delete is not empty` collisions during parallel execution of `S3FileStorage.spec.ts` and `storage.spec.ts` sharing bucket `uwazi-development` (`27128e9ffcbf`) in [`archive/rerun_minio_bucket_collision/`](archive/rerun_minio_bucket_collision/) for re-running.

- **DistributedLoopLock timeout archiving:** Archived 81 commits affected by timeouts in `DistributedLoopLock` under parallel worker load (`e81cd96b12c0cfa7` [10s, 46 runs], `64d40a3156eb` / `76b5cac200b3a3e0` [60s, 7 runs], Sub-family A [60s, 5 runs], and `a1153096937a`/`80e03705029f` DistributedLoopLock runs [60s, 23 runs]) in [`archive/rerun_distributed_loop_lock_timeout/`](archive/rerun_distributed_loop_lock_timeout/) for re-running.

- **Flaky timeout commit archiving:** Archived 108 commits affected by isolated flaky test timeouts on hardcoded hook limits and worker event timing (`f0b3053f037a`, `5b3f8f4e383b`, `80e03705029f`, `a1153096937a`) in `archive/rerun_flaky_timeouts/` for re-running.
- **Container CPU allocation:** Raised from 6 to 12 CPUs (`"container_cpus": 12` in `config.json`, supported in `src/config.py` and `src/docker/docker_run.py`) to eliminate CPU contention on 10s worker timeouts (3,207 affected logs archived in `archive/fix_num_workers/`).
- **Jest 24 60s timeout hook:** In Jest 24.8.0, CLI `--testTimeout` is ignored. Added an era-aware hook in `install-and-run.sh` injecting `jest.setTimeout(60000)` into `app/setUpJestServer.js` and `app/setUpJestClient.js` (1,809 affected logs archived in `archive/fix_jest_timeout/`).
- **CI MinIO image:** Dynamic fallback to `lazybit/minio` when `minio/minio` is unavailable.
- **Debian Bullseye dependencies:** Added `[trusted=yes]` for `security.debian.org` to resolve `gnupg` repository signature issues.
- **Ghostscript package:** Installed `ghostscript` in `Dockerfile` for PDF character position calculations (`PdfCharacterCountToAbsolute.spec.ts`).
- **Redis binary pre-population:** Extended `install-and-run.sh` to recognize `RedisServer.ts` (pre-Oct 2021) and pre-populate `redis/redis-stable/src/redis-server`, preventing failed `make` compilation and port 6379 binding collisions. Archived 49 remaining affected commits in `archive/rerun_redis_makepopulation/` for re-run.
- **MinIO S3 detection:** Expanded test file detection in `install-and-run.sh` to include `storage_s3_upload_on_read.spec.ts`, `storage_read.spec.ts`, `s3Storage.spec.ts`, and `files.v2` S3 specs, preventing connection refused errors on port 9000. Archived 32 remaining affected commits in `archive/rerun_minio_s3/` for re-run.
- **Test fixture cleanup collision under monolithic execution (`syncWorker` / `FileSystemStorage`):** In commit `cd12226df` (Nov 2025+), `FileSystemStorage.spec.ts` introduced an `afterAll` hook calling `testingEnvironment.cleanupUploadPaths()`. Because it called `setTenant()` rather than `setUp()`, `uploadSubPath` defaulted to an empty string (`""`), causing `cleanupTestUploadedPaths('')` in `app/api/files/filesystem.ts` to unlink all files in the shared root `specs/uploads/` and `specs/customUploads/` directories. In upstream CI (`.github/workflows/ci_unit_tests_docker.yml`), this test collision never occurred because Jest tests were partitioned across 4 isolated Docker containers via `--shard=${{ matrix.shard }}/4`, meaning `FileSystemStorage.spec.ts` and `syncWorker.spec.ts` ran in completely separate containers and never shared a filesystem. In our pipeline, executing all suites in a single container with `--maxWorkers=10` caused `cleanupTestUploadedPaths('')` to delete fixture files (`customUpload.gif`, `test.txt`, `test2.txt`) from under `syncWorker.spec.ts` while it was executing concurrently. Patched `install-and-run.sh` to guard `cleanupTestUploadedPaths` so it only cleans when a non-empty `subPath` is provided (`if (!subPath) return;`). Archived 134 affected commits (including `c4ebfc986fd470d6`) in [`archive/rerun_syncworker_cleanup_collision/`](archive/rerun_syncworker_cleanup_collision/) for re-run.
- **Elasticsearch shard ceiling:** After Elasticsearch is ready, raise `cluster.max_shards_per_node` to 10000 via a persistent `_cluster/settings` update, so suites that create many indices no longer fail with `validation_exception ... this action would add N total shards`. Archived affected commits in `archive/rerun_es_shard/` and `archive/rerun_es_shard_fix/` for re-run.
- **Redis binary-path mirror:** Extended `install-and-run.sh` to pre-populate `redis-server` next to every `RedisServer.ts` / `downloadRedis.js` found under `app` (excluding `node_modules`), preventing post-`make` binary-path failures and port 6379 binding collisions. Archived affected commits (including 5 commits affected by cross-worker `read ECONNRESET` and `Address already in use` under `taskManager.spec.ts`) in `archive/rerun_redis_redisbin/` and `archive/rerun_redis_timeouts/` for re-run.
- **MinIO detection (`storage.spec.ts`):** Extended S3 test-file detection in `install-and-run.sh` to include `app/api/files/specs/storage.spec.ts`, preventing `ECONNREFUSED 127.0.0.1:9000`. Archived affected commits in `archive/rerun_minio_storage_spec/` for re-run.
- **GitHub asset DNS pinning:** `install-and-run.sh` now sources `resolve-and-pin.sh` and pins `release-assets.githubusercontent.com`, `objects.githubusercontent.com`, and `codeload.github.com` in `/etc/hosts`, eliminating `EAI_AGAIN` failures during electron/sharp/canvas postinstall binary downloads. Archived 176 affected commits in `archive/dns_eai_again/` for re-run.
- **Transient hard-error recovery:** Two archive-and-re-run passes (`archive/rerun_transient_infra/`, 228 runs; `archive/retry_round2/`, 5 runs) recovered commits lost to one-off infra flakiness during install: WayPack 502/ResponseError tarball fetches, Docker-in-Docker image pull/build timeouts (`docker.elastic.co` via the `docker-multi-cache` proxy, `registry-1.docker.io`), Elasticsearch plugin-install DNS (`artifacts.elastic.co`), and electron/sharp postinstall downloads. A 6-commit probe re-run confirmed the transient attribution (5 of 6 families recovered with no code change); the 25 unrecoverable runs are documented under Known gaps.

## Known gaps

25 hard errors remain. All three families are commit-era developer mistakes that any clean install reproduces (upstream CI fails identically), so re-running cannot recover them:

| Cause | Runs | Detail |
|---|---|---|
| `@babel/eslint-parser` pinned to `7.11.6` | 16 (2021-05-21 to 2021-05-24) | `package.json` pins a version that was never published to npm — only 7.11.0/.3/.4/.5 exist, verified against both the WayPack temporal snapshot at the failing timestamp and the full current registry snapshot; the `yarn.lock` entry is self-contradictory (key `@7.11.6`, resolved tarball `7.11.5`). Fixed upstream in `a7004a899` ("fix babel/eslint-parser version", 2021-05-30, pinned 7.11.5). |
| Corrupt committed `package.json` | 5 (2024-08-05, 2024-08-14, 2024-08-20) | `SyntaxError: package.json: Expected double-quoted property name / Expected ',' or '}' after property value` — `4ae87cc50` shipped unresolved merge-conflict markers, and four release-candidate commits shipped a missing comma after the `version` line. Fixed upstream the same day in `07534627a` ("Fix package json"), `2f22c8e3e` ("fix package json"), and `9d07c44f0` ("fix package.json"). |
| jest reporter crash — `TypeError: stripAnsi is not a function` | 4 (2024-09-23) | Dependency-tree incompatibility in the committed lockfile: `@jest/reporters/build/Status.js` calls `string-length`, which calls a `strip-ansi` version that is not callable. The crash occurs entirely inside `node_modules` (no coverage produced). All four runs fall in the "Merge back from production and Bump rc version" window. |
