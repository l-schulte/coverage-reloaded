# sentry-javascript

> **Archived project (integration-test issues).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Unit tests are simple, but there are different integration tests for the packages:

- remix
    - lerna
        - client: `yarn playwright test`
        - server: `jest --config=...`
    - workspace
        - client: `yarn playwright test`
        - server: `jest --config=...`, later `vitest run`
- browser
    - lerna
        - default: `test/integration/run.js`
    - workspace
        - default: `test/integration/run.js`
- nextjs (workspace and lerna)
    - lerna:
        - client: `yarn playwright test`
        - server: `jest --config=...`
    - workspace:
        - client: `node test/client.js --silent`, later `yarn playwright test`
        - server: `node test/server.js --silent`, later `jest --config=`, then `(cd test/integration && yarn test:server)`

Additionally, there are various integration-specific workspaces. Archiving the
project because of the complexity of the integration tests and the difficulty of
running them in a containerized environment. The integration tests require a large
dependency tree of browsers, playwright, and other services that are not easily
containerized at correct versions.

## Config

```json
"sentry-javascript": {
    "url": "https://github.com/getsentry/sentry-javascript"
}
```

## Checklist

- [no] 100 done
- [no] failed tests doublechecked
- [no] complete run