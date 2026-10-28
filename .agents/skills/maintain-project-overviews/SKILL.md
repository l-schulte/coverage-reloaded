---
name: maintain-project-overviews
description: Create and update the two-level coverage-collection documentation (root OVERVIEW.md index with a checklist-only status table + projects/<p>/OVERVIEW.md per active project). Enforces a fixed template and technical-English style. Sources results from stats_output/report.txt (regenerated fresh via `stats.py --report-only` on every invocation) and failure-triage numbers from the v2 label CSVs (regenerated fresh via `check_failures_v2.py --stats`). Never duplicates per-family failure labels. Active projects only. Draft-and-confirm only.
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
- Failure labels live only in `projects/<p>/label_analysis/failure_labels_project_min.csv`
  and `..._max.csv`. The per-project `## Failure triage` section reports aggregate
  numbers and, only when non-zero, the `problematic`/`unclear` families. It never
  restates `acceptable`/`reevaluated_acceptable` labels.
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
- `projects/<p>/label_analysis/failure_labels_project_min.csv` — **the single
  source of truth for failure labels**: one row per `fp_min` fingerprint, with
  `label`, `n_runs`, `auto_rule_id`, `first_run`/`last_run`, `keyword`, and
  `block`. `failure_labels_project_max.csv` is the diagnostic window. Regenerate
  the aggregate numbers fresh on every invocation with
  `python check_failures_v2.py <p> --stats` (read-only, backed by
  `label_analysis/failure_labels_v2.db`) before reading either CSV. Legacy v1
  artifacts (`failure_labels_project.csv`, `failure_labels_collapsed_*.csv`,
  `label_analysis/v1/`) are **not** read.
