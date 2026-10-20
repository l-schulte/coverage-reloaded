---
name: commit-archiving
description: Archive logs and output artifacts for commits affected by a fixed pipeline or setup issue into a dedicated project archive subfolder (`projects/<p>/archive/<speaking_name>/`). Clears stale logs and outputs so `main.py` / `collect_coverage.py` can re-run affected commits cleanly, while preserving historical audit trails in `logs/`, `output/`, `moved.txt`, and `README.md`.
license: MIT
metadata:
  audience: developers
  workflow: failure-recovery
---

## What I do

When a bug or environment setup issue in `install-and-run.sh`, `Dockerfile`, timeout configuration, worker concurrency, or dependency management is fixed, all previous runs affected by that issue must be **archived**.

Because `src/collect_coverage.py` determines which commits to execute by checking whether `{timestamp}_{commit_hash}.log` or `.error` exists in `projects/<project>/logs/`, simply fixing the code will **not** trigger a re-run for commits that already attempted execution.

To allow the pipeline to re-run those commits under the fix without corrupting the historical record:
1. I identify all log and output artifacts belonging to the affected commits.
2. I move them out of `projects/<project>/logs/` and `projects/<project>/output/` into a dedicated archive subfolder: `projects/<project>/archive/<speaking_name>/`.
3. I generate manifest and audit documentation (`moved.txt` and `README.md`) recording the reason, fix, timestamp, and moved runs.
4. Once vacated, the affected commits immediately become eligible for re-run via `python3 main.py -p <project> --mode coverage-only`.

---

## Context & Prior Project Standards

Multiple mature projects in this repository (`uwazi`, `openneuro`, `spreed`, `opencrvs-core`, `material-ui`, `n8n`) have established this standard archiving structure:

### Archive Subfolder Layout
Every archive subfolder lives directly under `projects/<project>/archive/<speaking_name>/`:

```
projects/<project>/archive/<speaking_name>/
├── logs/
│   ├── {timestamp}_{commit_hash}.log
│   ├── {timestamp}_{commit_hash}.error
│   └── {timestamp}_{commit_hash}_*.log
├── output/
│   ├── {timestamp}_{commit_hash}/
│   ├── {timestamp}_{commit_hash}.error
│   └── {timestamp}_{commit_hash}.not_applicable
├── moved.txt
└── README.md
```

### Speaking Name Discipline
The subfolder name must be a concise, self-explanatory `snake_case` identifier describing the root issue or fix applied:
- **Good:** `dns_eai_again`, `fix_nyc_install`, `overwrite_model_error`, `rerun_syncworker_cleanup_collision`, `fix_jest_timeout`, `pretest_typecheck_gatekeeper`, `auxiliary_build_metrics_auth`
- **Bad:** `archive1`, `temp`, `fixed`, `errors`, `rerun`

### Golden Rules
1. **Never delete commit artifacts:** Never run `rm -rf` on live logs or outputs to force a re-run. Always move them to `archive/<speaking_name>/`.
2. **Never edit `commits.csv`:** Commits remain in `projects/<project>/commits.csv`. Vacating their logs from `projects/<project>/logs/` is the mechanism that signals they are pending execution.
3. **Move both logs and outputs:** Moving logs alone leaves stale output directories and markers (`.error` / `.not_applicable`). Moving outputs alone leaves logs that prevent `collect_coverage.py` from selecting the commit. Both must be moved together.
4. **Draft and confirm first:** Never move files without showing the user the blast radius (number of commits, file counts, and folder name) and obtaining approval.

---

## Tooling

Use the repository script `archive_fixed_commits.py`:

```bash
# 1. Preview changes (dry-run):
python3 archive_fixed_commits.py <project> <archive_name> \
    --reason "<what failed and why>" \
    --fix "<how install-and-run.sh or Dockerfile was modified>" \
    [--commits <hash1> <hash2> ... | --commits-file <file> | --grep-log "<pattern>"] \
    --dry-run

# 2. Execute archive move:
python3 archive_fixed_commits.py <project> <archive_name> \
    --reason "<what failed and why>" \
    --fix "<how install-and-run.sh or Dockerfile was modified>" \
    [--commits <hash1> <hash2> ... | --commits-file <file> | --grep-log "<pattern>"]
```

