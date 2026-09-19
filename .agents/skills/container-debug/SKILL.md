---
name: container-debug
description: Debug test execution environment for a specific commit by starting a podman container in detached mode, then executing commands via podman exec. The container runs in the background throughout the debugging session, preserving state between commands. Use when a commit fails due to environment/setup problems (not test logic). Container has a 90-minute auto-stop timer to prevent stale containers, and is explicitly stopped and removed at session end.
metadata:
  audience: developers
  workflow: environment-debugging
---

## What I do

Debug environment setup issues by starting a detached podman container for a specific commit, then investigating interactively by executing commands via `podman exec`. The container runs in the background throughout the session, preserving state (installed packages, modified files) between commands. The goal is to identify and fix environment problems, not test logic issues. All changes happen inside the container — no host-side modifications. The container has a **90-minute auto-stop timer** to prevent stale containers if cleanup fails, and is explicitly stopped and removed when debugging completes.

## Context

- **`execute.sh`**: Entrypoint that sets up tmpfs mount, git checkout, package manager, registries, and lockfile patching. Calls `install-and-run.sh` at the end.
- **`install-and-run.sh`**: Project-specific script that installs dependencies and runs tests with coverage. This is the file we may modify inside the container.
- **`docker-run.sh`**: Container startup script. For optimized debugging, we bypass this and use direct `podman` commands.
- **`commits.csv`**: Contains commit metadata (timestamp, package_manager, node version) needed to start the container.
- **`helper/find-and-move-lcov.sh`**: Coverage collection script called by `install-and-run.sh`.
- **`helper/logging.sh`**: Logging functions (`print_header`, `suite_start`, `suite_end`).
- **Registry separation**: Project deps go through WayPack (temporal), our tooling (c8, nyc) goes through Verdaccio.
- **No bail rule**: Never use `--bail`, `--exit-first`, `--fail-fast`. Tests must run to completion.

## Prerequisites

Required inputs to start debugging:
- Project name (e.g., `material-ui`)
- Commit hash to debug

Optional (can be read from `commits.csv`):
- Timestamp (epoch seconds)
- Package manager (e.g., `npm@8`, `yarn@1.22`)
- Node version (e.g., `20`)

## Protocol

### Phase 0 — Gather Prerequisites

1. Read `projects/<name>/commits.csv` to find the target commit row.
2. Extract: `timestamp`, `package_manager`, `node_version` (column names may vary — check header).
3. If commit not in `commits.csv`, ask user for timestamp, package manager, and node version.

**Checkpoint 0:** Confirm with user: *"Ready to debug project X at commit Y (ts=..., pm=..., node=...). Proceed?"*

### Phase 1 — Start Detached Container

Start a container in **detached mode** with a descriptive name:

```bash
CONTAINER_NAME="debug-<project>-<hash:8>"
EXECUTOR="podman"
IMAGE="core_node<node>_<project>"

$EXECUTOR run -d \
  --name "$CONTAINER_NAME" \
  --network mining-net \
  --cap-add=NET_ADMIN \
  --env-file .env \
  --env revision=<hash> \
  --env timestamp=<timestamp> \
  --env package_manager=<pm> \
  --env project_id=<project> \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  --cpus=${CONTAINER_CPUS:-20} \
  --pids-limit 10000 \
  -v "$(pwd)/projects/<project>/output:/coverage_reloaded/coverage" \
  $IMAGE \
  tail -f /dev/null
```

**Start the auto-stop timer** (90 minutes / 5400 seconds):
```bash
# Launch a background process that kills the container after timeout
$EXECUTOR exec -d $CONTAINER_NAME bash -c '
  sleep 5400 && kill 1 2>/dev/null || true
'
```

**Key points:**
- Container name: `debug-<project>-<hash:8>` (first 8 chars of hash for brevity)
- `tail -f /dev/null` keeps the container running without executing anything
- Container runs in background, preserving state between commands
- All environment variables and mounts are configured at startup
- **Auto-stop timer** kills container after 90 minutes if not cleaned up manually

After starting, verify the container is running:
```bash
$EXECUTOR ps | grep $CONTAINER_NAME
```

