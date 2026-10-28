# Coverage Collection — Project Overview

Status index for the longitudinal line-coverage collection. Each active project has
a dedicated `projects/<p>/OVERVIEW.md` with its test infrastructure, coverage
approach, checklist, results, and failure triage.

- Pipeline and design rules: [`AGENTS.md`](AGENTS.md)
- Collection workflow: [`README.md`](README.md)
- Detailed pipeline reference: [`ref/`](ref/)
- Study-level methodology decisions (e.g. author-date dependency snapshots):
  [`STUDY_DECISIONS.md`](STUDY_DECISIONS.md)

## How to read this document

### Checklist

Five items, always in this order:

| Item | Meaning |
|---|---|
| **100 done** | A sample of 100 commits was reviewed. |
| **failed tests doublechecked** | Non-zero-exit runs were inspected and classified. |
| **complete run** | The full commit history has been processed. |
| **complete test failure check** | Every failing run has been labeled and assessed. |
| **complete JEV test failure check** | Automated System 1 labeling via Jev (`label_analysis/failure_labels_jev_min.csv`, or `failure_labels_jev_min_dedup.csv` in dedup-keyword mode) evaluated failing runs. Done when the file has no flagged families or `label_analysis/jev_audit.md` is current. |

Symbols: ✅ done, 🟡 work in progress, 🚧 paused (partially processed), 🆘 inclusion criterion not met or at risk, ❌ not done.

### Run statuses

| Status | Meaning |
|---|---|
| **pass** | No test failures. |
| **fail** | Test failures with exit code 1; coverage is valid (partial). |
| **error** | Hard error (exit code > 1 or no `lcov.info`); no coverage. |
| **not applicable** | The commit has no applicable test infrastructure. |

### Failure labels

Labels in `projects/<p>/label_analysis/failure_labels_project_min.csv` (primary) and
`projects/<p>/label_analysis/failure_labels_project_max.csv` (diagnostic window):

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

|  # | Project                                             | 100 done | failed tests doublechecked | complete run | complete test failure check | complete JEV test failure check |
| -- | --------------------------------------------------- | -------- | -------------------------- | ------------ | --------------------------- | ------------------------------- |
|  1 | [apollo-client](projects/apollo-client/OVERVIEW.md) | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  2 | [bhima](projects/bhima/OVERVIEW.md)                 | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  3 | [compass](projects/compass/OVERVIEW.md)             | ✅       | ✅                         | 🟡           | ❌                          | ❌                              |
|  4 | [desktop](projects/desktop/OVERVIEW.md)             | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  5 | [flowfuse](projects/flowfuse/OVERVIEW.md)           | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  6 | [gatsby](projects/gatsby/OVERVIEW.md)               | ✅       | ✅                         | 🟡           | 🚧                          | 🚧                              |
|  7 | [material-ui](projects/material-ui/OVERVIEW.md)     | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  8 | [matrix-js-sdk](projects/matrix-js-sdk/OVERVIEW.md) | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
|  9 | [moodleapp](projects/moodleapp/OVERVIEW.md)         | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 10 | [n8n](projects/n8n/OVERVIEW.md)                     | ✅       | ✅                         | ✅           | ✅                          | ❌                              |
| 11 | [opencrvs-core](projects/opencrvs-core/OVERVIEW.md) | ✅       | ✅                         | 🟡           | 🚧                          | 🚧                              |
| 12 | [openneuro](projects/openneuro/OVERVIEW.md)         | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 13 | [pf2e](projects/pf2e/OVERVIEW.md)                   | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 14 | [sequelize](projects/sequelize/OVERVIEW.md)         | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 15 | [spreed](projects/spreed/OVERVIEW.md)               | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 16 | [uploader](projects/uploader/OVERVIEW.md)           | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 17 | [uwazi](projects/uwazi/OVERVIEW.md)                 | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 18 | [vega-lite](projects/vega-lite/OVERVIEW.md)         | ✅       | ✅                         | ✅           | ✅                          | ✅                              |
| 19 | [webpack](projects/webpack/OVERVIEW.md)             | ✅       | ✅                         | ✅           | 🚧 (todo: 6837)             | ❌                              |
| 20 | [wowanalyzer](projects/wowanalyzer/OVERVIEW.md)     | ✅       | ✅                         | ✅           | ✅                          | ✅                              |

