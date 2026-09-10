# govuk-frontend

> **Archived project.** Content extracted from the legacy single-file
> `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Tests are fully jest based; we run `test` and inject the coverage flag. Workspaces
do not have their own general `test` script, only screenshot-test scripts.

> ⚠️ Early commits use `jest` only to invoke `jest-puppeteer`, for which coverage
> collection is not possible. → Archive

## Config

```json
"govuk-frontend": {
    "url": "https://github.com/alphagov/govuk-frontend"
}
```

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked (seem like UI related errors, e.g., "scrolls the label or legend to the top of the screen" expectin 0 and receiving 0.828...)
- [no] complete run (----)

## V8 Instrumentation Drift (Node 22 → 24)

> **Note:** A >15pp line coverage rise and branch coverage drop between commits `5f4c845...` and `1748fe8...` is attributed to Node 22 (V8 12.x) → Node 24 (V8 13.6) instrumentation changes rather than behavioral code modifications.

- **Delta composition:** +963 line hits (+41.8%) consist almost entirely of `0→1` increments. Zero `covered→0` reversals observed.
- **Code pattern:** Delta lines are predominantly JSDoc blocks, class property declarations, and method signatures (e.g., `constructor`, `initControls()`), rather than executable logic. Validated across `accordion.mjs`, `button.mjs`, `tabs.mjs` (70-85% JSDoc/comments).
- **Root cause:** V8 12.x → 13.6 instrumentation maps preceding JSDoc blocks and ES method opening braces `{` as new branch entries, increasing coverage counts without corresponding behavioral execution changes.
- **Classification:** Environment-driven measurement variation — does not reflect code evolution or test behavior changes. Coverage data remains valid for the exposure variable; the delta represents instrumentation differences between V8 versions.

## Implementation notes

- `install-and-run.sh` replaces all GitHub URLs in source files (excluding
  `package.json`) with WayPack proxy URLs.