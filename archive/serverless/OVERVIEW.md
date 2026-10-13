# serverless

**Repository:** https://github.com/serverless/serverless
**Status:** archived

## Test infrastructure

- **Package manager:** npm, root workspace (see [`config.json`](../../config.json) → `serverless`).
- **Node strategy:** `min_node_version = 12`.
- **Runners:** `mocha`, `nyc`, `c8`.
- **Eras:** two coverage eras: `nyc` (early 2020) and `c8` (dominant from around
  2020 onward).

## Coverage collection

- **Suites collected:** `test`, the primary suite (mocha-based).
- **Suites excluded:** none.
- **Coverage tool / config:** `nyc` (`nyc --reporter=lcov`) or `c8`
  (`c8 --reporter=lcov`) depending on the era.
- **LCOV production:** `nyc`/`c8` `lcov` reporter.

## Checklist

- [x] 100 done (99/100)
- [x] failed tests doublechecked
- [sos] complete run (all 2,765 commits processed — coverage 78.4%, below the 90% inclusion criterion)
- [paused] complete test failure check (534 hard errors; awaiting resolution)

## Results

Source: `stats_output/report.txt` (generated 2026-09-19 12:31).

| Metric | Value |
|---|---|
| Commits processed | 2765 |
| Without test failures | 1251 |
| With test failures | 690 |
| Not applicable | 290 |
| Hard errors | 534 |
| Coverage produced | 78.4% |

0 commits are not yet processed.

Full statistics and plots: [`stats_output/`](stats_output/).

## Known test failures

| Signature | Classification | Coverage impact | Action |
|---|---|---|---|
| `#invokeLocalRuby context.remainingTimeInMillis should become lower over time` and `#invokeLocalRuby calling a class method should execute` — `SyntaxError: Unexpected token t in JSON at position 1` | problematic | none; Ruby invocation logic is covered by passing stub tests | None. The Ruby wrapper's `attach_tty` method prints `"tty unavailable"` in the container (no TTY device), so the output starts with `t` instead of JSON. Verified with Ruby 2.7 across 2020–2025 commits. |
| Author-date dependency snapshot `ETARGET` / `ENOVERSIONS` (407 commits) | unresolved | 407 commits fail at `npm install` (zero coverage) | **Unresolved / Paused.** See detailed analysis below. |
| `Cannot find module '../../../commands/logout'` | problematic | 93 commits abort at Mocha load (zero coverage) | Unresolved. In upstream PR #12335 (Jan 2024), `commands/logout.js` was deleted but `test/unit/commands/logout.test.js` was left until Dec 2025. |

### Details: Author-Date Dependency Snapshot & Pre-Release Resolution Attempt

Under the author-date snapshot policy ([`STUDY_DECISIONS.md` §1](../../STUDY_DECISIONS.md)), 407 commits fail with `ETARGET` or `ENOVERSIONS` during `npm install` because dependencies declared in `package.json` were not yet published on npm at the commit's author date:

- **246 commits:** The Serverless Framework v3.0.0 release-train rebase cluster (`73cb9cdef`..`c15004519` on base `cb58fb996`). Author dates span 2021-10-20 to 2022-01-25, but all share committer timestamp `1643293318` (release day 2022-01-27).
- **161 commits:** Feature PR branches rebased onto `main`. When rebased, these commits inherited dependencies that were bumped on `main` *after* the feature branch's author date (e.g. `aws-sdk@^2.891.0`, `aws-sdk@^2.1062.0`, `@serverless/dashboard-plugin@^5`, `@serverless/components@^3`).

#### Mitigation Attempt: `allow-prerelease-deps.js`
A standalone script ([`allow-prerelease-deps.js`](allow-prerelease-deps.js)) was added to the project container and called prior to `npm install` in `install-and-run.sh`. The script rewrites caret/tilde ranges of `@serverless/*` packages in `package.json` to append `-0` (e.g. `^6.0.0` → `^6.0.0-0`), signaling npm to accept published `pre.*` versions when stable releases do not yet exist.

#### Outcome & Root Incompatibilities:
While `allow-prerelease-deps.js` successfully allows npm to resolve published companion pre-releases (e.g. `@serverless/dashboard-plugin@6.0.0-pre.ffadbdc1`), the issue remains **unresolved** due to three fundamental blockers:
1. **Unpublished rebase dependencies:** For cluster commits authored before Jan 19, 2022, `package.json` requires `@serverless/components@^3.18.2` (and `aws-sdk@^2.1062.0`), which were published on npm only on Jan 19 or later.
2. **CamelCase vs. Kebab-Case rename mismatch:** For cluster commits authored after Jan 20, 2022, the framework source code requires the kebab-case path `@serverless/dashboard-plugin/lib/resolve-provider-credentials`. However, the companion pre-releases on npm only shipped the camelCase file `resolveProviderCredentials.js` (the kebab-case rename was published on release morning Jan 27). Bridging this via filesystem symlinks was considered and rejected as direct interference with historical code.
3. **Third-party packages:** External dependencies like `aws-sdk` have no pre-releases and were published strictly after the commit author timestamp.

Work on `serverless` is paused until an architectural resolution for timestamp skew / un-buildable historical commits is decided.

## Environment / setup fixes

- `allow-prerelease-deps.js`: Standalone script copied into Docker container and invoked in `install-and-run.sh` to allow pre-release range resolution for `@serverless/*` dependencies.

## Known gaps

290 commits are **not applicable**: they depend on `@serverlessinc/sf-core`, which is closed source.