---

## Phased Protocol (Draft & Confirm)

### Phase 0 — Scope & Target Identification

1. **Identify the Project and Fixed Issue:**
   - Confirm project `<project>` under `projects/`.
   - Identify the exact bug or failure cause that was fixed (e.g. from `labeled-failure-analysis` or test triage).
   - Formulate a clear, speaking `snake_case` folder name (e.g. `fix_vitest_scope`).

2. **Determine Affected Commits / Runs:**
   Use one or more of the following identification strategies:
   - **By Error Pattern (`--grep-log`):** Grep `projects/<project>/logs/` for the specific failure string (e.g. `EAI_AGAIN`, `OverwriteModelError`, `Cannot find module`).
   - **By Failure Rule / Label File:** Extract run IDs from `projects/<project>/failure_labels_project.csv` or `failure_labels_collapsed_by_rule.csv` for the problematic rule ID.
   - **By Commit Hashes / Era List:** A list of commit hashes or `{timestamp}_{hash}` prefixes known to have suffered from the bug.

---

### Phase 1 — Blast Radius & Dry-Run Verification

1. Check if `projects/<project>/archive/<speaking_name>/` already exists. If it exists, choose a distinct name or confirm whether appending is intended (`--allow-existing`).
2. Run `archive_fixed_commits.py` with `--dry-run`:

```bash
python3 archive_fixed_commits.py <project> <speaking_name> \
    --reason "<reason>" \
    --fix "<fix>" \
    --dry-run \
    [target selection options]
```

3. Review the dry-run output:
   - Verify that all matched runs genuinely belong to the issue.
   - Verify no unrelated runs or unaffected commits are caught in the sweep.
   - Note the number of distinct runs, log files, and output items.

**Checkpoint 1 (Mandatory Stop Point):**
Present the proposed archiving plan to the user:
- Project: `<project>`
- Target archive path: `projects/<project>/archive/<speaking_name>/`
- Reason: `<description of fixed issue>`
- Fix applied: `<description of code/docker fix>`
- Number of affected runs / commits: `<n>`
- Number of log files to move: `<n>`
- Number of output items to move: `<n>`
- Sample of affected run IDs (`{ts}_{hash}`).

Ask: *"Proceed with archiving these <n> runs to `projects/<project>/archive/<speaking_name>/`?"*
**STOP and wait for the user's explicit approval before moving any files.**

---

### Phase 2 — Execute Archive Move

Once the user approves:

1. Run the archive command without `--dry-run`:

```bash
python3 archive_fixed_commits.py <project> <speaking_name> \
    --reason "<reason>" \
    --fix "<fix>" \
    [target selection options]
```

2. Confirm:
   - `projects/<project>/archive/<speaking_name>/logs/` contains the moved logs.
   - `projects/<project>/archive/<speaking_name>/output/` contains the moved outputs.
   - `projects/<project>/archive/<speaking_name>/moved.txt` lists the relocated artifacts.
   - `projects/<project>/archive/<speaking_name>/README.md` documents the audit summary.

---

### Phase 3 — Post-Archive Verification & Documentation

1. **Verify Live Directories:**
   - Confirm that the moved runs no longer appear in `projects/<project>/logs/` or `projects/<project>/output/`.
   - Confirm `projects/<project>/commits.csv` is intact.

2. **Update Project Overview (`projects/<project>/OVERVIEW.md`):**
   Under `## Environment / setup fixes`, record the fix and reference the new archive folder:
   ```markdown
   - **<Speaking Title>:** <Description of root cause and fix applied>. <N> affected runs archived to [`archive/<speaking_name>/`](archive/<speaking_name>/) for re-run.
   ```

3. **Provide Re-Run Command:**
   Inform the user that the commits are now pending re-run, and provide the command:
   ```bash
   python3 main.py -p <project> --mode coverage-only
   ```
   (or `python3 main.py -p <project>` if full processing is desired).