### Phase 2 — Set Up Environment via execute.sh

**Before running execute.sh**, read it and decide where to interrupt `install-and-run.sh`. Place an `exit` command at that point inside the container.

**Strategy**: Modify `/coverage_reloaded/install-and-run.sh` inside the container to add `exit 0` at the point where you want to stop. This is deterministic (unlike Ctrl+C).

Common interruption points:
- **After dependency install but before tests**: Add `exit 0` after `npm install` / `yarn install` / `pnpm install` completes.
- **After build but before tests**: Add `exit 0` after any build step (e.g., `lerna run prepare`, `tsc`).
- **Before a specific test suite**: Add `exit 0` before the `suite_start` for the problematic suite.

**Example** — interrupt after install, before tests:
```bash
# View install-and-run.sh
podman exec $CONTAINER_NAME cat /coverage_reloaded/install-and-run.sh

# Edit the file inside the container (add exit 0 after install)
podman exec $CONTAINER_NAME bash -c 'sed -i "/npm install/a\\exit 0" /coverage_reloaded/install-and-run.sh'

# Run execute.sh
podman exec $CONTAINER_NAME bash execute.sh
```

**If execute.sh itself has issues** (tmpfs mount, git checkout, package manager setup), you can run those steps manually:
```bash
# Manual step-through (only if execute.sh fails early)
podman exec $CONTAINER_NAME bash -c '
  mount -t tmpfs -o size=20G tmpfs /coverage_reloaded/repo &&
  cp -a /coverage_reloaded/repo_disk/. /coverage_reloaded/repo/ &&
  cd /coverage_reloaded/repo &&
  git checkout <hash>
  # ... then set up package manager manually
'
```

**Checkpoint 1:** Report what happened: *"Environment setup complete. Dependencies installed successfully / failed at step X with error Y."* Then propose next debugging step.

### Phase 3 — Debug Environment Issues

Now that the environment is partially set up, investigate issues:

```bash
# Check package manager versions
podman exec $CONTAINER_NAME bash -c 'npm --version'
podman exec $CONTAINER_NAME bash -c 'yarn --version'
podman exec $CONTAINER_NAME bash -c 'pnpm --version'

# Check registry connectivity
podman exec $CONTAINER_NAME bash -c 'curl -s $WAYPACK_NPM_REGISTRY | head -20'

# Check dependency resolution (re-run install to see errors)
podman exec $CONTAINER_NAME bash -c 'cd /coverage_reloaded/repo && npm install'

# Check Node.js version
podman exec $CONTAINER_NAME bash -c 'node --version'

# Check for missing system deps (look for gyp ERR!, command not found)
podman exec $CONTAINER_NAME bash -c 'cd /coverage_reloaded/repo && npm install 2>&1 | grep -i "error\|ERR\|not found"'

# Check lockfile issues
podman exec $CONTAINER_NAME bash -c 'ls -la /coverage_reloaded/repo/*.lock /coverage_reloaded/repo/package-lock.json'
```

**Common issues to look for**:
- `Cannot find module` — WayPack miss, need local override
- `Z_DATA_ERROR` — lockfile/PM version mismatch
- `gyp ERR!` — missing system deps (may need apt packages in Dockerfile)
- `peer dep conflict` — use `--legacy-peer-deps` or `--force`
- `EADDRINUSE` — port conflicts from parallel execution
- `Killed` (OOM) — too many workers

**For interactive debugging sessions**, use `podman exec -it`:
```bash
# Start an interactive bash session when needed
podman exec -it $CONTAINER_NAME bash
# (This drops you into a shell inside the running container)
```

**Checkpoint 2:** Report findings: *"Found issue X. Root cause is Y. Proposed fix: Z."*

### Phase 4 — Test Execution (Optional)

If environment issues are resolved, optionally test execution:

```bash
# Remove the exit 0 you added in Phase 2
podman exec $CONTAINER_NAME bash -c 'sed -i "/^exit 0$/d" /coverage_reloaded/install-and-run.sh'

# Run execute.sh again
podman exec $CONTAINER_NAME bash execute.sh

# Or run specific test commands manually
podman exec $CONTAINER_NAME bash -c '
  cd /coverage_reloaded/repo &&
  npx --registry=$WAYPACK_NPM_REGISTRY jest path/to/test.js --coverage
'
```

