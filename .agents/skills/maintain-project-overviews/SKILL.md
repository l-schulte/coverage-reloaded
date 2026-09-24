---
name: maintain-project-overviews
description: Create and update the two-level coverage-collection documentation (root OVERVIEW.md index with a checklist-only status table + projects/<p>/OVERVIEW.md per active project). Enforces a fixed template and technical-English style, sources results from stats_output/report.txt (regenerated fresh via `stats.py --report-only` on every invocation), condenses known failures with classification and links. Active projects only. Draft-and-confirm only.
license: MIT
metadata:
  audience: developers
  workflow: documentation
---

## What I do

I maintain the coverage-collection documentation in two levels:

- **Root `OVERVIEW.md`** — a global index: purpose, legend, a checklist-only
  status-at-a-glance table of every active project, cross-cutting infrastructure
  notes, and a maintenance section.
- **`projects/<p>/OVERVIEW.md`** — one file per **active** project, built from the
  canonical template below.

I create missing files and refresh existing ones after a collection run or a
re-labeling pass. I cover **active projects only**; excluded and archived projects
remain under `archive/` and are out of scope.

I am a **draft-and-confirm** skill: I present every generated or updated file and
wait for explicit approval before writing anything to disk.

## Document model

- Active projects are exactly the projects listed in the root `OVERVIEW.md`
  status table and present in `config.json`. `sentry-javascript` is in
  `config.json` but is documented as excluded — do **not** treat it as active.
- The legacy single-file overview is preserved at `projects/OVERVIEW.md.bak` (and
  in git history); `projects/OVERVIEW.md` is now only a pointer stub.
- The per-project file is the single source of detail. The root file never
  duplicates project detail; it links to it.
- The canonical per-project template lives **only in this skill**. The root
  `OVERVIEW.md` maintenance section points readers here.

## Read-only sources

Never invent values. Every number must be traceable to one of these files:

- `config.json` — project URL, package-manager and Node strategy. **Link to it,
  never copy the JSON block.**
- `projects/<p>/stats_output/report.txt` — the canonical Results numbers
  (commits processed, without/with test failures, not applicable, hard errors,
  coverage %). Use the generated date from this file. **Regenerate it fresh on
  every invocation** by running `python stats.py <p> --report-only` before
  reading it; this rewrites `report.txt` from the current `output/` state and
  deletes any stale plots.
- `projects/<p>/stats_output/` — CSVs and plots; link to the directory.
- `projects/<p>/failure_labels_project.csv` and
  `projects/<p>/failure_labels_collapsed_problematic_unclear.csv` — failure
  families and their labels.
- `projects/<p>/install-and-run.sh` and `projects/<p>/command_changes.csv` —
  suite names, runners, and era transitions.
- `projects/OVERVIEW.md.bak` — legacy content to migrate when present (see
  Protocol); otherwise use git history.
- `AGENTS.md` — checklist semantics, the bail rule, and coverage-gate policy.

## Canonical per-project template

```markdown
# <project-id>

**Repository:** <url>
**Status:** active

## Test infrastructure

- **Package manager:** <pm(s)> (see [`config.json`](../../config.json) → `<id>`)
- **Node strategy:** <strategy / overrides, or "default">
- **Runners:** <runner list>
- **Eras:** <chronological runner/config transitions>

## Coverage collection

- **Suites collected:** <suite → runner>
- **Suites excluded:** <suite → reason>
- **Coverage tool / config:** <c8 | nyc | jest | vitest | project config>
- **LCOV production:** <how the lcov file(s) are emitted>

## Checklist

- [ ] 100 done (<n>/100)
- [ ] failed tests doublechecked (<note>)
- [ ] complete run (<note>)
- [ ] complete test failure check (<note>)

## Results

Source: `stats_output/report.txt` (generated <date>).

| Metric | Value |
|---|---|
| Commits processed | <n> |
| Without test failures | <n> |
| With test failures | <n> |
| Not applicable | <n> |
| Hard errors | <n> |
| Coverage produced | <pct>% |

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

<One table per classification group, or a single table with a Classification
column. Keep each row to signature → classification → coverage impact → action.
Link to `logs/`, `failure_labels_project.csv`, or the collapsed CSV for depth.>

## Environment / setup fixes

<Conditional fixes applied in install-and-run.sh / Dockerfile, or "None.">

## Known gaps

<Uncollected suites, timeouts, or unfixable failures, or "None.">
```

## Style guide (technical English)

- Present tense, third person, impersonal. Avoid "we"/"I" except when recording a
  documented decision.
- No colloquialisms, filler, or marketing adjectives ("awesome", "great",
  "seamless").
