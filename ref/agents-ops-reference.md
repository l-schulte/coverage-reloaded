# Operations Reference — Host, Container, Debugging, Versions

> Referenced from `AGENTS.md §3`. Read when debugging runs or onboarding a new project.

## Host vs. container

The host and container operate on **different copies of the repo at different commits.** This is the #1 source of debugging confusion.

| | Host (`main.py`) | Container (`execute.sh`) |
|---|---|---|
| Repo | `projects/<name>/repo/`, cloned once, left at clone-time `HEAD` | repo **copied into image at build time**, then `git checkout $revision` |
| Checks out target commit? | **No** | **Yes** |
| Workdir | `coverage_reloaded/` root | `/coverage_reloaded` |
| WayPack | n/a | yes, `http://waypack:3000` on `mining-net` |

**Implications:**
- To inspect a commit's files on the host, use `git show`/`git ls-tree` — **do not** assume the host working tree is at that commit.
- The project image snapshots the host repo at `docker build` time. `docker-run.sh` rebuilds on every invocation; the container then runs `git checkout $revision`.
- `collect_commits.py` (whole-history) and `collect_coverage.py` (per-commit) run on independent timelines.

**Path map:** `projects/<p>/repo/` ↔ `/coverage_reloaded/repo/`; `projects/<p>/install-and-run.sh` ↔ `/coverage_reloaded/install-and-run.sh`; `projects/<p>/output/` ↔ `/coverage_reloaded/coverage/` (volume).

### What you can run, and where

**On the host — DO:**
- Run **git** against `projects/<name>/repo/` to read history and any file at any commit.
- Read/edit authored files: `install-and-run.sh`, `projects/<p>/Dockerfile`, `config.json`, `commits_postprocess.py`.
- Read generated data: `commits.csv`, `command_changes.csv`, `additional_information.csv`, `logs/`, `output/`.
- Trigger runs: `main.py --mode single-commit --commit-hash <h>` / `--mode coverage-only`.
- Drop into a container: `bash docker-run.sh <p> shell|debug <hash> <ts> <pm> <node>`.

**On the host — DO NOT:**
- ❌ `npm/yarn/pnpm install`, `npm test`, `nyc`, `c8` — no WayPack, no faketime, wrong toolchain.
- ❌ Read host working-tree files expecting them to reflect the target commit.

**Inside the container (via `docker-run.sh shell|debug`) — DO:**
- Install deps via WayPack, run behavioral suite with coverage, step through `install-and-run.sh`.
- Inspect the checked-out commit at `/coverage_reloaded/repo`.

### Inspecting files at a commit with git (host)

```bash
REPO=projects/<name>/repo
git -C $REPO show <hash>:package.json
git -C $REPO show <hash>:package.json | jq '.scripts'
git -C $REPO show <hash>:packages/foo/.c8rc.json
git -C $REPO cat-file -e <hash>:karma.conf.js && echo present
git -C $REPO ls-tree -r --name-only <hash>
git -C $REPO show --stat <hash>
```

## Onboarding a new project

1. Add to `config.json` (`url`, `projectID`, `package_manager_priority`, `min_node_version`, `node_version_delay_months`, `workspaces`).
2. `main.py --mode commits-only`
3. Write `projects/<p>/Dockerfile`
4. Write `install-and-run.sh`
5. Optional: `commits_postprocess.py`
6. Test one commit: `--mode single-commit --commit-hash <h>`
7. Full run: `--mode coverage-only --max-workers N`
8. Verify success rate (count `.lcov` vs `.error`)

## Debugging a commit

Check `output/<hash>.{lcov,error}`; read `logs/node*_<hash>.*` (first line = reproduce command); or `bash docker-run.sh <p> shell <hash> <ts> <pm> <node>` and step through manually.

| Symptom | Cause | Fix |
|---|---|---|
| `Cannot find module` | WayPack miss for this timestamp | add local override |
| `Z_DATA_ERROR` | lockfile/npm-ver mismatch | bump npm via `commits_postprocess.py` |
| `gyp ERR!` | missing build/system deps | add apt pkgs to project Dockerfile |
| `No lcov.info files found` | no coverage produced | add `--coverage` or wrap nyc/c8 |
| 90-min timeout | install/tests hang | check interactive prompts / env |
| peer-dep conflict | bad dep tree | `--legacy-peer-deps` / `--force` |
| `Killed` (OOM) | container memory | fewer workers / add swap |

**Silent failure** = exit 0 + lcov produced but no tests ran (empty match or bail). Cross-check for low line counts and bail patterns in logs.

## Version determination

**Node** (priority): `.nvmrc` → `engines.node` → lockfile hints → `.tool-version` → repo Dockerfiles → `build/npm/preinstall.js` → Angular matrix → fallback `node_releases.json` (latest LTS at commit_date − offset).

**Package manager** (priority from `config.json`, default `["pnpm","yarn","npm"]`): lockfile presence picks candidate, then scan for version hints.

**PM version** (`from_package_json.py`, first match wins): `packageManager` field → `volta` → `engines` (semver range → highest numeric). If none, bare PM name with no version pin.
