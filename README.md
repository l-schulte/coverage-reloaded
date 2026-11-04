# Longitudinal Code Coverage Collection for JavaScript and TypeScript

This repository provides an automated, reproducible execution harness for collecting longitudinal, line-based test coverage across the version histories of mature JavaScript and TypeScript systems. Designed for empirical software engineering research, the pipeline reconstructs historical software environments to measure code coverage as an exposure variable without confounding by test execution bailouts, coverage threshold gates, or unversioned dependency drift.

---

## 1. Overview & Methodological Design

Empirical studies investigating the causal relationship between test coverage and software defect introduction require unbiased historical coverage measurements. Measuring historical coverage accurately in dynamic ecosystems (such as Node.js) presents specific validity challenges:

- **Historical Dependency Reproducibility:** Historical package dependencies are pinned to their commit timestamp using the [WayPack Machine](https://codeberg.org/l-schulte/waypack-machine), eliminating dependency drift and modern proxy interference.
- **Strict Execution (No Bail):** Tests must never terminate early on failure (no `--bail`, `--fail-fast`, or `bail: true`). A bailed run exercises only a fraction of the test suite yet emits structurally valid coverage, resulting in severe measurement bias.
- **Coverage Gate Disablement:** Quality gates (e.g., `coverageThreshold` in Jest or `--check-coverage` in nyc) exit with non-zero status when coverage drops below a target floor, conflating behavioral failures with measurement thresholds. All such enforcement is neutralized.
- **Focus Marker Guarding:** Committed focus markers (`describe.only`, `it.only`) truncate suites silently. Depending on the runner semantics, affected runs are marked not-applicable or flagged via sidecar deficit logs.

---

## 2. System Architecture & Repository Layout

The pipeline operates via a multi-tiered orchestration model:

```
HOST (main.py)
  └── docker-run.sh (Podman / Docker)
        └── CONTAINER (execute.sh)
              └── install-and-run.sh (per-project)
                    ├── helper/ (logging, LCOV extraction, faked time, focus guards)
                    └── WayPack Machine (temporal package registry)
```

### Directory Structure

```
├── main.py                     # Primary host-side orchestration entrypoint
├── docker-run.sh               # Host container launcher (supports Podman and Docker)
├── execute.sh                  # In-container driver (tmpfs mount, checkout, execution)
├── Dockerfile                  # Base Debian image with multi-Node version tooling
├── config.json                 # Global study configuration and per-project parameters
│
├── helper/                     # IN-CONTAINER collection helpers (mounted into containers)
│   ├── assert-suite-ran.sh     # Validates test suites actually executed (guards zero-test runs)
│   ├── fake-time.sh            # Environmental time-travel wrapper
│   ├── fake-time-node.js       # libfaketime preload shim for Node runtimes
│   ├── find-and-move-lcov.sh   # Validates, normalizes, and extracts LCOV artifacts
│   ├── has-option.sh           # CLI flag presence detector
│   ├── logging.sh              # Structured logging and suite boundary markers
│   ├── na-if-focus-marker.sh   # Scans for committed .only focus markers
│   ├── resolve-and-pin.sh      # DNS resolution and registry pin fallback
│   └── start-dind.sh           # Docker-in-Docker service initialization helper
│
├── scripts/                    # HOST-SIDE analysis and maintenance utilities
│   ├── failure_triage/         # Failure categorization, normalization, and fingerprinting package
│   ├── stats/                  # Coverage data scanning, aggregation, and plotting package
│   ├── check_failures_v2.py    # CLI for interactive and automated failure classification
│   ├── check_failures_jev_v2.py# LLM-assisted failure classification CLI (Jev system)
│   ├── check_lcov_sanity.py    # Audits LCOV files against historical git source trees
│   ├── check_validity.py       # Retroactively validates output runs for abnormal runner behaviour
│   ├── archive_commits.py      # Archives runs discordant with commits.csv
│   ├── archive_fixed_commits.py# Archives runs affected by resolved environment issues
│   ├── bin_excess_commits.sh   # Stashes runs not present in regenerated commit sets
│   └── strip_lcov_prefix.py    # Normalizes path prefixes in SF: records
│
├── projects/                   # Active study projects
│   └── <project_name>/
│       ├── Dockerfile          # Project-specific container layer (system dependencies)
│       ├── install-and-run.sh  # Project test execution script across chronological eras
│       ├── commits.csv         # Target commits, timestamps, and resolved Node/PM versions
│       ├── command_changes.csv # Test command evolution across project history
│       ├── OVERVIEW.md         # Status checklist, test eras, and environment fixes
│       ├── output/             # Collected LCOV coverage artifacts and exit codes
│       ├── logs/               # Raw standard output and error logs per commit
│       └── label_analysis/     # Failure fingerprints and triage databases
│
└── archive/                    # Archived evaluations and deprecated projects
```

---

## 3. Prerequisites & Environment Setup

### Host Requirements
- **Operating System:** Linux (Ubuntu 20.04+ or Debian 11+ recommended).
- **Container Engine:** Podman (default) or Docker with rootless support.
- **Python:** Python 3.10 or newer.
- **Network Bridge:** A user-defined network named `mining-net` must exist for container communication:
  ```bash
  podman network create mining-net
  # or: docker network create mining-net
  ```

### WayPack Machine (Temporal Package Registry)
The pipeline relies on the WayPack Machine to serve packages at the specific epoch timestamp of each commit:
1. Clone the WayPack Machine repository:
   ```bash
   git clone https://codeberg.org/l-schulte/waypack-machine.git waypack-machine
   ```
2. Launch the registry container services:
   ```bash
   cd waypack-machine
   docker compose up -d
   cd ..
   ```

### Python Dependencies
Set up a Python virtual environment and install dependencies:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

---

## 4. Execution Workflows

### 1. Generating Commit Schedules
Commit schedules define the chronological commits, resolved Node.js engines, and package managers for each project:
```bash
# Generate commits.csv for a specific project
python3 main.py --project <project_name> --mode commits-only

# Limit the temporal scope
python3 main.py --project <project_name> --mode commits-only --start-date 2021-01-01 --end-date 2026-01-01
```

### 2. Running Coverage Collection
Coverage execution builds the required base and project container images, checks out each commit into an in-memory `tmpfs` volume, executes the test suite, and extracts normalized LCOV files.
```bash
# Collect coverage for all pending commits in a project
python3 main.py --project <project_name> --mode coverage-only --max-workers 8

# Re-run only commits that previously failed
python3 main.py --project <project_name> --mode retry-failed

# Execute a single commit
python3 main.py --project <project_name> --mode single-commit --commit-hash <hash>
```

### 3. Interactive Debugging
To debug a failing environment or test suite interactively for a specific commit:
```bash
bash docker-run.sh <project_name> shell <commit_hash> <timestamp> <package_manager> <node_version>
```
Inside the container:
- The target repository is located at `/coverage_reloaded/repo`.
- Run `/coverage_reloaded/install-and-run.sh` to trace dependency installation and test execution.
- Coverage output is directed to `/coverage_reloaded/coverage`.

### 4. Post-Collection Auditing and Statistics
```bash
# Verify LCOV coverage integrity against git source trees
python3 scripts/check_lcov_sanity.py <project_name> --verbose

# Retroactively validate runs for silent zero-test anomalies
python3 scripts/check_validity.py <project_name>

# Compute summary statistics and generate report.txt
python3 scripts/stats.py <project_name> --report-only

# Classify and analyze test failures
python3 scripts/check_failures_v2.py <project_name> --stats
```

---

## 5. Active Study Projects

The study includes 20 mature, active open-source JavaScript and TypeScript projects spanning diverse architectural patterns, application domains, and test runner ecosystems.

| # | Project | Repository | Primary Ecosystem | Test Runner(s) | Description |
|---|---------|------------|-------------------|----------------|-------------|
| 1 | **apollo-client** | [apollographql/apollo-client](https://github.com/apollographql/apollo-client) | TypeScript / JS | Jest | Comprehensive state management and caching GraphQL client library for web applications. |
| 2 | **babel** | [babel/babel](https://github.com/babel/babel) | JavaScript / TS | Jest (`jest-light-runner`) | Multi-package compiler and transpilation toolchain converting ECMAScript 2015+ syntax into backwards-compatible JavaScript. |
| 3 | **bhima** | [third-culture-software/bhima](https://github.com/third-culture-software/bhima) | JavaScript | Mocha (c8), Karma (`karma-coverage`) | Modular Enterprise Resource Planning (ERP) and clinical management platform designed for healthcare facilities in resource-limited settings. |
| 4 | **compass** | [mongodb-js/compass](https://github.com/mongodb-js/compass) | TypeScript / JS | Mocha (nyc) | Official interactive graphical user interface and data visualization client for MongoDB databases. |
| 5 | **desktop** | [desktop/desktop](https://github.com/desktop/desktop) | TypeScript (Electron) | Jest, Node test runner (`node:test` via c8) | Desktop GUI client for Git version control and GitHub workflow management. |
| 6 | **flowfuse** | [FlowFuse/flowfuse](https://github.com/FlowFuse/flowfuse) | JavaScript / TS | Mocha, Vitest | Collaborative operational management platform and console for Node-RED visual IoT workflows. |
| 7 | **gatsby** | [gatsbyjs/gatsby](https://github.com/gatsbyjs/gatsby) | JavaScript / TS | Jest | Monorepo static site generator and modern web application framework based on React and GraphQL. |
| 8 | **material-ui** | [mui/material-ui](https://github.com/mui/material-ui) | TypeScript / JS | Mocha (nyc), Vitest | Modular component library providing an implementation of Google's Material Design system for React. |
| 9 | **matrix-js-sdk** | [matrix-org/matrix-js-sdk](https://github.com/matrix-org/matrix-js-sdk) | TypeScript / JS | Jest | Client SDK providing access to the Matrix federated, decentralized real-time communication protocol. |
| 10 | **moodleapp** | [moodlehq/moodleapp](https://github.com/moodlehq/moodleapp) | TypeScript (Angular / Ionic) | Jest, Karma (`ng test`) | Official cross-platform mobile application for the Moodle learning management system (LMS). |
| 11 | **openneuro** | [openneuroorg/openneuro](https://github.com/openneuroorg/openneuro) | TypeScript / JS | Jest, Vitest | Open-science data repository and cloud processing platform for neuroimaging datasets structured via BIDS. |
| 12 | **pf2e** | [foundryvtt/pf2e](https://github.com/foundryvtt/pf2e) | TypeScript | Jest | System implementation and tactical game rules automation engine for Pathfinder 2nd Edition on Foundry Virtual Tabletop. |
| 13 | **prebid** | [prebid/Prebid.js](https://github.com/prebid/Prebid.js) | JavaScript | Karma (Mocha adapter) | Open-source header bidding solution enabling web publishers to solicit simultaneous real-time advertising auctions. |
| 14 | **sequelize** | [sequelize/sequelize](https://github.com/sequelize/sequelize) | TypeScript / JS | Mocha (c8) | Object-Relational Mapper (ORM) supporting PostgreSQL, MySQL, MariaDB, SQLite, DB2, and Microsoft SQL Server. |
| 15 | **spreed** | [nextcloud/spreed](https://github.com/nextcloud/spreed) | JavaScript / Vue | Jest, Vitest (`vue-cli-service`) | Nextcloud Talk audio/video conferencing, screen sharing, and messaging application integration. |
| 16 | **uploader** | [tidepool-org/uploader](https://github.com/tidepool-org/uploader) | JavaScript (Electron) | Jest (Electron runner) | Desktop application for retrieving, decoding, and uploading data from diabetes devices (insulin pumps, CGMs, blood glucose meters). |
| 17 | **uwazi** | [huridocs/uwazi](https://github.com/huridocs/uwazi) | TypeScript / JS | Jest | Document repository and structured database tool designed for human rights documentation, legal investigation, and public archives. |
| 18 | **vega-lite** | [vega/vega-lite](https://github.com/vega/vega-lite) | TypeScript | Jest, Vitest | High-level declarative grammar for statistical graphics, compiling compact JSON specifications into lower-level Vega visualization models. |
| 19 | **webpack** | [webpack/webpack](https://github.com/webpack/webpack) | JavaScript | Jest | Configurable module bundler and asset compiler for modern web applications. |
| 20 | **wowanalyzer** | [wowanalyzer/wowanalyzer](https://github.com/wowanalyzer/wowanalyzer) | TypeScript / JS | Jest (`react-app-rewired`), Vitest | Analytical platform evaluating combat logs from World of Warcraft encounters to provide automated gameplay diagnostics. |
