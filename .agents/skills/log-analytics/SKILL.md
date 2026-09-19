---
name: log-analytics
description: Triaging test failures and hard errors in coverage_reloaded pipeline logs using a phased iterative protocol with explicit user check-ins between each phase. Follow the structured approach — never launch long debugging runs without presenting options first. Podman/container launches are off-limits unless explicitly authorized by the user.
license: MIT
metadata:
  audience: developers
  workflow: failure-analysis
---

## What I do

Systematically triage test failures and hard errors in logs produced by the `coverage_reloaded` pipeline (see `projects/<name>/logs/`). I break analysis into short, bounded phases with explicit stop points where I present findings and ask the user for feedback before proceeding. This prevents long, rough debugging runs that could have been avoided by showing options mid-investigation.

## Context

- Per commit, a container runs `projects/<name>/install-and-run.sh`, which runs the project's behavioral test suite with coverage and emits `lcov.info`.
- Logs live at `projects/<name>/logs/` — `<ts>_<hash>.log` (run produced coverage) or `<ts>_<hash>.error` (run failed entirely). Every log's first line is the exact `docker-run.sh` reproduce command.
- Output sidecars at `projects/<name>/output/*/unit.exit_code` indicate exit codes: 0 = clean, 1 = tests failed but coverage valid, >1 = runner crashed.
- Ignore `logs_1/` and `output_1/` (outdated snapshots). See `AGENTS.md §7` for coverage-validity rules.
- `AGENTS.md §4`: Coverage-threshold gates (§3 `--check-coverage`) are not bugs — they are confounds of the exposure variable. Do not attempt to "fix" them.

## Iterative Protocol

Run phases sequentially. Stop after each phase. Present your summary table or grouping **in full** before moving on. Wait for the user's input explicitly listed as a checkpoint question.

### Phase 0 — Inventory & Triage

Bounded scope: only gather high-level numbers, no deep tracing yet.

1. Count `.log` vs `.error` runs in `projects/<name>/logs/`.
2. For every `output/*/unit.exit_code`, tally 0 / 1 / >1.
3. Read each error log once. Extract the top 3–5 most common failure signatures from Docker build output (truncated steps like `STEP N/26`, empty/header-only logs, package-manager version mismatches like yarn Berry rejecting classic flags such as `--ignore-scripts`).
4. Report the success rate relative to the ≥90%-of-last-5-years inclusion criterion.

**Checkpoint 0:** Present a summary table (`total_runs | .log | .error | 0 | 1 | >1 | success_rate`) plus the most common `.error` patterns. Ask: *"Inventory complete — does this match what you expect? Proceed to classification?"*

### Phase 1 — Group & Classify

Bounded scope: cluster failures by root cause, assign tentative types. Do NOT trace imports/configs more than one level deep at this stage.

1. Grep `.log` files for failure signatures: `Tests: N failed`, `✕`, `●`, `FAIL <path>`, `Expected/Received`, `Unknown type`, `Cannot query field`, `ENOTFOUND`, `ECONNREFUSED`, timeouts, schema merge errors (`Error merging schemas`, GraphQL federation issues).
2. Cluster matching errors into groups by signature. Each group represents a distinct root-cause pattern observed across commits.
3. Tentatively classify each group:
   - **Developer-facing** — a genuine assertion/logic failure a developer would also hit at that commit (real bug or known-flaky test). These legitimately reduce coverage.
   - **Environment/setup** — sandbox artifact: network isolation (remote/stitched service schemas, external endpoints), temporal drift (time-relative/"self-expiring" tests running at wall-clock instead of commit time), package-manager/version mismatch, missing system deps, Docker build infra.

   If time-related and fixable, verify candidate with `helper/fake-time-node.js` (set `NODE_OPTIONS="-r /coverage_reloaded/fake-time-node.js"` + `TIMESTAMP_EPOCH="$timestamp"`). Check it doesn't introduce new failures.

4. Determine whether each failure corrupts the exposure variable (silent under-measurement via bail) or is an acceptable visible partial result.

