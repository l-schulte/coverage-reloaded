# Pipeline & Project Details

> Referenced from `AGENTS.md §2`. Read for deeper understanding of the collection pipeline, container layers, WayPack, LCOV validation, and per-project structure.

## Pipeline: host → container → output

```
HOST                                          CONTAINER
main.py (orchestrator)
  ├─ collect_commits.py  (once/project) ──► commits.csv, additional_information.csv,
  │                                          command_changes.csv
  └─ collect_coverage.py (per commit)
        └─ docker_run.py → docker-run.sh
              ├─ build core_node<N>_base           (Dockerfile)
              ├─ build core_node<N>_<proj>         (projects/<p>/Dockerfile)
              └─ docker run … bash execute.sh ──►  execute.sh
                                                     ├─ git checkout $revision
                                                     ├─ configure npm/yarn/pnpm → WayPack
                                                     ├─ patch lockfile URLs → WayPack
                                                     ├─ timeout 5400s bash ../install-and-run.sh
                                                     │     ├─ install deps (via WayPack)
                                                     │     ├─ run tests w/ coverage
                                                     │     └─ bash ../find-and-move-lcov.sh
                                                     ├─ count/validate lcov.info (0 → exit 1)
                                                     ├─ lcov --add-tracefile → merged.lcov
                                                     └─ mv merged.lcov → /coverage_reloaded/coverage/<hash>.lcov
```

**Output (host):** `projects/<name>/output/<hash>.lcov` (success) or `<hash>.error` (failure); logs at `projects/<name>/logs/node<N>_<ts>_<hash>.{log,error}`. First log line is the exact `docker-run.sh` command to reproduce.

**External prerequisite:** WayPack Machine compose stack must be running on `mining-net` Docker network.

**`main.py` modes:** `full` | `commits-only` | `coverage-only` | `single-commit --commit-hash`

`collect_coverage.py` skips commits with existing `.lcov`, deletes stale `*.error`, shuffles commits (avoid temporal bias), runs through `ThreadPoolExecutor`.

## Container layers & runtime

| Layer | Dockerfile | Tag | Contents | Built |
|---|---|---|---|---|
| **Base** | `./Dockerfile` | `core_node${N}_base` | debian:bullseye-slim + git/curl/wget/make/build-essential/cmake/jq/zip/nano, libfaketime, lcov, `uv`-managed Python, `n`, `CI=true`, 4 shared scripts | once per Node ver (16/18/20/22) |
| **Project** | `projects/<p>/Dockerfile` | `core_node${N}_<proj>` | `FROM` base + system deps, `COPY ./repo`, `COPY ./install-and-run.sh` | first run per project |
| **Runtime** | (in `docker-run.sh`) | — | `docker run` instance | every commit |

**Runtime flags:** `--network mining-net --cap-add=NET_ADMIN --dns 1.1.1.1 --dns 8.8.8.8 --pids-limit 10000`, env file + `revision`/`timestamp`/`package_manager`/`project_id`, volume `projects/<p>/output:/coverage_reloaded/coverage`.

## WayPack Machine

Temporal registry: serves each package **as it existed at the commit's timestamp**. Routes:
- `/npm/<ts>/<pkg>`, `/yarn/<ts>/<pkg>`, `/pip/<ts>/<pkg>`
- `/request/<url>` (generic proxy/cache)
- `/local/<path>`, `/local_config`

**Local overrides:** drop `.config.json` in `waypack-machine/local_files/` to redirect a tarball to a local file.

**`fake-time.sh`** wraps a command with libfaketime (`FAKETIME` from `$timestamp`).

## LCOV output & validation

**`find-and-move-lcov.sh` signature:**
```bash
bash ../find-and-move-lcov.sh [TEST_TYPE] [PREPEND_PATHS] [TEST_EXIT_CODE]
# $1 TEST_TYPE       — label → filename (e.g. "unit" → unit.lcov.info)
# $2 PREPEND_PATHS   — "true" for workspace monorepos
# $3 TEST_EXIT_CODE  — stored as <TEST_TYPE>.exit_code sidecar
```

Finds all `lcov.info` under `$REPOPATH` (excluding `node_modules`), strips `$REPOPATH` and `co_re_*` prefixes from `SF:` lines, optionally prepends workspace-relative paths, moves to `$COVERAGE_REPORT_PATH`. **Exits 1 if no `lcov.info` found.**

**Validation chain:** `execute.sh` counts → 0 = exit 1 → `find-and-move-lcov.sh` exits 1 → `docker_run.py` writes `.error` → `collect_coverage.py` skips.

**Danger states (pass naive checks):**
- Empty `lcov.info` (0 lines) — BAD
- Partial from bail — BAD
- Partial from non-bail test failure — valid partial, WARNING-acceptable

## `command_changes.csv` — design-time reference

Shows full history of `package.json` script changes: one row per unique `(script_name, script_definition)` pair with earliest commit, plus removal rows (blank definition). Schema: `commit_hash, timestamp, script_name, script_definition`

> ⚠️ Removal rows record the commit where blank state was observed, not necessarily where the script was removed. Always verify by inspecting `git show <hash>:package.json` at boundary commits.

Use alongside `git show` on representative commits to validate branching logic. Runtime branches must be driven by what is actually **present in the checked-out commit**.

## Per-project files & env vars

**Required per `projects/<name>/`:** `Dockerfile` · `install-and-run.sh` (executable) · `commits.csv`, `additional_information.csv`, `command_changes.csv` (generated) · `output/`, `logs/`, `repo/` (generated).
**Optional:** `commits_postprocess.py` · `fixed/` (`.error` skip-list).
**Shared root scripts** (edit only if all projects benefit): `execute.sh`, `docker-run.sh`, `find-and-move-lcov.sh`, `fake-time.sh`, `logging.sh`, `main.py`, `Dockerfile`.

### State env vars

| Var | Meaning |
|---|---|
| `revision` | commit SHA to checkout |
| `timestamp` | commit epoch seconds (drives fake-time) |
| `package_manager` | e.g. `npm@8`, `yarn@1.22`, `pnpm@6` |
| `project_id` | project identifier |
| `IS_{NPM,YARN,PNPM}_MAIN_PM` | `true`/`false` — branch on these |
| `WAYPACK_{NPM,YARN}_REGISTRY` | `http://waypack:3000/{npm,yarn}/<ts>/` |
| `REPOPATH` | `/coverage_reloaded/repo` |
| `COVERAGE_REPORT_PATH` | `/coverage_reloaded/exported` |
| `OUTPUT_PATH` | `/coverage_reloaded/coverage` |
| `CI` | `true` (no interactive mode) |
