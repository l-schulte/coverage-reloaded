# edge-react-gui

> **Archived project (inaccessible issues).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

Root workspace with jest.

- `test`: default, sometimes uses `jest.config.js` or calls `test:sync` and `test:async`
- `test:sync`: jest with `jest.config.js`
- `test:async`: jest with `jest.async.config.js`

We call jest directly with whichever config is available.

## Config

```json
"edge-react-gui": {
    "url": "https://github.com/EdgeApp/edge-react-gui"
}
```

## Checklist

- [x] 100 done (96/100, installation process fails flaky)
- [x] failed tests doublechecked (ok)
    * between 2025-06 and 2022-09 the same test fails: expects 185, got 184
    * between 2021-05 and 2020-12... no tests fail, exit code is 1 because it skips one test.
- [x] complete run (~97% of commits successfull, after re-run of errors, might have duplicate logfiles)