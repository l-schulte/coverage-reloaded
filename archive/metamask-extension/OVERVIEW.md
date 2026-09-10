# metamask-extension

> **Archived project (coverage gate).** Content extracted from the legacy
> single-file `projects/OVERVIEW.md` (2026-09-10) to preserve the information.

⚠️ Coverage Gates:

- nyc --check-coverage era (Mar 2020 – Apr 2021): Low risk — the 0% default made it a no-op.
    * [link](https://github.com/MetaMask/metamask-extension/blob/b1d090ac4d/package.json#L28-L30)
- jest coverageThreshold era (Apr 2021 – Jan 2023): Moderate risk — thresholds were low (6–52%) but rising, and jest-it-up prevented drops >5%.
    * [link](https://github.com/MetaMask/metamask-extension/blob/01c0d7823d988d15ddedbf9ad8fa6ca5f7f6ca73/jest.config.js#L12-L24)
- Custom merge-coverage.js era (Jan 2023 – Jun 2024): High risk — thresholds were substantial (57–71% lines) and the script also failed if coverage exceeded the threshold by >5%, creating a strong incentive to keep coverage within a narrow band.
    * [link](https://github.com/MetaMask/metamask-extension/blob/f6acedb6cc72f79f043317e5e1390e3cd62c05f7/coverage-targets.js)

**Reason for exclusion:** Three distinct eras of coverage gates with increasingly
strict thresholds. The merge-coverage.js era also penalized exceeding thresholds,
creating a narrow coverage band incentive.