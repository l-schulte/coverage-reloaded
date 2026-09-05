# AGENTS.md — Causal Coverage Collection

> Primary reference. Read fully before changing anything.
> Your main deliverable per project is **`install-and-run.sh`**.

---

## 1. Purpose & success criteria

Collects **longitudinal line-based coverage** across the full commit history of mature JS/TS projects. Coverage is the **exposure variable** in a causal study of coverage → bug introduction, so **measurement bias directly threatens validity.**

**Guiding principle:** at each commit, *follow the project's own coverage intent* (c8 → its `.c8rc.json`; nyc → its config). Where none exists, wrap the behavioral suite with c8/nyc.

**Inclusion criterion:** ≥ 90% of a project's last-5-years commits must produce valid coverage.

**Failure must be loud.** A silent/empty/partial file that passes validation corrupts the exposure variable with no signal. The worst failure mode is a **bailed run** (see §2).

**Never hide errors.** Forbidden in `install-and-run.sh` and all shared scripts:
- `|| { echo ...; exit 1; }` — replaces original error with generic message
- `command 2>&1 | tail -N` — discards early error output
- `command || true` — discards exit code and error context
- Any construct that suppresses stdout/stderr and substitutes a hand-written message

**Preferred:** let `set -e` abort on failure; log *before* the command, not *instead of* output.

---

## 2. ⚠️ THE BAIL RULE + exit-code handling

> **Tests must NEVER bail. No exceptions.**

A bailed run stops at first failure, exercises a fraction of the code, yet produces an `lcov.info` indistinguishable from a clean run. This is the most dangerous failure mode.

**Forbidden anywhere:** `--bail`, `--exit-first`, `--fail-fast`, `bail: true`, `bail: N` (N≥1), `stopOnFailure`.

| Runner | Forbidden | Use instead |
|---|---|---|
| mocha | `--bail`, `bail: true` | `--no-bail` (explicit) |
| jest | `--bail`, `bail: true` | omit |
| vitest | `bail: N` (N≥1) | `bail: 0` (default) |
| lerna | `--bail` | **`--no-bail`** (mandatory — lerna bails by default) |

**Exit-code handling — tight scope:**
```bash
set +e
npm run test:unit
UNIT_EXIT=$?
set -e
bash ../find-and-move-lcov.sh "unit" "false" "$UNIT_EXIT"
```

`set +e` wraps **only the test command**, not `find-and-move-lcov.sh`. Exit codes: 0/1 → coverage valid (WARNING on 1); >1 → runner crashed (ERROR, exit >1).

**Checklist:**
- [ ] No bail flags anywhere (CLI, config objects, npm scripts, config files)
- [ ] `--no-bail` present for mocha & lerna
- [ ] `set +e` wraps only test command, not `find-and-move-lcov.sh`
- [ ] `set -e` restored immediately after capture
- [ ] Exit code captured immediately after command
- [ ] 0/1 = warning; >1 = error + exit
- [ ] `set -e` at script top
- [ ] `find-and-move-lcov.sh` always called with exit code as 3rd arg

---

## 3. ⚠️ Coverage gates — confound alert

**Coverage thresholds** (nyc `--check-coverage`, jest `coverageThreshold`, custom wrappers) **confound the exposure variable**: a commit that passes all behavioral tests but falls below the threshold exits with code 1, indistinguishable from a real failure. Detect by inspecting:

- [ ] Does the coverage script pass `--check-coverage`, `--lines`, `--branches` etc.?
- [ ] Does `jest.config` or `package.json` contain `coverageThreshold`?
- [ ] Does a custom `bin/test.js` wrapper enforce a coverage floor?
- [ ] Does `.c8rc.json` or `.nycrc` set `check-coverage` or threshold values?

**If found: do NOT create `install-and-run.sh` or Dockerfile.** Report the finding and move on.

---

## 4. Pipeline overview

See `@ref/agents-pipeline-detail.md` for full pipeline diagram, container layers, WayPack details, LCOV validation, env vars, and per-project files.

```
HOST main.py → docker-run.sh → CONTAINER execute.sh → install-and-run.sh
```

**Your file:** `install-and-run.sh` is the only project-specific script. Shared scripts (`execute.sh`, `find-and-move-lcov.sh`, etc.) must not be edited per-project.

---

## 5. Host vs. container — critical distinction

See `@ref/agents-ops-reference.md` for host/container comparison, git inspection commands, onboarding, debugging table, and version determination.

> **Core rule:** inspect commit files on host with `git -C projects/<p>/repo show <hash>:package.json` — never assume the host working tree is at the target commit.

---

## 6. Writing `install-and-run.sh`

See `@ref/agents-design-guide.md` for full contract, suite markers, era detection, parallelism, and suite exclusions.

**Key constraints:**
- Branch on `$IS_NPM_MAIN_PM` / `$IS_YARN_MAIN_PM` / `$IS_PNPM_MAIN_PM`
- Detect what to run by inspecting the **checked-out commit** — not dates
- Wrap every suite with `suite_start` / `suite_end`
- Pin registries: project deps → `$WAYPACK_NPM_REGISTRY`, our tooling → `$VERDACCIO_REGISTRY`
- `--maxWorkers=1` / `--runInBand` preferred; `--maxWorkers=2` acceptable to prevent timeout errors in slow suites
- Use `command_changes.csv` during design, not at runtime

---

## 7. Debugging methodology

When asked to investigate a failing test or error:

1. **Read the error log first** — extract the exact test name, error type, and line numbers.
2. **Trace the config chain** — follow imports/configs to identify the root subsystem (DB, network, build tool).
3. **Report findings with ONE actionable next step** — a single command the user can run to confirm or eliminate the primary hypothesis.

**Do not** produce long hypothetical reasoning trees. Lead with a 3-sentence summary of what you found and what to run next. Hypotheses are useful only when paired with a concrete verification step.
