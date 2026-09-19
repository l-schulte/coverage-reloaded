# Coverage Collection — Project Overview

Status index for the longitudinal line-coverage collection. Each active project has
a dedicated `projects/<p>/OVERVIEW.md` with its test infrastructure, coverage
approach, checklist, results, and known test failures.

- Pipeline and design rules: [`AGENTS.md`](AGENTS.md)
- Collection workflow: [`README.md`](README.md)
- Detailed pipeline reference: [`ref/`](ref/)
- Study-level methodology decisions (e.g. author-date dependency snapshots):
  [`STUDY_DECISIONS.md`](STUDY_DECISIONS.md)

## How to read this document

### Checklist

Four items, always in this order:

| Item | Meaning |
|---|---|
| **100 done** | A sample of 100 commits was reviewed. |
| **failed tests doublechecked** | Non-zero-exit runs were inspected and classified. |
| **complete run** | The full commit history has been processed. |
| **complete test failure check** | Every failing run has been labeled and assessed. |

Symbols: ✅ done, 🟡 work in progress, 🚧 paused (partially processed), ❌ not done.

### Run statuses

| Status | Meaning |
|---|---|
| **pass** | No test failures. |
| **fail** | Test failures with exit code 1; coverage is valid (partial). |
| **error** | Hard error (exit code > 1 or no `lcov.info`); no coverage. |
| **not applicable** | The commit has no applicable test infrastructure. |

### Failure labels

Labels in `projects/<p>/failure_labels_project.csv`:

| Label | Meaning |
|---|---|
| `acceptable` | A genuine developer-facing test failure at that commit. |
| `problematic` | An environment/setup artifact of this pipeline. |
| `unclear` | Ambiguous after analysis. |
| `false_positive` | Not a real failure (for example, captured console output). |
| `reevaluated_acceptable` | Documented reclassifications. |

### Inclusion criterion

At least 90% of a project's commits from the last five years must produce valid
coverage.

## Project status at a glance

Checklist status per active project, taken from each project's `OVERVIEW.md`.
Numeric results (commits processed, coverage %, hard errors) and their generation
dates live in the per-project Results sections, sourced from
`stats_output/report.txt`.

| Project | 100 done | failed tests doublechecked | complete run | complete test failure check |
|---|---|---|---|---|
| [apollo-client](projects/apollo-client/OVERVIEW.md) | ✅ | ✅ | ✅ | ✅ |
| [apostrophe](projects/apostrophe/OVERVIEW.md) | ✅ | ✅ | ❌ | ❌ |
| [bhima](projects/bhima/OVERVIEW.md) | ✅ | ✅ | ✅ | ✅ |
| [flowfuse](projects/flowfuse/OVERVIEW.md) | ✅ | ✅ | 🚧 | ❌ |
| [gatsby](projects/gatsby/OVERVIEW.md) | ✅ | ✅ | 🟡 | 🚧 |
| [material-ui](projects/material-ui/OVERVIEW.md) | ✅ | ✅ | 🟡 | ❌ |
| [matrix-js-sdk](projects/matrix-js-sdk/OVERVIEW.md) | ✅ | ✅ | ❌ | ❌ |
| [moodleapp](projects/moodleapp/OVERVIEW.md) | ✅ | ✅ | ✅ | ✅ |
| [n8n](projects/n8n/OVERVIEW.md) | ✅ | ❌ | 🟡 | ❌ |
| [opencrvs-core](projects/opencrvs-core/OVERVIEW.md) | ✅ | 🟡 | ❌ | ❌ |
| [openneuro](projects/openneuro/OVERVIEW.md) | ✅ | ✅ | ❌ | ❌ |
| [pf2e](projects/pf2e/OVERVIEW.md) | ✅ | ✅ | ✅ | ✅ |
| [rxdb](projects/rxdb/OVERVIEW.md) | ✅ | ✅ | 🟡 | ❌ |
| [serverless](projects/serverless/OVERVIEW.md) | ✅ | ✅ | 🚧 | 🚧 |
| [spreed](projects/spreed/OVERVIEW.md) | ✅ | ✅ | 🟡 | ❌ |
| [uploader](projects/uploader/OVERVIEW.md) | ✅ | ✅ | ❌ | ❌ |
| [uwazi](projects/uwazi/OVERVIEW.md) | ✅ | ✅ | 🚧 | ❌ |
| [vega-lite](projects/vega-lite/OVERVIEW.md) | ✅ | ✅ | 🚧 | ❌ |
| [wowanalyzer](projects/wowanalyzer/OVERVIEW.md) | ✅ | ✅ | ✅ | ✅ |
| [yari](projects/yari/OVERVIEW.md) | ✅ | ✅ | 🚧 | ❌ |

## Cross-cutting infrastructure

- **WayPack Machine** serves each package as it existed at the commit timestamp
  (`/npm/<ts>/<pkg>`, `/yarn/<ts>/<pkg>`, `/pip/<ts>/<pkg>`). It must be running on
  the `mining-net` Docker network. Local overrides live in
  `waypack-machine/local_files/`.
- **`helper/fake-time-node.js`** wraps a Node command with libfaketime so
  time-relative tests run at the commit timestamp. It is used by `bhima` and is the
  standard probe for time-dependent failures.
- **`projects/flowfuse/pool-shim.js`** forces a single SQLite `:memory:` connection
  (`pool: { max: 1, min: 1 }`) to fix a pooled-connection migration race.
- **`stats.py <project>`** scans `projects/<p>/output/` and writes the CSVs, plots,
  and `stats_output/report.txt` used as the Results source.
- **`check_failures.py`** and **`collapse_labels.py`** classify non-zero-exit runs
  and collapse `problematic`/`unclear` rows into error families.

## Maintenance

This document and the per-project files follow the
[`maintain-project-overviews`](.agents/skills/maintain-project-overviews/SKILL.md)
skill, which defines the canonical template, the technical-English style guide, the
data sources, and the update protocol. Update the per-project files after a
collection run or a re-labeling pass, then refresh the status table above.

Excluded and archived projects are out of scope here; they remain under
[`archive/`](archive/), each with its archived overview at
`archive/<p>/OVERVIEW.md`.