**Checkpoint 3:** Report test results: *"Tests passed/failed. Coverage produced/not produced."*

### Phase 5 — Report

Output a structured report to chat:

```
# Environment Debug Report

## Commit: <hash> (<timestamp>)
## Project: <name>

### Issues Found
1. [Issue description]
   - **Root cause**: [cause]
   - **Proposed fix**: [fix in install-and-run.sh]

### Proposed Changes to install-and-run.sh
```diff
- [current code]
+ [proposed code]
```

### Next Steps
- [ ] Apply changes to install-and-run.sh on the host
- [ ] Test with: `python main.py --project <name> —-mode single-commit --commit-hash <hash>`
```

### Phase 6 — Cleanup

Explicitly stop and remove the container (this also kills the auto-stop timer):

```bash
# Stop the container (kills PID 1 and all child processes including the timer)
podman stop $CONTAINER_NAME

# Remove the container
podman rm $CONTAINER_NAME
```

Verify cleanup:
```bash
podman ps -a | grep $CONTAINER_NAME
# Should return empty
```

No auto-removal — explicit cleanup ensures the container is properly removed. The auto-stop timer is automatically killed when the container stops.

## Container Lifecycle Management

### Naming Convention
- Container name: `debug-<project>-<hash:8>`
- Example: `debug-material-ui-a1b2c3d4`

### State Preservation
The detached container preserves state between commands:
- Installed packages in `node_modules/`
- Modified files (e.g., `install-and-run.sh` with `exit 0`)
- Environment variables
- Working directory

### Auto-Stop Timeout

The container has a **90-minute auto-stop timer** to prevent stale containers:

- **Mechanism**: Background process runs `sleep 5400 && kill 1` inside the container
- **Effect**: Kills PID 1 (`tail -f /dev/null`), causing the container to exit
- **Purpose**: Prevents resource leaks if agent fails to clean up

To check if the timer is still running:
```bash
# List background processes inside container
podman exec $CONTAINER_NAME ps aux | grep sleep
```

To reset the timer (extend timeout by another 90 minutes):
```bash
# Kill existing timer and start new one
podman exec $CONTAINER_NAME pkill -f "sleep 5400"
podman exec -d $CONTAINER_NAME bash -c 'sleep 5400 && kill 1 2>/dev/null || true'
```

To disable the timer (not recommended):
```bash
podman exec $CONTAINER_NAME pkill -f "sleep 5400"
```

### Container Crash Recovery
If the container crashes unexpectedly:
```bash
# Check container status
podman ps -a | grep debug-<project>

# If exited, remove and restart
podman rm debug-<project>-<hash:8>

# Restart Phase 1 with same parameters
```

### Interactive Sessions
When interactive input is needed (e.g., answering prompts):
```bash
podman exec -it $CONTAINER_NAME bash
# Work inside the container
# Type 'exit' to return to host (container keeps running)
```

## Off-Limits — Strictly Enforced

The following actions require explicit user permission:

### No modifications to shared scripts

- Do **not** modify `execute.sh`, `find-and-move-lcov.sh`, `logging.sh`, `fake-time.sh`, `has-option.sh`, `cypress-patcher.sh` unless clearly beneficial to all projects.

### No test logic changes

- Do **not** change test assertions, test files, or test configuration. Focus only on environment/setup fixes in `install-and-run.sh`.

### No host-side changes

- Do **not** create files outside the container. All changes happen inside the container.
- Do **not** modify `projects/<name>/install-and-run.sh` on the host — only propose changes in the report.

### No permanent container changes

- Do **not** commit to git inside the container. The container is temporary.
- Do **not** push changes to registries or external services.

### Reasoning boundaries

- After 2 attempts at resolving a single issue, stop and escalate to the user rather than continuing to speculatively search.
- Hypotheses must be paired with a concrete verification step (a command to run, a file to check).