- Define acronyms on first use (CI, PM, LCOV, DB, DI, OOM).
- One idea per sentence; prefer short sentences.
- Use tables for enumerable facts; use prose only for rationale.
- Use consistent terms: **commit**, **suite**, **run**, **exit code (failing-test count)**,
  **hard error**, **coverage gate**, **not applicable**.
- Attribute every number to its source file.
- Do not use emojis.

## Checklist and label semantics

Checklist items (see `AGENTS.md`):

- **100 done** — a sample of 100 commits was reviewed.
- **failed tests doublechecked** — non-zero-exit runs were inspected and classified.
- **complete run** — the full commit history has been processed.
- **complete test failure check** — every failing run has been labeled and assessed.

Status symbols (used in the root status table and the per-project checklist):

- `✅` / `- [x]` — done.
- `🟡` / `- [wip]` — work in progress; a run is actively being processed.
- `🚧` / `- [paused]` — paused; a run was partially processed and then stopped
  (for example, awaiting a date-basis switch or a re-run). The Results section
  shows pending commits.
- `❌` / `- [ ]` — not done; no work started.

Failure labels (`failure_labels_project.csv`):

- `acceptable` — a genuine developer-facing test failure at that commit.
- `problematic` — an environment/setup artifact of this pipeline.
- `unclear` — ambiguous after analysis.
- `false_positive` — not a real failure (for example, captured console output).
- `reevaluated_acceptable` — documented reclassification for failures initially
  labeled `unclear`/`problematic` that static analysis confirms are genuine
  developer-facing failures (see the `labeled-failure-analysis` skill). Excluded
  from `collapse_labels.py` (only `problematic`/`unclear` collapse) and assignable
  interactively with the `e` key. Environment/setup artifacts remain labeled
  `problematic` even after fixes are applied so regressions continue to surface.

## Protocol

### Phase 0 — Inventory

1. Read `config.json` and the active-project list from the root `OVERVIEW.md`.
2. Build the active set (exclude `sentry-javascript`). For each project, record
   whether `stats_output/report.txt`, `failure_labels_project.csv`, and
   `failure_labels_collapsed_problematic_unclear.csv` exist.
3. Checkpoint: present the active set and the per-project source availability.

### Phase 1 — Per-project drafts

For each active project, build the file from the template:

1. Migrate the legacy section from `projects/OVERVIEW.md.bak` when it is present.
2. Condense Known Test Failures into signature → classification → coverage impact
   → action rows; link to logs/CSV instead of embedding long narratives.
3. Checkpoint: ask whether to trace back each documented known failure against the
   most recent logs to confirm it still exists. If the user opts in, inspect
   `projects/<p>/logs/` for each signature and keep, update, or drop rows based on
   the latest evidence.
4. Regenerate `stats_output/report.txt` by running `python stats.py <p> --report-only`
   (fresh numbers from the current `output/` state; stale plots are deleted).
   Then pull Results from it. If the command fails, write
   `Results: pending (no stats_output)`.
5. Link to `config.json` for configuration; do not copy JSON.

### Phase 2 — Root index

Assemble `OVERVIEW.md`: purpose/pointers, legend, the checklist-status table
(one row per active project, linking to its file; columns `100 done`, `failed
tests doublechecked`, `complete run`, `complete test failure check`, symbols
`✅`/`🟡`/`🚧`/`❌`; no numeric results), cross-cutting infrastructure notes, and the
maintenance section pointing at this skill.

### Phase 3 — Consistency check

- Every per-project file exists for every active project.
- Root table row count equals the active-project count.
- Root table carries no numeric results (commits, coverage %, hard errors, dates).
- Every checklist cell is `✅`, `🟡`, `🚧`, or `❌`, taken from the per-project file.
- All relative links resolve on disk.
- No `config.json` JSON block is duplicated.
- Style guide is respected.

### Phase 4 — Draft and confirm

Present the full set of drafts and a summary of changes. **Do not write until the
user explicitly approves.** On approval:

- Back up `projects/OVERVIEW.md` to `projects/OVERVIEW.md.bak` before replacing it
  with the pointer stub.
- Write the per-project files and the root `OVERVIEW.md`.

## Guardrails (strictly enforced)

- **Draft-and-confirm only.** Never write without explicit approval.
- **Active projects only.** Do not document, edit, or move projects under
  `archive/`.
- **Never fabricate numbers.** Every value cites `stats_output/report.txt` or the
  source CSV.
- **Root status table is checklist-only.** It never carries numeric results
  (commits, coverage %, hard errors, dates); those live in the per-project
  Results sections.
- **Do not duplicate `config.json`** — link to it.
- **Do not modify** `config.json`, shared pipeline scripts, or any
  `install-and-run.sh`.
- The canonical template lives **only** in this skill.
