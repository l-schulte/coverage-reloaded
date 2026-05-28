# Cypress Coverage Config Patcher

Tools for discovering Cypress config files across git history and patching
them at runtime to enable code coverage collection with `@cypress/code-coverage`.

## Workflow Overview

```
1. DISCOVER  →  helper/cypress/discover-cypress-configs.sh <repo>
2. PATCH ──  →  manually create coverage-enabled patches
3. APPLY   →  helper/cypress/cypress-patcher.sh <repo> <mapper> <patches>
```

---

## Step 1: Discover — Extract originals and build mapper

Scan a git repository for all files relevant to Cypress coverage configuration
(cypress configs, support files, plugins, vite configs, .nycrc files, etc.).

```bash
./helper/cypress/discover-cypress-configs.sh projects/my-project/repo
```

This creates a `cypress-coverage-configs/` directory next to the repo:

```
projects/my-project/
├── cypress-coverage-configs/
│   ├── originals/          — file contents at their introducing commits
│   ├── patches/            — place your patches here (empty initially)
│   └── mapper.tsv          — sha256  →  repo_path  mapping
└── repo/                   — the git repository
```

**mapper.tsv** format (tab-separated, no header line to skip):

```
sha256_original<tab>repo_path
a7c99388...  packages/vuetify/cypress.config.ts
96126686...  packages/kitchen/cypress.json
```

Each row represents one unique file version at its introducing commit.
The SHA256 allows the patcher to verify that the checked-out file at
runtime matches what was extracted.

---

## Step 2: Patch — Create coverage-enabled file versions

For each original file that needs coverage support, create a `.patch` file
in the `patches/` directory.

### Naming convention

```
{sha256_of_original}__{basename}.patch
```

The SHA256 prefix is required for matching — the basename is for human
readability. Examples:

```
a7c99388c4922f27474d576355d99701604462cbf724231ab444c058eaa951d2__cypress.config.ts.patch
96126686650a6b3bc2375095e92a00cc4d68f053d9e71a4a969f903084f0e22f__cypress.json.patch
```

### What each patch should add

**For cypress.config.ts / cypress.config.js (Cypress 10+):**

Add a `setupNodeEvents` function that registers the coverage task, and
set `env.coverage = true`.

```js
import { defineConfig } from 'cypress'

export default defineConfig({
  component: {
    devServer: { /* existing config */ },
    setupNodeEvents(on, config) {
      require('@cypress/code-coverage/task')(on, config)
      return config
    },
  },
  env: {
    coverage: true,
  },
})
```

**For cypress.json (pre-Cypress 10):**

Add `env.coverage = true`.

```json
{
  "component": {
    "componentFolder": "./src",
    "testFiles": "**/*cy.spec.{js,jsx,ts,tsx}",
    "video": false
  },
  "env": {
    "coverage": true
  }
}
```

**For cypress/plugins/index.js (pre-Cypress 10 plugin file):**

Register the coverage task alongside existing plugins.

```js
module.exports = (on, config) => {
  // existing plugin setup...
  require('@cypress/code-coverage/task')(on, config)
  return config
}
```

**For cypress/support/index.js or index.ts:**

Import the coverage support module.

```js
import '@cypress/code-coverage/support'
```

---

## Step 3: Apply — Patch files at runtime

In the Docker container, after the target commit is checked out, run:

```bash
./helper/cypress/cypress-patcher.sh \
  /coverage_reloaded/repo \
  /coverage_reloaded/cypress-coverage-configs/mapper.tsv \
  /coverage_reloaded/cypress-coverage-configs/patches
```

The patcher:
1. Reads `mapper.tsv` to get expected SHA256 hashes for each file
2. For each entry, checks if the file exists at the checked-out commit
3. Verifies the file's content hash matches the expected one
4. If matched, looks up `{sha256}__*.patch` in the patches directory
5. Replaces the original file with the coverage-enabled version

Files that don't exist at the checked-out commit (e.g., kitchen package
from 2019) or have non-matching hashes are silently skipped.

### Integration in install-and-run.sh

Add this call before the test execution step:

```bash
# Apply Cypress coverage patches
bash "$SCRIPT_DIR/helper/cypress/cypress-patcher.sh" \
  "$REPO_DIR" \
  "$CONFIG_DIR/mapper.tsv" \
  "$CONFIG_DIR/patches"
```

---

## Adding patches for a new project

1. Run `discover-cypress-configs.sh` against the project's repo
2. Look at the generated `mapper.tsv` — each row identifies a unique file
3. For each file that needs a coverage patch (typically: cypress configs,
   support files, plugins), read its content from the `originals/` directory
4. Create a modified version with coverage support added
5. Save it as `{sha256}__{basename}.patch` in the `patches/` directory
6. Only files with matching hashes will be patched at runtime — files that
   evolved differently in the actual project history are safely skipped
