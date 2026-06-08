# AGENT.md — Causal Coverage Collection

> Primary reference for any coding agent modifying this codebase. Read fully before changing anything.
> Every line encodes a design constraint. Your main deliverable per project is **`install-and-run.sh`**.

---

## Contents

1. [Purpose & success criteria](#1-purpose--success-criteria)
2. [Pipeline: host → container → output](#2-pipeline-host--container--output)
3. [Host vs. container — critical distinction](#3-host-vs-container--critical-distinction)
   - [3.1 What you can run, and where](#31-what-you-can-run-and-where)
   - [3.2 Inspecting files at a commit with git](#32-inspecting-files-at-a-commit-with-git-host)
4. [Container layers & runtime](#4-container-layers--runtime)
5. [WayPack Machine](#5-waypack-machine)
6. [Writing `install-and-run.sh`](#6-writing-install-and-runsh)
7. [⚠️ THE BAIL RULE + exit-code handling](#7-️-the-bail-rule--exit-code-handling)
8. [Coverage scope & suite exclusions](#8-coverage-scope--suite-exclusions)
9. [LCOV output & validation](#9-lcov-output--validation)
10. [Era detection & `command_changes.csv`](#10-era-detection--command_changescsv)
11. [Per-project files & env vars](#11-per-project-files--env-vars)
12. [Onboarding & debugging](#12-onboarding--debugging)
13. [Version determination](#13-version-determination)

---

## 1. Purpose & success criteria

Collects **longitudinal line-based coverage** across the full commit history of mature JS/TS projects. This coverage is the **exposure variable** in a causal study of coverage → bug introduction, so **measurement bias directly threatens validity.**

**Guiding principle:** at each commit, *follow the project's own coverage intent* (c8 → its `.c8rc.json`; nyc → its config) rather than imposing one uniform external tool. Where no coverage tooling exists, wrap the behavioral suite externally with c8/nyc. **Coverage = lines executed by behavioral tests, whether or not the project measured them.**

**Inclusion criterion:** ≥ 90% of a project's last-5-years commits must produce valid coverage.

**Failure must be loud.** A silent/empty/partial file that passes validation is *worse* than an outright failure — it corrupts the exposure variable with no signal. The worst failure mode is a **bailed run** (see §7).

---

## 2. Pipeline: host → container → output

```
HOST                                          CONTAINER
main.py (orchestrator)
  ├─ collect_commits.py  (once/project) ──► commits.csv, additional_information.csv,
  │                                          command_changes.csv
  └─ collect_coverage.py (per commit)
        └─ docker_run.py → docker-run.sh
              ├─ build core_node<N>_base           (Dockerfile)
              ├─ build core_node<N>_<proj>         (projects/<p>/Dockerfile — snapshots repo)
              └─ docker run … bash execute.sh ──►  execute.sh   [shared, do NOT edit]
                                                     ├─ git checkout $revision
                                                     ├─ configure npm/yarn/pnpm → WayPack
                                                     ├─ patch lockfile URLs → WayPack
                                                     ├─ timeout 5400s bash ../install-and-run.sh  ◄── YOUR FILE
                                                     │     ├─ install deps (via WayPack)
                                                     │     ├─ run tests w/ coverage (set +e)
                                                     │     └─ bash ../find-and-move-lcov.sh  [shared]
                                                     ├─ count/validate lcov.info (0 → exit 1)
                                                     ├─ lcov --add-tracefile → merged.lcov
                                                     └─ mv merged.lcov → /coverage_reloaded/coverage/<hash>.lcov
```

**Output (host):** `projects/<name>/output/<hash>.lcov` (success) or `<hash>.error` (failure); logs at `projects/<name>/logs/node<N>_<ts>_<hash>.{log,error}`. First log line is the exact `docker-run.sh` command to reproduce.

**External prerequisite:** the WayPack Machine compose stack must be running on the `mining-net` Docker network before any run (§5).

**`main.py` modes:** `full` | `commits-only` | `coverage-only` (skips done commits) | `single-commit --commit-hash`.

`collect_coverage.py` skips commits with an existing `.lcov`, deletes stale `*.error`, shuffles commits (avoid temporal bias), and runs them through a `ThreadPoolExecutor`.

---

## 3. Host vs. container — critical distinction

> The host and container operate on **different copies of the repo at different commits.** This is the #1 source of debugging confusion.

| | Host (`main.py`) | Container (`execute.sh`) |
|---|---|---|
| Repo | `projects/<name>/repo/`, cloned once, left at clone-time `HEAD` | repo **copied into the image at build time**, then `git checkout $revision` |
| Checks out target commit? | **No** | **Yes** |
| Workdir | `coverage_reloaded/` root | `/coverage_reloaded` |
| WayPack | n/a | yes, `http://waypack:3000` on `mining-net` |

**Implications:**
- To inspect a commit's files on the host, use `git show`/`git ls-tree` (§3.2) — **do not** assume the host working tree is at that commit.
- **The project image snapshots the host repo at `docker build` time.** If you change the host repo (including checking out a different commit), you must rebuild the project image. `docker-run.sh` currently rebuilds on every invocation. The container then runs `git checkout $revision` regardless, so host working-tree state does not affect a coverage run's correctness — but a dirty host tree *is* copied into the image, so keep it clean.
- `collect_commits.py` (whole-history, once) and `collect_coverage.py` (per-commit containers) run on independent timelines.

**Path map (host ↔ container):** `projects/<p>/repo/` ↔ `/coverage_reloaded/repo/`; `projects/<p>/install-and-run.sh` ↔ `/coverage_reloaded/install-and-run.sh`; `projects/<p>/output/` ↔ `/coverage_reloaded/coverage/` (volume); shared scripts (`execute.sh`, `find-and-move-lcov.sh`, `logging.sh`, `fake-time.sh`) live in the base image at `/coverage_reloaded/`.

### 3.1 What you can run, and where

> Before running a command, ask: *does this need WayPack, faketime, the per-commit Node/PM, or installed deps?* If yes, it **only works inside the container.** If it's reading source/history or editing your authored files, do it on the **host.**

**On the host (where you operate directly) — DO:**
- Run **git** against `projects/<name>/repo/` to read history and any file at any commit (§3.2). This is your main way to understand a commit.
- Read/edit the files you author: `install-and-run.sh`, `projects/<p>/Dockerfile`, `config.json`, `commits_postprocess.py`.
- Read generated data: `commits.csv`, `command_changes.csv`, `additional_information.csv`, `logs/`, `output/`.
- Trigger runs: `main.py --mode single-commit --commit-hash <h>` / `--mode coverage-only`.
- Drop into a container: `bash docker-run.sh <p> shell|debug <hash> <ts> <pm> <node>`.

**On the host — DO NOT (it will not work / will mislead you):**
- ❌ `npm/yarn/pnpm install`, `npm test`, `nyc`, `c8`, or any build/test command against the repo. The host has **no WayPack registry, no faketime, and no per-commit Node/PM** — installs hit live npm and tests run against the wrong toolchain. **Dependency install and test execution happen only in the container.**
- ❌ Read a file from the host working tree expecting it to reflect the target commit. The working tree sits at clone-time `HEAD`, not `$revision` (use §3.2 instead).

**Inside the container (only via `docker-run.sh shell|debug`, or during a real run) — DO:**
- Install deps via WayPack, run the behavioral suite with coverage, execute/step through `install-and-run.sh`.
- Inspect the *checked-out* commit at `/coverage_reloaded/repo` (e.g. `node -p "require('./package.json').scripts.test"`). This is the only place "the checked-out commit's state" (§10) refers to.

### 3.2 Inspecting files at a commit with git (host)

The host repo is a normal clone. To see how a file looked at commit `<hash>`, **prefer read-only commands that never touch the working tree** (so you don't dirty the tree that gets copied into the image). Use `git -C` instead of `cd`:

```bash
REPO=projects/<name>/repo

# Print a file exactly as it was at <hash> (no checkout):
git -C $REPO show <hash>:package.json
git -C $REPO show <hash>:package.json | jq '.scripts'          # just the test scripts
git -C $REPO show <hash>:packages/foo/.c8rc.json               # nested / workspace file

# Did a file/dir exist at <hash>?  (exit 0 = yes)
git -C $REPO cat-file -e <hash>:karma.conf.js && echo present
git -C $REPO ls-tree <hash> -- sh/                              # list a dir's contents at <hash>

# List every tracked file present at <hash>:
git -C $REPO ls-tree -r --name-only <hash>

# Context around the commit:
git -C $REPO log --oneline -n 5 <hash>
git -C $REPO show --stat <hash>                                 # what this commit changed
```

This is how you design era branching **before** writing `install-and-run.sh`: read `package.json` scripts and coverage-config presence at several commits across the history (cross-reference `command_changes.csv`, §10) to learn which runners/configs existed when.

**If you genuinely need a working tree** (rare — e.g. running a host-side script): check out, then **restore** so the tree stays clean for image builds:
```bash
git -C $REPO stash --include-untracked          # if anything is dirty
git -C $REPO checkout <hash>
# … inspect …
git -C $REPO checkout -                          # back to the previous branch
git -C $REPO stash pop                           # if you stashed
```
Remember: even after a host checkout, the container re-runs `git checkout $revision` itself — so checking out on the host changes *what the image snapshots*, not what the run measures.

---

## 4. Container layers & runtime

| Layer | Dockerfile | Tag | Contents | Built |
|---|---|---|---|---|
| **Base** | `./Dockerfile` | `core_node${N}_base` | debian:bullseye-slim + git/curl/wget/make/build-essential/cmake/jq/zip/nano, **libfaketime**, lcov (1.14-2), `uv`-managed Python (Node≤12→3.8 else 3.10), `n` (Node mgr), `CI=true`, + 4 shared scripts | once per Node ver (16/18/20/22) |
| **Project** | `projects/<p>/Dockerfile` | `core_node${N}_<proj>` | `FROM` base + system deps (chromium, MySQL, libusb…), `COPY ./repo`, `COPY ./install-and-run.sh`, `WORKDIR /coverage_reloaded` | first run per project |
| **Runtime** | (in `docker-run.sh`) | — | `docker run` instance | every commit |

**Runtime flags:** `--network mining-net --cap-add=NET_ADMIN --dns 1.1.1.1 --dns 8.8.8.8 --pids-limit 10000`, env file + `revision`/`timestamp`/`package_manager`/`project_id`, volume `projects/<p>/output:/coverage_reloaded/coverage`. **Modes:** `exec` (full), `shell` (interactive), `debug` (shell w/ mounted code).

`CI=true` is set globally to keep runners out of watch/interactive mode.

---

## 5. WayPack Machine

Temporal npm/yarn/pnpm/pip registry: serves each package **as it existed at the commit's timestamp**. The container points its package manager at `http://waypack:3000/npm/<timestamp>/`; WayPack fetches metadata via verdaccio→npmjs.org and **filters to versions published on/before the timestamp**.

**Routes:** `/npm/<ts>/<pkg>`, `/yarn/<ts>/<pkg>`, `/pip/<ts>/<pkg>`, `/request/<url>` (generic proxy/cache, e.g. GitHub raw), `/local/<path>`, `/local_config`.

**Local overrides** — drop `.config.json` in `waypack-machine/local_files/` (loaded by `ConfigStore`) to redirect a tarball to a local file or override version metadata. Used for packages deleted/unavailable on npm (e.g. `vitest-mui`).

**`fake-time.sh`** wraps a command with libfaketime (`FAKETIME` from `$timestamp`) for time-sensitive install logic, embedded build timestamps, and time-dependent tests. Requires `$timestamp` (epoch seconds).

---

## 6. Writing `install-and-run.sh`

Runs inside `$REPOPATH` (`/coverage_reloaded/repo`). **Contract:**

- Idempotent; installs **all** deps (coverage tools are usually devDeps → `npm --include=dev` / `yarn --dev`).
- Runs the behavioral suite **with coverage**, producing `lcov.info` file(s) somewhere under `$REPOPATH` (outside `node_modules`) for `find-and-move-lcov.sh` to discover.
- **Branch on `$IS_NPM_MAIN_PM` / `$IS_YARN_MAIN_PM` / `$IS_PNPM_MAIN_PM`** — never guess the PM.
- **Detect eras by inspecting the checked-out commit** (script/file presence), not `command_changes.csv` (§10).
- `set +e` before tests; capture exit code; handle per §7. **No bail flags, ever** (§7).
- Call `bash ../find-and-move-lcov.sh [TEST_TYPE] [PREPEND_PATHS]` after **each** suite.
- `npx` must pin the registry: `npx --registry=$WAYPACK_NPM_REGISTRY nyc …`. Never bare `npx` (pulls latest from npmjs.org).
- **Do NOT modify** `execute.sh`, `find-and-move-lcov.sh`, `logging.sh`.

**Logging discipline:**
- **No `2>&1`** — `docker_run.py` already merges stderr into stdout. It's pure noise.
- **No `| tail`** — logs are the primary debugging artifact and `tail` discards the first/earliest errors. Use `| head` or `| grep` to narrow while keeping the full raw log.

**`find-and-move-lcov.sh`** (shared): recursively finds `lcov.info` (excl. `node_modules`), strips `$REPOPATH` and `co_re_*` prefixes from `SF:` lines, optionally prepends the workspace path when `$2=true`, moves to `$COVERAGE_REPORT_PATH/<rel>/<TEST_TYPE>.lcov.info`. Exits 1 if none found. `$1` = label (becomes filename), `$2` = `PREPEND_PATHS` (pass `true` for monorepos).

**Per-tool strategy** (per the guiding principle, §1):
- **c8 present** → let c8 emit lcov via the project's own `.c8rc.json`.
- **nyc present** → let nyc emit lcov via its own config.
- **No coverage tooling** → wrap the behavioral suite with c8/nyc at defaults; instrument the whole workspace (non-committed files are filtered later).
- **Workspace monorepos** → validate that every package with a `test` script also has coverage config; **fail loudly** on a violation; keep a whitelist for intentionally-excluded tooling packages.

---

## 7. ⚠️ THE BAIL RULE + exit-code handling

> **Tests must NEVER bail. No exceptions.**

A bailed run stops at the first failure, exercising only a fraction of the code, yet produces an `lcov.info` that is **indistinguishable from a clean run** (valid format, real paths, non-zero lines). It silently passes every downstream check. A single bailed commit can corrupt the exposure variable for an entire measurement point with no signal — the most dangerous failure mode in this project.

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Every time you launch a test runner, consciously verify NO bail  ┃
┃ flag exists — in CLI args, config objects, npm scripts you call, ┃
┃ or config files the runner loads. Applies to mocha, jest,        ┃
┃ vitest, lerna, and any other orchestrator.                       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Forbidden anywhere:** `--bail`, `--exit-first`, `--fail-fast`, `bail: true`, `bail: N` (N≥1), `stopOnFailure`.

| Runner | Forbidden | Use instead |
|---|---|---|
| mocha | `--bail`, `bail: true` in `.mocharc` | `--no-bail` (explicit) |
| jest | `--bail`, `bail: true` | omit; remove from any copied config |
| vitest | `bail: N` (N≥1) | `bail: 0` (default) |
| lerna | `--bail` | **`--no-bail`** — *lerna bails by default*, so this is mandatory ([verified](https://www.npmjs.com/package/@lerna/run)) |

**Exit-code handling (mandatory pattern):**
```bash
set -e
# ... install deps, build, etc. (failures here should abort)
set +e                       # failures must not abort the script
<test command with coverage>
TEST_EXIT_CODE=$?            # capture immediately
# 0 or 1  → success / expected test failures: coverage valid → WARNING, continue
# >1      → runner crashed: coverage unreliable → ERROR, exit
bash ../find-and-move-lcov.sh "$LABEL"   # always call, even on partial failure
```
If no lcov files were produced, that is **fatal** (see §9).

**Checklist before any `install-and-run.sh` is done:** no `--bail`/`--exit-first`/`--fail-fast`/`bail:true` anywhere · `--no-bail` present for mocha & lerna · `set +e` before tests · exit code captured immediately · 0/1 = warning, >1 = error · 
set -e at script top (before deps/bootstrap) · `find-and-move-lcov.sh` always called.

### 7.1 Parallelism — prefer serial execution

> Tests run more reliably when not parallelized. Serial execution should be the default.

Many projects spawn child processes (dev servers, build commands, database migrations) during tests. Running test files in parallel multiplies these processes, causing **PID exhaustion**, **port conflicts** (EADDRINUSE), and **thread creation failures** (EAGAIN / `uv_thread_create` assertion). These failures are intermittent and hard to reproduce, making them a major source of measurement bias.

**Rule:** add `--maxWorkers=1` (jest/vitest) or `--runInBand` (jest) to every test invocation in `install-and-run.sh`. This serializes test execution within each suite, keeping resource usage predictable.

Exceptions are rare and must be justified in a comment: only consider parallel execution when the test suite is purely computational (no subprocesses, no network, no file I/O contention) and the speedup is essential for pipeline throughput.

---

## 8. Coverage scope & suite exclusions

> *Added based on the study's stated measurement principle — confirm it reflects current design before relying on it.*

Coverage must reflect **testing**, not rendering. **Exclude suites whose execution exists purely for visual-regression snapshotting** (e.g. Percy- or Vizzly-driven runs) even though they execute large amounts of source — their line hits measure rendering, not behavioral verification, and would inflate the exposure variable. Detect such suites by their runner/script (Percy/Vizzly invocation) and skip them; run and instrument only the behavioral suites.

---

## 9. LCOV output & validation

Final per-commit artifact: `projects/<name>/output/<hash>.lcov` (merged from all `lcov.info`).

**Validation chain:** `execute.sh` counts `lcov.info` in `$COVERAGE_REPORT_PATH` → 0 files = **exit 1** (reports non-empty count separately) → `find-and-move-lcov.sh` exits 1 if none found → `docker_run.py` writes `.error` on non-zero → `collect_coverage.py` skips commits already having `.lcov`. If both `.lcov` and `.error` exist, `.lcov` wins.

**Danger states (all pass naive file-existence checks):**
- **Empty `lcov.info`** (0 lines) — BAD.
- **Partial from bail** (only first file covered) — BAD (see §7).
- **Partial from a non-bail test failure** — valid partial data, WARNING-acceptable.

---

## 10. Era detection & `command_changes.csv`

Projects change test infra over time. Runtime scripts **do not parse `command_changes.csv`** — detect the era by inspecting the **checked-out commit's** state:

```bash
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
echo "$TEST_SCRIPT" | grep -q vitest && ERA=vitest
[ -f karma.conf.js ] && SERVER_ERA=karma
```

`command_changes.csv` is a **reference for you** (the agent) to see the historical sequence of test runners/scripts so you can design branching. **Schema:** `commit_hash,timestamp,script_name,script_definition` — one row per unique `(script_name, script_definition)` pair, annotated with the **earliest** commit it appeared at, sorted by `(script_name, timestamp)`. Generated by `get_command_changes()`: melt `additional_information.csv` to long form, drop empties, sort by `(script_name, timestamp)`, drop duplicate pairs (keeps earliest).

---

## 11. Per-project files & env vars

**Required per `projects/<name>/`:** `Dockerfile` (agent) · `install-and-run.sh` (agent, executable) · `commits.csv`, `additional_information.csv`, `command_changes.csv` (generated) · `output/`, `logs/`, `repo/` (generated).
**Optional:** `commits_postprocess.py` (defines `postprocess()`; fixes bad version assignments) · `fixed/` (`.error` skip-list for unfixable commits).
**Shared root scripts — never edit per-project:** `execute.sh`, `docker-run.sh`, `find-and-move-lcov.sh`, `fake-time.sh`, `logging.sh`, `main.py`, `Dockerfile`.

**State env vars** (Python → docker-run.sh → execute.sh → install-and-run.sh):

| Var | Meaning |
|---|---|
| `revision` | commit SHA to checkout |
| `timestamp` | commit epoch seconds (also drives fake-time) |
| `package_manager` | e.g. `npm@8`, `yarn@1.22`, `pnpm@6` |
| `project_id` | project identifier |
| `IS_{NPM,YARN,PNPM}_MAIN_PM` | `true`/`false` — branch on these |
| `WAYPACK_{NPM,YARN}_REGISTRY` | `http://waypack:3000/{npm,yarn}/<ts>/` |
| `REPOPATH` | `/coverage_reloaded/repo` |
| `COVERAGE_REPORT_PATH` | `/coverage_reloaded/exported` (write reports here) |
| `OUTPUT_PATH` | `/coverage_reloaded/coverage` (final merged `<hash>.lcov`) |
| `CI` | `true` (no interactive mode) |

---

## 12. Onboarding & debugging

**Onboard:** ① add to `config.json` (`url`, `projectID`, `package_manager_priority`, `min_node_version`, `before_date_offset_months`, `workspaces`). ② `main.py --mode commits-only`. ③ write `projects/<p>/Dockerfile` (`FROM core_node${NODE_VERSION}_base`, system deps, `COPY repo` + `install-and-run.sh`, `chmod +x`, `WORKDIR`). ④ write `install-and-run.sh` per §6–§8. ⑤ optional `commits_postprocess.py`. ⑥ test one commit: `--mode single-commit --commit-hash <h>`. ⑦ full: `--mode coverage-only --max-workers N`. ⑧ verify success rate (count `.lcov` vs `.error`).

**Debug a commit:** check `output/<hash>.{lcov,error}`; read `logs/node*_<hash>.*` (first line = reproduce command); or `bash docker-run.sh <p> shell <hash> <ts> <pm> <node>` then step through manually.

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot find module` | WayPack miss for this timestamp | add local override |
| `Z_DATA_ERROR` | lockfile/npm-ver mismatch | bump npm via `commits_postprocess.py` |
| `gyp ERR!` | missing build/system deps | add apt pkgs to project Dockerfile |
| `No lcov.info files found` | no coverage produced | add `--coverage` or wrap nyc/c8 |
| 90-min Timeout | install/tests hang | check interactive prompts / env |
| peer-dep conflict | bad dep tree | `--legacy-peer-deps` / `--force` |
| `Killed` (OOM) | container memory | fewer workers / add swap |

**Silent failure** = exit 0 + lcov produced but no tests actually ran (empty match or **bail**). Cross-check for unusually low line counts and bail patterns in logs.

---

## 13. Version determination

**Node** (priority): `.nvmrc` → `engines.node` → lockfile hints → `.tool-version` → repo Dockerfiles → `build/npm/preinstall.js` → Angular matrix → fallback `node_releases.json` (latest LTS at commit_date − offset).

**Package manager** (priority from `config.json`, default `["pnpm","yarn","npm"]`): lockfile presence picks the candidate, then scan it for version hints.

**PM version** (`from_package_json.py`, first match wins): `packageManager` field (exact, `npm@8.5.0`) → `volta` (exact) → `engines` (semver *range* → highest numeric, `>=7.0.0` → `npm@7`). If none provide a version, the bare PM name is used with no version pin.