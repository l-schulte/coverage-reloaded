# uwazi

**Repository:** https://github.com/huridocs/uwazi
**Status:** active

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `uwazi`).
- **Node strategy:** override Node 16 → `14` for epoch `1626742218`–`1659708655`.
- **Runners:** `jest`.
- **Eras:** jest `24.8.0` → `27.5.1` → `29.7.0`. Suites run with `--maxWorkers=2 --forceExit --testTimeout=60000` (matching upstream CI `--maxWorkers=2` to prevent internal port 6379 and file collision between concurrent suites while isolating V8 compilation-cache heap leaks across ~800 suites without container sharding).

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
- [x] complete JEV test failure check (Jev CSV in fingerprint mode with 165 flagged fingerprints; audited in [`label_analysis/jev_audit.md`](label_analysis/jev_audit.md))

## Results

Source: `stats_output/report.txt` (generated 2026-11-08 23:21).

| Metric | Value |
|---|---|
| Commits processed | 8907 |
| Without test failures | 5414 |
| With test failures | 3465 |
| Not applicable | 0 |
| Hard errors | 28 |
| Coverage produced | 99.7% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Failure triage

Source: `python check_failures_v2.py uwazi --stats` (window `min`, run 2026-11-08) and
`stats_output/report.txt` (generated 2026-11-08 23:21). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | 3465 |
| Failing runs (label DB) | 3449 (`failing runs` line) |
| Fingerprints (min / max) | 2675 / 3123 |
| Labeled fingerprints | 2675 (100.0%) |
| Unlabeled fingerprints | 0 |
| acceptable | 1843 |
| reevaluated_acceptable | 832 |
| problematic | 0 |
| unclear | 0 |
| false_positive | 0 |
| Manual / auto-propagated labels | 147 / 2528 |
| Labeled detections (min) | 20546/20546 (100.0%) |
| Labeled runs (min) | 3449/3449 (100.0%) |
| Jev mode | fingerprint |
| Jev pipeline issues | 165 flagged rows |
| Jev audit | current |

**State:** complete. *(Note: 16 runs exited with code 1 due to obsolete Jest snapshot warnings rather than test assertion failures, accounting for the 3,449 vs 3,465 run-count difference; 100.0% of detected failing runs are assessed and labeled.)*

## Environment / setup fixes