## Cross-cutting infrastructure
^
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
- **`check_failures_v2.py <project>`** detects failure families in non-zero-exit
  runs and writes `label_analysis/failure_labels_project_{min,max}.csv` backed by
  `label_analysis/failure_labels_v2.db`; `--stats` reports the label numbers used
  by the per-project failure triage.
- **`check_failures_jev_v2.py`** evaluates failing runs with the automated System 1
  model (Jev), writing `failure_labels_jev_min.csv` or, in dedup-keyword mode,
  `failure_labels_jev_min_dedup.csv` (one row per family). Its conclusions are
  audited in `label_analysis/jev_audit.md`.

## Host system prerequisites

Settings on the **host machine**, outside this repository and its containers. Unlike the
per-project fixes, these are not project- or container-scoped: they apply to every user
and every container on the shared host and must therefore be applied and reverted
deliberately.

### `fs.aio-max-nr` async-I/O budget (temporarily raised, 2026-10-09)

`fs.aio-max-nr` is the host-wide ceiling on Linux native asynchronous-I/O events
allocated by `io_setup()`; `fs.aio-nr` is the number currently reserved. `io_setup()`
returns `EAGAIN` once `aio-nr` reaches `aio-max-nr` (kernel
`Documentation/sysctl/fs.txt`; `io_setup(2)`). The budget is **global and not
namespaced**, so all containers and all users on the host share it.

Several project database containers (MySQL/MariaDB InnoDB, SQL Server) allocate a
native-AIO context at startup. On this 256-CPU host each instance reserves **17 408
events** (≈68 I/O threads × 256), measured directly. With the kernel default
`fs.aio-max-nr = 65536` and ~26 688 events already held by long-lived services, only ~2
concurrent database instances fit; a third `io_setup()` fails, the engine aborts at boot
(`InnoDB: io_setup() failed with EAGAIN`; SQL Server `Unable to create a new
asynchronous I/O context`), the container exits, and its health check can never pass —
recorded as a hard error.

- **Applied:** `sudo sysctl -w fs.aio-max-nr=1048576` (65536 → 1048576; ≈58 concurrent
  database instances). Runtime only; not persisted under `/etc/sysctl.d/`, so a reboot
  restores 65536.
- **Revert** once collection on the affected projects is finished:
  `sudo sysctl -w fs.aio-max-nr=65536` (or reboot).
- **Scope:** host-wide and shared with all other users and containers on the machine.
- **No container-level alternative:** Podman cannot bound this value — it is not
  namespaced (not settable with `--sysctl`), `--cpuset-cpus` is unavailable under
  rootless Podman here, and SQL Server ignores the CPU set regardless because it reads
  the un-namespaced `/proc/cpuinfo` (cf. Red Hat BZ 1985491). `lxcfs` is not installed.
- **Complementary in-repo mitigation (mysql/mariadb only):** `install-and-run.sh`
  injects `--innodb-use-native-aio=0` into each mysql/mariadb compose service so those
  engines no longer call `io_setup()`. This lowers the pressure but does not cover SQL
  Server, so it cannot replace the host limit.

## Maintenance

This document and the per-project files follow the
[`maintain-project-overviews`](.agents/skills/maintain-project-overviews/SKILL.md)
skill, which defines the canonical template, the technical-English style guide, the
data sources, and the update protocol. Update the per-project files after a
collection run or a re-labeling pass, then refresh the status table above.

Excluded and archived projects are out of scope here; they remain under
[`archive/`](archive/), each with its archived overview at
`archive/<p>/OVERVIEW.md`.
