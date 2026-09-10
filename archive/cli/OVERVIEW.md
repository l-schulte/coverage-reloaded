# cli

> **Archived project (coverage gate).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Root and workspaces using `tap`.

- `test:coverage` uses the nyc-based --coverage flag
- `test` just calls tap

We call tap directly, appending the `--nyc-arg=--reporter=lcov` parameter.

⚠️ Coverage gate: defaults to 100% lines, checked between 08.2020 and 03.2024.
Commits often reach it.

**Reason for exclusion:** Coverage threshold at 100% lines makes coverage
indistinguishable from behavioral verification. Commits that reach the threshold
inflate the exposure variable.