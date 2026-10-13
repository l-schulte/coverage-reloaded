#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function patchPackageJson(filePath) {
  if (!fs.existsSync(filePath)) return;

  let pkg;
  try {
    pkg = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (e) {
    console.error(`[allow-prerelease-deps] Failed to parse ${filePath}:`, e.message);
    return;
  }

  let modified = false;
  for (const depType of ['dependencies', 'devDependencies', 'peerDependencies', 'optionalDependencies']) {
    if (!pkg[depType]) continue;
    for (const [name, range] of Object.entries(pkg[depType])) {
      if (typeof range !== 'string') continue;
      // Target @serverless companion packages with range prefixes (^ or ~)
      // e.g. "^6.0.0" -> "^6.0.0-0", "~6.1.0" -> "~6.1.0-0"
      if (name.startsWith('@serverless/')) {
        const match = range.match(/^(\^|~)(\d+\.\d+\.\d+)$/);
        if (match) {
          const prefix = match[1];
          const version = match[2];
          const newRange = `${prefix}${version}-0`;
          pkg[depType][name] = newRange;
          console.log(`[allow-prerelease-deps] Patched ${name}: ${range} -> ${newRange} in ${path.relative(process.cwd(), filePath)}`);
          modified = true;
        }
      }
    }
  }

  if (modified) {
    fs.writeFileSync(filePath, JSON.stringify(pkg, null, 2) + '\n');
  }
}

// 1. Patch root package.json
const rootPkgPath = path.resolve(process.cwd(), 'package.json');
patchPackageJson(rootPkgPath);

// 2. Patch workspace packages if any exist
if (fs.existsSync(rootPkgPath)) {
  try {
    const rootPkg = JSON.parse(fs.readFileSync(rootPkgPath, 'utf8'));
    if (rootPkg.workspaces) {
      const workspaces = Array.isArray(rootPkg.workspaces) ? rootPkg.workspaces : (rootPkg.workspaces.packages || []);
      for (const pattern of workspaces) {
        const baseDir = pattern.replace(/\/\*$/, '');
        const fullBaseDir = path.resolve(process.cwd(), baseDir);
        if (fs.existsSync(fullBaseDir)) {
          const entries = fs.readdirSync(fullBaseDir, { withFileTypes: true });
          for (const entry of entries) {
            if (entry.isDirectory()) {
              patchPackageJson(path.join(fullBaseDir, entry.name, 'package.json'));
            }
          }
        }
      }
    }
  } catch (e) {
    // Ignore workspace parsing errors
  }
}