**Checkpoint 1:** Present the groups table (`Group → Signature → Example log(s) → Classification → # commits affected → exposure impact`). Then ask: *"These are the failure groups I've found. Which should we dive deeper on, and in what priority?"* The user may select none, some, or all groups. You must wait for their selection before proceeding to Phase 2.

### Phase 2 — Deep Dive (per selected group)

Bounded scope: focus **only** on what the user selected. Max 2 passes per group — then escalate to the user.

1. Trace the specific error chain to its origin point (which layer causes it):
   - Is it in `install-and-run.sh`?
   - In the container base layer or project `Dockerfile`?
   - Attributable to the behavioral suite itself (a real test flakiness)?
2. Suggest the minimal proposed fix (line-level patch if applicable). Note: any fix must not modify `execute.sh`, `find-and-move-lcov.sh`, or `logging.sh` unless clearly beneficial to all projects.
3. Flag any coverage thresholds found in this group as confounds (not bugs).

**Checkpoint 2:** Present finding(s). Ask: *"Accept, modify, or skip this group? Or move to another group?"* Always offer these three concrete options.

### Phase 3 — Final Report & Decide

1. Compile all resolved and skipped groups into a concise report mirroring `LOG_FAILURE_ANALYSIS_PROMPT.md § Deliverable`:
   - Success rate and coverage-producing runs total
   - Table: `signature → example log → developer-facing vs setup → coverage impact`
   - Recommended next steps categorized as: (a) fixes in `install-and-run.sh`, (b) required changes in `Dockerfile` or shared scripts, (c) document-as-known-in-failure in `projects/<name>/OVERVIEW.md` under "Known Test Failures"
   - Note any deviation from the ≥90% inclusion criterion
2. If there are remaining unexplored groups, include them separately so the user can choose to continue.

**Checkpoint 3:** Show the completed report. Ask: *"Done — or want to continue with another group?"*

## Off-Limits — Strictly Enforced

The following actions require explicit, separate user permission before executing. State what you intend to do, why, what you expect to learn, and expected duration — **do not execute without confirmation**.

### Starting podman containers is off-limits unless explicitly authorized

- Do **not** manually start containers via `podman run`, `podman exec`, `podman attach`, or equivalent commands unless the user has given direct permission in the chat.
- Do **not** use `bash docker-run.sh <project> shell|debug <hash> <ts> <pm> <node>` to spin up interactive debug sessions unless explicitly permitted.
- When requesting permission, include:
  1. The exact podman/docker command (or describe the intended `docker-run.sh` invocation with all parameters).
  2. What diagnostic information you expect to extract and why it answers the current question.
  3. Why the same information cannot be obtained from static log/file inspection alone (grep, git show, config reading).
  4. Expected investigation duration inside the container (should typically be well under 5 minutes).
  5. Whether you will attempt to install dependencies, run tests, or just inspect state.

### Verification runs are always handled by the user unless specified otherwise

- Do **not** launch pods/containers to get updated or proving logs. This includes:
  - Rerunning a specific commit to confirm a hypothesis
  - Spinning up an interactive shell session to install dependencies manually
  - Executing commands inside a running container for verification purposes
  - Re-running `docker-run.sh` or `bash execute.sh` to get fresh output
- All static analysis is on-limits without permission: reading logs, grepping content, inspecting files via `git show`, reviewing `command_changes.csv`, tracing import chains within the repo.
- Dynamic execution (any command that touches runtime, installs packages, or starts subprocesses inside a container) requires explicit user authorization regardless of how minor it seems.

### Reasoning boundaries

- Never produce a long speculative reasoning tree. Lead with a 3-sentence summary and a single concrete next step, not multiple hypotheses.
- Hypotheses must be paired with a concrete verification step (a grep pattern, a `git show` target, a file path) — not a promise to keep digging.
- After 2 attempts at resolving a single issue, stop and escalate to the user rather than continuing to speculatively search.