- `projects/<p>/label_analysis/failure_labels_jev_min.csv` — automated System 1
  failure classifications from `check_failures_jev_v2.py`. Only rows with
  `is_pipeline_issue == True` are counted in the triage table. When the audit
  records mode `dedup-keyword`, the source is
  `failure_labels_jev_min_dedup.csv`: one row per `(suite, keyword)` family (the
  row's `fingerprint` is the representative). Never compare its row count with
  the human CSV; the lower count is by design. Family membership is reconstructed
  from the human CSV when it is needed (`--report` does this).
- `projects/<p>/label_analysis/jev_audit.md` — the Jev audit written by the
  `jev-failure-analysis` skill. Its `Snapshot` line records the `labeled_at`
  maximum and the fingerprint/flagged counts used to detect staleness. This is
  the only place Jev findings are written; the overview links to it and reports
  the `Jev audit` state.
- `projects/<p>/install-and-run.sh` and `projects/<p>/command_changes.csv` —
  suite names, runners, and era transitions.
- `projects/<p>/repo` git history — first-parent parent count, PR syntax patterns,
  authors, and file diffs. Used **only when establishing a new overview or when
  explicitly asked to audit development style — do not re-run on routine maintenance.**
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

## Development style

- **PR merging strategy:** <Squash and merge | Merge commit | Rebase | Transitioned (e.g. Merge commit -> Squash and merge in YYYY) | Hybrid>
- **Merge convention:** <e.g. `Title (#<PR>)` | `Merge pull request #<PR> from <branch>` | `Merge branch '<branch>'`>
- **Direct commits:** <None / minimal bot-only | Lead maintainer direct pushes | Release/chore-only bumps>
- **JS/TS code impact of direct commits:** <None / negligible | Hotfixes & ops only (<pct>% JS/TS) | Core logic & tests (<pct>% JS/TS)>
- **Issue tracking discipline:** <High (PR-gated) | Partial | Low / Wild west (<pct>% issue references)>
- **Workflow notes:** <brief description of team workflow, release flow, or solo-maintainer style>

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
- [ ] complete JEV test failure check (<note>)

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

## Failure triage

Source: `python check_failures_v2.py <p> --stats` (window `min`, run <date>) and
`stats_output/report.txt` (generated <date>). Labels:
[`failure_labels_project_min.csv`](label_analysis/failure_labels_project_min.csv)
(primary) and [`failure_labels_project_max.csv`](label_analysis/failure_labels_project_max.csv)
(diagnostic window). These CSVs are the single source of truth; this section
reports numbers only and does not restate per-family labels.

| Metric | Value |
|---|---|
| Failing runs (`report.txt`) | <n> |
| Failing runs (label DB) | <n> (`failing runs` line) |
| Fingerprints (min / max) | <n> / <n> |
| Labeled fingerprints | <n> (<pct>%) |
| Unlabeled fingerprints | <n> |
| acceptable | <n> |
| reevaluated_acceptable | <n> |
| problematic | <n> |
| unclear | <n> |
| false_positive | <n> |
| Manual / auto-propagated labels | <n> / <n> |
| Labeled detections (min) | <n>/<n> (<pct>%) |
| Labeled runs (min) | <n>/<n> (<pct>%) |
| Jev mode | <fingerprint / dedup-keyword> |
| Jev pipeline issues | <n> flagged rows (families in dedup-keyword mode) |
| Jev audit | <current / outdated / missing / n/a> |

**State:** <complete | in progress | stale | not started>.

<Only when `problematic` or `unclear` is non-zero: one table of those families
(label → suite → signature → fingerprint → first/last run → `n_runs`), sourced
from `failure_labels_project_min.csv`. No row for `acceptable` or
`reevaluated_acceptable` families.>

<When the label DB and `report.txt` disagree on the failing-run count, name both
numbers, set State to `stale`, and give the re-label command. Do not reconstruct
a narrative from logs.>

## Environment / setup fixes

<Applied pipeline changes only: fix name, files changed (install-and-run.sh,
Dockerfile, patch-*.js), and a link to `archive/<fix>/README.md`. Record counts
only as stated by that README; do not re-derive run counts, timeout breakdowns, or
per-family signatures. Those belong to the label CSVs and logs.>

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
- **complete JEV test failure check** — automated System 1 labeling via Jev (`label_analysis/failure_labels_jev_min.csv`, or `failure_labels_jev_min_dedup.csv` in `dedup-keyword` mode, produced by `check_failures_jev_v2.py`) evaluated failing runs. A project is done (`✅`) when the Jev CSV exists and either it has zero `is_pipeline_issue == True` labels, or `label_analysis/jev_audit.md` is `current` (its `Snapshot` matches the Jev mode, Jev row count, `labeled_at` maximum, and `failure_labels_project_min.csv`) and attributes every flagged family (upstream defect, pipeline defect, or unclear). The audit records the evidence and the label outcome. In progress (`🟡`) if the CSV exists but the audit is `missing`/`outdated` or a flagged family is unattributed; not done (`❌`) if no Jev CSV exists.

Status symbols (used in the root status table and the per-project checklist):

- `✅` / `- [x]` — done.
- `🟡` / `- [wip]` — work in progress; a run is actively being processed.
- `🚧` / `- [paused]` — paused; a run was partially processed and then stopped
  (for example, awaiting a date-basis switch or a re-run). The Results section
  shows pending commits.
- `🆘` / `- [sos]` — inclusion criterion not met or at risk (for example, coverage
  below the 90% threshold); the project is blocked pending an architectural or
  quality resolution.
- `❌` / `- [ ]` — not done; no work started.

Failure labels (`label_analysis/failure_labels_project_min.csv`):

- `acceptable` — a genuine developer-facing test failure at that commit.
- `problematic` — an environment/setup artifact of this pipeline.
- `unclear` — ambiguous after analysis.
- `false_positive` — not a real failure (for example, captured console output).
- `reevaluated_acceptable` — documented reclassification for failures initially
  labeled `unclear`/`problematic` that static analysis confirms are genuine
  developer-facing failures (see the `labeled-failure-analysis` skill). Assigned
  interactively with the `e` key, and valid as an `auto_classify` rule label, so
  `--auto-classify` propagates it to new occurrences of the same error body.
  Environment/setup artifacts remain labeled `problematic` even after fixes are
  applied so regressions continue to surface.

Failure triage state (`## Failure triage`):

- `complete` — 100% of fingerprints and detections are labeled, and the label DB
  failing-run count equals `stats_output/report.txt`.
- `in progress` — unlabeled fingerprints or detections remain, and the counts
  agree.
- `stale` — the label DB failing-run count differs from `stats_output/report.txt`.
  The label snapshot predates the current `output/`; this takes precedence over
  `complete` and `in progress`.
- `not started` — `label_analysis/failure_labels_project_min.csv` does not exist.
  Report the failing-run count from `stats_output/report.txt` only. Never fall
  back to legacy v1 label files.

`problematic` and `unclear` counts are reported in the table as open issues; they
do not change the state by themselves. A project with 100% labeled runs and
non-zero `problematic` is still `complete` (the artifact remains visible so
regressions surface).

Jev audit state (`Jev audit` row):

- `current` — `label_analysis/jev_audit.md` exists and its `Snapshot` line matches
  both current CSVs: the Jev mode, `labeled_at` maximum, row count, and flagged
  count, plus the human CSV `labeled_at` maximum and fingerprint count.
- `outdated` — the file exists but either snapshot differs; re-run the Jev audit
  (and regenerate the Jev CSV first when its `labeled_at` or the human fingerprint
  count changed). A Jev row-count difference alone is not staleness in
  `dedup-keyword` mode; the Jev row count is lower than the human fingerprint
  count by design.
- `missing` — the Jev CSV has flagged fingerprints but no audit file.
- `n/a` — no Jev CSV (neither fingerprint mode nor `_dedup.csv`).

## Protocol

### Phase 0 — Inventory

1. Read `config.json` and the active-project list from the root `OVERVIEW.md`.
2. Build the active set (exclude `sentry-javascript`). For each project, record
   whether `stats_output/report.txt`, `label_analysis/failure_labels_project_min.csv`,
   `label_analysis/failure_labels_project_max.csv`,
   `label_analysis/failure_labels_v2.db`, and
   `label_analysis/failure_labels_jev_min.csv` (or
   `failure_labels_jev_min_dedup.csv`) exist, plus whether
   `label_analysis/jev_audit.md` exists. A project without the v2
   label artifacts is recorded as `not started`; do not inspect legacy v1 files.
3. Checkpoint: present the active set and the per-project source availability.

### Phase 1 — Per-project drafts

For each active project, build the file from the template:

1. Migrate the legacy section from `projects/OVERVIEW.md.bak` when it is present.
2. **Preserve or populate `## Development style`:**
   - **Do NOT re-analyze development style on routine maintenance invocations.** If `## Development style` is already present in `projects/<p>/OVERVIEW.md`, preserve it as-is.
   - Only perform the git log analysis (first-parent parent count, PR syntax patterns, direct commit JS/TS impact, issue reference rate) when creating a new project overview for the first time or when explicitly requested by the user.
3. Regenerate `stats_output/report.txt` by running `python stats.py <p> --report-only`
   (fresh numbers from the current `output/` state; stale plots are deleted).
   Then pull Results from it. If the command fails, write
   `Results: pending (no stats_output)`.
4. **Build `## Failure triage` from the v2 label source.**
   - Run `python check_failures_v2.py <p> --stats` fresh and take every label
     number from its output (`failing runs`, `fingerprints`, `labeled`,
     `labels`, `coverage`). Do not hand-count CSV rows and do not read legacy
     v1 files; ignore the `v1 reference` line.
   - Compare the label DB failing-run count with `Failing runs` from
     `report.txt`; when they differ, set State to `stale` and name the re-label
     command in one sentence.
   - Add a per-family table **only** when `problematic` or `unclear` is non-zero.
     Source those rows from `label_analysis/failure_labels_project_min.csv`
     (label, suite, signature, fingerprint, first/last run, `n_runs`). Never list
     `acceptable` or `reevaluated_acceptable` families.
   - Count `Jev pipeline issues` from the Jev file recorded by the audit mode.
     Report flagged rows; note that in `dedup-keyword` mode each row is a family.
     Never compare row counts with the human CSV.
   - Set the `Jev audit` row from `label_analysis/jev_audit.md`: `current` when
     its `Snapshot` line matches both current CSVs (Jev mode, Jev and human
     `labeled_at` maxima, Jev rows, flagged count, human fingerprints),
     `outdated` when it differs, `missing` when flags exist without a file, `n/a`
     when no Jev CSV exists. A Jev row-count difference alone is not staleness in
     `dedup-keyword` mode. If the Jev `labeled_at` or the human fingerprint count
     changed, the snapshot predates a re-label: regenerate it (ask first) and
     audit the fresh file. If the audit is `missing` or `outdated`, perform the
     audit following the `jev-failure-analysis` skill (Phases 1–3) or ask the user
     to; do not mark the JEV checklist item `✅` until the audit is `current`.
   - If the v2 artifacts are absent, write `State: not started` and the
     `report.txt` failing-run count only.
5. Link to `config.json` for configuration; do not copy JSON.

### Phase 2 — Root index

Assemble `OVERVIEW.md`: purpose/pointers, legend, the checklist-status table
(one row per active project, linking to its file; columns `100 done`, `failed
tests doublechecked`, `complete run`, `complete test failure check`,
`complete JEV test failure check`, symbols `✅`/`🟡`/`🚧`/`🆘`/`❌`; no numeric
results), cross-cutting infrastructure notes (including `check_failures_jev_v2.py`),
and the maintenance section pointing at this skill.

### Phase 3 — Consistency check

- Every per-project file exists for every active project.
- Root table row count equals the active-project count.
- Root table carries no numeric results (commits, coverage %, hard errors, dates).
- Every checklist cell is `✅`, `🟡`, `🚧`, `🆘`, or `❌`, taken from the per-project file.
- Every `## Failure triage` table was regenerated on this invocation from
  `check_failures_v2.py --stats` and `stats_output/report.txt`.
- No `## Failure triage` section lists `acceptable` or `reevaluated_acceptable`
  families; only aggregate counts and, when non-zero, `problematic`/`unclear`
  families appear.
- Every triage `State` matches its numbers (`stale` whenever the label DB and
  `report.txt` failing-run counts differ, `not started` whenever the v2 label
  artifacts are absent).
- `Jev audit` is `current` (or `n/a`) whenever the JEV checklist item is `✅`, and
  the audit `Snapshot` matches both the current Jev file (mode, rows, `labeled_at`)
  and `failure_labels_project_min.csv`.
- No legacy v1 label artifact is linked or cited.
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
  output of `check_failures_v2.py <p> --stats` (for label counts).
- **The v2 label CSVs are the single source of truth for failure labels.** Never
  restate `acceptable`/`reevaluated_acceptable` families in an overview; list only
  `problematic`/`unclear` families, and only as pointers. Do not re-derive counts
  from logs or from old narratives in `## Environment / setup fixes`.
- **No v1 fallbacks.** A project without `label_analysis/failure_labels_project_min.csv`
  is reported as `State: not started`. Never read `failure_labels_project.csv`,
  `failure_labels_collapsed_*.csv`, or `label_analysis/v1/`.
- **Jev findings live only in `label_analysis/jev_audit.md`.** The overview reports
  the `Jev audit` state and links to the file; it never restates the audit's
  per-family findings. If the audit is `missing`/`outdated`, the JEV checklist
  item cannot be `✅`.
- **Jev row counts are mode-dependent.** In `dedup-keyword` mode the Jev file has
  one row per family (`_dedup.csv`); never compare its row count with the human
  CSV or the fingerprint-mode Jev CSV. The lower count is expected.
- **Root status table is checklist-only.** It never carries numeric results
  (commits, coverage %, hard errors, dates); those live in the per-project
  Results sections.
- **Do not duplicate `config.json`** — link to it.
- **Do not modify** `config.json`, shared pipeline scripts, or any
  `install-and-run.sh`.
- The canonical template lives **only** in this skill.
