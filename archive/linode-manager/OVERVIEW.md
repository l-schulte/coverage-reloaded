# linode-manager

> **Archived project (inaccessible issues).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

The linode-manager project is a monorepo that runs 8 named test suites, detected by
checking for specific root scripts. Each suite resolves to either a root-level
command or a workspace package's test script, and runs via vitest (with
`@vitest/coverage-istanbul`) or jest, both with coverage enabled and `--bail=0`. If
none of the named scripts exist, it falls back to the generic `test` script.

- **`test:manager`** — runs tests for the manager package (jest or vitest)
- **`test:sdk`** — runs tests for the SDK package
- **`test:ui`** — runs UI component tests
- **`test:search`** — runs search-related tests
- **`test:validation`** — runs validation package tests
- **`test:utilities`** — runs utilities package tests
- **`test:queries`** — runs query-related tests
- **`test:shared`** — runs shared package tests
- **Fallback `test`** — only if none of the above scripts exist

Skipping build-only and lerna bootstrap scripts. Coverage is collected per-suite via
lcov, using the project's native runner (vitest or jest).

## Config

```json
"linode-manager": {
    "url": "https://github.com/linode/manager"
}
```

## Checklist

- [x] 100 done (96/100)
- [x] failed tests doublechecked (genuine errors)
- [no] complete run (cancelled moved to archive)

## Known Test Failures

- Async issues, timeouts and assertion errors in `unit` suite
- Timeouts and "unable to find an element" UI validation in `test:manager` suite

## Implementation notes

- `install-and-run.sh` patches `packages/manager/scripts/buildRequests.js` to skip
  live API caching during build.