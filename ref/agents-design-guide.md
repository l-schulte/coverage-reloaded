# Design Guide — Writing `install-and-run.sh`

> Referenced from `AGENTS.md §6`. Read when writing or modifying `install-and-run.sh`.

## Contract

Runs inside `$REPOPATH` (`/coverage_reloaded/repo`):

- Idempotent; installs **all** deps including devDeps.
- Runs the behavioral suite **with coverage**, producing `lcov.info` file(s) under `$REPOPATH` (outside `node_modules`).
- **Branch on `$IS_NPM_MAIN_PM` / `$IS_YARN_MAIN_PM` / `$IS_PNPM_MAIN_PM`** — never guess the PM.
- **Detect what to run by inspecting the checked-out commit's `package.json` scripts and config files** — not by assuming time ranges.
- `set +e` before tests; capture exit code; **restore `set -e` immediately** before calling `find-and-move-lcov.sh`.
- Call `bash ../find-and-move-lcov.sh [TEST_TYPE] [PREPEND_PATHS] [EXIT_CODE]` after **each** suite.
- `npx` must pin the registry. **Project dependencies** (jest, vitest, etc.) go through WayPack: `npx --registry=$WAYPACK_NPM_REGISTRY jest …`. **Our own tooling** (c8, nyc) goes through Verdaccio: `npx --registry=$VERDACCIO_REGISTRY c8 …`. Never bare `npx`.
- **Do NOT modify** `execute.sh`, `find-and-move-lcov.sh`, `logging.sh` unless the change clearly benefits all projects.

**Logging discipline:**
- **No `2>&1`** — `docker_run.py` already merges stderr into stdout.
- **No `| tail`** — logs are the primary debugging artifact. Use `| head` or `| grep` to narrow.
- **No `||` error suppression**.
- **Use `suite_start` / `suite_end`** for every test suite.

## Suite start/end markers

Every test suite execution must be wrapped:

```bash
suite_start "suite-name" "Human-readable description"
set +e
<test command with coverage>
TEST_EXIT=$?
set -e
bash ../find-and-move-lcov.sh "suite-name" "false" "$TEST_EXIT"
suite_end "suite-name" "$TEST_EXIT"
```

**Log format:** `[SUITE_START] suite-name — description` / `[SUITE_END] suite-name exit_code=N`

**Rules:**
- `suite_name` is short kebab-case (e.g. `unit`, `integration`, `client-unit`).
- `suite_start` emitted **before** `set +e`.
- `suite_end` emitted **after** `find-and-move-lcov.sh` succeeds.
- Only wrap **actual test execution** — not setup, install, or build steps.
- Every `suite_start` needs a matching `suite_end` (even on failure).

## Era detection — read the commit, not dates

**Do not think in eras with fixed date boundaries.** Infer test infrastructure from what the commit actually contains:

1. **`package.json` scripts** — what `test`, `test:unit`, `test:coverage`, etc. exist?
2. **Installed coverage tool** — `c8` or `nyc` in `devDependencies`? `.c8rc.json`, `.nycrc`, or nyc config in `package.json`?
3. **Config files** — `jest.config.*`, `vitest.config.*`, `karma.conf.js`, `.mocharc.*`?

### Decision flow

```bash
TEST_SCRIPT=$(node -p "require('./package.json').scripts.test || ''")
HAS_COVERAGE_SCRIPT=$(node -p "require('./package.json').scripts['test:coverage'] || ''")
HAS_C8=$(node -p "Object.keys(require('./package.json').devDependencies || {}).includes('c8')")
HAS_NYC=$(node -p "Object.keys(require('./package.json').devDependencies || {}).includes('nyc')")
```

Then branch:
- **Dedicated coverage script** (e.g. `test:coverage`, `coverage`) → run it directly.
- **`test` script already invokes c8/nyc/jest `--coverage`** → run `npm test`.
- **c8 in devDeps + `.c8rc.json`** → let c8 use its own config. Do not override.
- **nyc in devDeps + nyc config** → let nyc use its own config. Do not override.
- **No coverage tooling** → wrap test command with `npx c8` or `npx nyc` at defaults.

**Use `command_changes.csv` during design** (see `@ref/agents-pipeline-detail.md §10`) to understand script history. Do not parse it at runtime.

**Prefer running exactly what the project defines.** If `package.json` has `"test:unit": "jest --runInBand"`, use `npm run test:unit`.

## Parallelism

Add `--maxWorkers=1` (jest/vitest) or `--runInBand` (jest) to every test invocation. Parallel execution causes PID exhaustion, port conflicts (EADDRINUSE), and intermittent failures. Exception only for purely computational suites with no subprocesses, network, or file I/O contention.

## Suite exclusions

**Exclude suites for visual-regression snapshotting** (Percy, Vizzly, etc.) — their line hits measure rendering, not behavioral verification. Detect by runner/script and skip; instrument only behavioral suites.

## Monorepo workspace handling

Validate that every package with a `test` script also has coverage config; fail loudly on violations. Keep a whitelist for intentionally-excluded tooling packages.