- **Jest worker concurrency standard (`--maxWorkers=2`) and temporary elevation recovery:** `--maxWorkers=2` was and remains the permanent baseline standard for general runs in [`install-and-run.sh`](install-and-run.sh), matching upstream CI (`.github/workflows/ci_api_unit_tests.yml: yarn test app/api --coverage --maxWorkers=2`). This avoids container port 6379 binding races and Redis lock contention across ~800 suites. In August 2022 / early 2023 commits with ~460–730 suites, Jest child workers sequentially executing >300 suites per worker under Istanbul/Babel coverage hit V8's hard 4096 MB pointer-compression address ceiling (`FatalProcessOutOfMemory` in `AllocateCode(bool)`), causing 90-minute container timeout deadlocks. A batch of 16 affected runs was temporarily elevated to `--maxWorkers=5` / `--maxWorkers=10` to split the suite load into smaller per-worker batches (<150 suites/worker, keeping heap usage under 1.5 GB). All 16 runs completed successfully to full coverage (11 passing cleanly with exit code 0, 0 hard errors), after which [`install-and-run.sh`](install-and-run.sh) was immediately restored to `--maxWorkers=2` as the safer choice for all general runs.
- **Transient network timeout archiving (Docker Hub, Elastic artifacts, and GitHub Releases):** Archived 24 runs affected by transient outbound network/DNS drops during parallel container execution (15 Docker Hub timeouts pulling `lazybit/minio` or Elasticsearch base images, 5 GitHub releases asset download timeouts for `sharp-libvips`, and 4 Elastic artifacts DNS resolution failures for `analysis-icu`) into [`archive/transient_network_timeouts/`](archive/transient_network_timeouts/) for clean re-run.
- **GitHub unauthenticated API timeout incident archiving:** Archived 71 commits affected by the official GitHub infrastructure incident ([pyynvrm1vskw](https://www.githubstatus.com/incidents/pyynvrm1vskw), 10:36–11:56 UTC) into [`archive/github_outage_unauthenticated_timeouts/`](archive/github_outage_unauthenticated_timeouts/). The degradation caused 503 Service Unavailable and 502 Bad Gateway timeouts on unauthenticated release asset downloads (`sharp-libvips`, `electron`, `canvas`, and Elasticsearch plugins) during dependency installation. Commits vacated for clean re-run following GitHub's upstream mitigation.
- **Unclear singletons archiving (`entities.spec.js` and `MongoDataSource.spec.ts`):** Archived 2 commits (`1620749563_11baf845` with a duplicate key error in `entities.spec.js` on a 240-file merge commit, and `1741700460_56ab248f` with a transient 30s Mongoose server selection timeout on a tree-identical commit) into [`archive/rerun_unclear_singletons/`](archive/rerun_unclear_singletons/). Commits vacated for verification re-run to distinguish transient test-environment flake from authentic developer regression.
- **Permissions filters ES hook timeout archiving (`permissionsFilters.spec.ts`):** Archived 3 commits affected by a 20s `beforeAll` hook timeout in `app/api/search/specs/permissionsFilters.spec.ts` into [`archive/permissions_filters_es_hook_timeout/`](archive/permissions_filters_es_hook_timeout/). The timeout occurred during Elasticsearch index fixture setup (`permissionslevelfixtures`) under container worker contention, skipping all tests in the file and causing an artificial 15-line coverage deficit across `app/api/search/metadataAggregations.js`, `documentQueryBuilder.js`, and `search.js` (confirmed measurement bias against neighboring clean runs). Commits vacated for clean re-run.
- **S3FileStorage 60s timeout archiving (`S3FileStorage.spec.ts`):** Archived 1 commit (`1737954470_7971a67f`) affected by an isolated 60s timeout on an AWS S3 `PutObjectCommand` promise under container worker contention into [`archive/rerun_s3_filestorage_timeout/`](archive/rerun_s3_filestorage_timeout/) for clean re-run under `--maxWorkers=2`.
- **Redis restart persistence, connection race, and lock timing archiving (`taskManager.spec.ts` / `distributedLoop.spec.js`):** Archived 14 commits affected by Redis test execution artifacts into [`archive/rerun_redis_persistence_and_lock_races/`](archive/rerun_redis_persistence_and_lock_races/). 10 runs failed from unshimmed Redis restart persistence timeouts (missing RDB save points in older executions), 3 runs from the 100ms connection wait race (`Redis is not connected`), and 1 run (`8d011d51b`) from a 250ms sleep reconnect flake under worker load. All are resolved under the active [`redis-server-shim.sh`](redis-server-shim.sh) and `--maxWorkers=2` baseline; vacated for clean re-run.
- **TaskManager Redis connection race archiving (`taskManager.spec.ts`):** Archived 15 commits affected by a transient Redis connection race in `app/api/services/tasksmanager/specs/taskManager.spec.ts` into [`archive/task_manager_redis_connection_race/`](archive/task_manager_redis_connection_race/). The test's `beforeAll` relied on a fixed 100ms sleep (`setTimeout(resolve, 100)`) that intermittently expired before `RedisClient` finished handshaking, throwing `Redis is not connected` and causing an artificial 3-line coverage deficit in `app/api/services/tasksmanager/TaskManager.ts` (confirmed measurement bias against neighboring clean runs). Commits vacated for clean re-run; re-runs passed to valid coverage (`8f057947` with exit code 0).
- **CSV loader thesauri hook timeout archiving (`csvLoaderSelects.spec.js`):** Archived 42 commits affected by a 10s `beforeAll` hook timeout in `app/api/csv/specs/csvLoaderSelects.spec.js` into [`archive/csv_loader_selects_hook_timeout/`](archive/csv_loader_selects_hook_timeout/). The timeout occurred during heavy fixture setup (MongoDB cleanup, Elasticsearch index recreation, and CSV translation parsing) under container worker contention, aborting all 9 tests in the suite and causing an artificial 34-line coverage deficit in `app/api/csv/arrangeThesauri.ts` (confirmed measurement bias). Commits vacated for clean re-run.
- **Concurrent batch network timeout archiving:** Archived 470 commits affected by transient external network timeouts during parallel container startup (177 Elasticsearch `analysis-icu` plugin downloads from `artifacts.elastic.co`, 108 WayPack proxy 502 gateway timeouts, 96 `sharp-libvips` binary downloads from GitHub releases, and 92 Docker Hub token/manifest timeouts from `registry-1.docker.io`, plus 1 aborted startup run) into [`archive/rerun_batch_network_timeouts/`](archive/rerun_batch_network_timeouts/) for clean recovery re-run under low concurrency.
- **ICU Arabic localized date formatting alignment (macOS vs Linux CLDR divergence, Oct 2023+):** In commit `281662856` ("Replace moment.js", PR #6188), `app/react/V2/shared/specs/dateHelpers.spec.ts` introduced an assertion expecting `secondsToDate(1696624527, 'ar')` to equal `'٦ أكتوبر ٢٠٢٣'` (Eastern Arabic numerals). On the developer's macOS environment, system ICU defaults generic Arabic (`'ar'`) to Eastern Arabic digits (`nu-arab`). On Linux containers (Debian Bullseye), standard Node ICU/CLDR defaults `'ar'` to Latin digits (`"6 أكتوبر 2023"`), causing an assertion failure across 2,731 subsequent commits. Patched [`install-and-run.sh`](install-and-run.sh) to specify the Unicode numbering system extension (`sed -i "s/'ar'/'ar-u-nu-arab'/" app/react/V2/shared/specs/dateHelpers.spec.ts`), aligning Linux ICU output with the developer's environment without mutating expected values.
- **Jest worker concurrency reduction to `--maxWorkers=2` and soft failure archiving:** Aligned Jest execution in [`install-and-run.sh`](install-and-run.sh) from `--maxWorkers=10` down to `--maxWorkers=2`, matching upstream CI (`.github/workflows/ci_api_unit_tests.yml: yarn test app/api --coverage --maxWorkers=2`). This eliminates internal container port 6379 binding races between `socketClusterMode.spec.ts` and `distributedLoop.spec.js`, as well as shared Redis lock contention and filesystem fixture races. Set `"container_cpus": 6` in [`config.json`](../../config.json). Archived 4,870 historical soft failure runs into [`archive/rerun_all_soft_failures/`](archive/rerun_all_soft_failures/) for clean re-run.
- **Redis persistence for self-spawned servers (RedisServer / downloadRedis era, Oct 2021 – Sep 2022):** this era's tests spawn their own `redis-server` instances and rely on the dataset surviving a SIGINT restart; `taskManager › should read pending messages` writes a results message, kills the server, restarts it and expects the message to still be queued. The `redis-server` shipped in the image is compiled without upstream's default save points (a bare `redis-server --port N` reports an empty `save` and exits without writing `dump.rdb`), so every restart came up empty and the test failed deterministically in **1,692 of 1,692 executions** where it ran — not intermittently; the sibling `should send tasks again` intermittently reported `queueNotFound: Queue not found` (61 runs) for the same reason. `install-and-run.sh` now installs [`redis-server-shim.sh`](redis-server-shim.sh) (copied into the image by the `Dockerfile`) at every path the era's helpers resolve; the stub execs the packaged binary with the upstream save points (`3600 1`, `300 100`, `60 10000`), a per-port `--dir /tmp/redis-state/<port>` and a per-port `--logfile`, so a restart restores its own dataset and concurrent instances cannot overwrite each other's `dump.rdb`. 1,696 runs archived to [`archive/rerun_redis_save_points/`](archive/rerun_redis_save_points/) and the pilot run to [`archive/fix_redis_save_points/`](archive/fix_redis_save_points/) for re-run; the pilot commit re-ran to `exit_code=0` (641/641 suites, 3,996/3,996 tests).
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
