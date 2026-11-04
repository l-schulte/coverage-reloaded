'use strict';

const fs = require('fs');
const path = require('path');

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeJson(p, obj) {
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

const SKIP_DIRS = ['node_modules', '.git', 'dist', '.nyc_output', 'coverage'];

function walk(dir, fileList) {
  let entries;
  try {
    entries = fs.readdirSync(dir);
  } catch (e) {
    return;
  }
  for (const entry of entries) {
    if (SKIP_DIRS.includes(entry)) continue;
    const full = path.join(dir, entry);
    let st;
    try {
      st = fs.statSync(full);
    } catch (e) {
      continue;
    }
    if (st.isDirectory()) {
      const pkgPath = path.join(full, 'package.json');
      if (fs.existsSync(pkgPath)) {
        fileList.push(pkgPath);
      }
      walk(full, fileList);
    }
  }
}

const allPkgFiles = [];
walk('.', allPkgFiles);

for (const pkgFile of allPkgFiles) {
  let pkg;
  try {
    pkg = readJson(pkgFile);
  } catch (e) {
    continue;
  }
  if (!pkg.scripts) continue;

  const pkgDir = path.dirname(pkgFile);
  if (pkgDir.includes('compass-e2e-tests')) {
    if (pkg.scripts['test']) {
      pkg.scripts['test'] = 'node -e "console.log(\'skipping e2e\'); process.exit(0)" --';
    }
    if (pkg.scripts['test-ci']) {
      pkg.scripts['test-ci'] = 'node -e "console.log(\'skipping e2e\'); process.exit(0)" --';
    }
    writeJson(pkgFile, pkg);
    continue;
  }

  let modified = false;

  // Neutralize electron-only smoke test scripts that cannot produce coverage (see OVERVIEW.md)
  for (const sName of ['test:electron', 'test-electron', 'test-ci-electron']) {
    if (pkg.scripts[sName]) {
      pkg.scripts[sName] = 'node -e "console.log(\'skipping electron smoke suite\'); process.exit(0)" --';
      modified = true;
    }
  }

  // In workspace subpackages, neutralize "prepare" so npm 8 cannot fire it out-of-order during npm install.
  // Alias it to "bootstrap" (and "compile") so Lerna can build all packages topologically afterwards.
  if (pkgDir !== '.' && pkg.scripts['prepare']) {
    if (!pkg.scripts['bootstrap']) {
      pkg.scripts['bootstrap'] = pkg.scripts['prepare'];
    }
    if (!pkg.scripts['compile']) {
      pkg.scripts['compile'] = pkg.scripts['prepare'];
    }
    delete pkg.scripts['prepare'];
    modified = true;
  }

  // Ensure hadron-react-components is treated as external by Webpack in compass-import-export
  if (pkg.name === '@mongodb-js/compass-import-export') {
    if (pkg.devDependencies && pkg.devDependencies['hadron-react-components']) {
      if (!pkg.peerDependencies) pkg.peerDependencies = {};
      if (!pkg.peerDependencies['hadron-react-components']) {
        pkg.peerDependencies['hadron-react-components'] = pkg.devDependencies['hadron-react-components'];
        modified = true;
      }
    }
  }

  // Strip chained electron and karma test runs
  for (const [sName, sCmd] of Object.entries(pkg.scripts)) {
    if (typeof sCmd !== 'string') continue;
    let updatedCmd = sCmd;
    if (/\s*&&\s*npm run (test:electron|test-electron|test:karma|test-karma)\b/.test(updatedCmd)) {
      updatedCmd = updatedCmd.replace(/\s*&&\s*npm run (test:electron|test-electron|test:karma|test-karma)\b/, '');
    }
    if (pkgDir.endsWith('packages/compass') && sName === 'test-ci' && updatedCmd.includes('npm run test-release-tasks && npm run test')) {
      updatedCmd = updatedCmd.replace(' && npm run test', '');
    }
    // The mongodb-compass root `test-ci` chains a RAW `&& xvfb-maybe electron-mocha …`
    // instead of `&& npm run test:electron`, so the rule above misses it. The Chromium
    // half then aborts the script on the missing electron binary (the binary is never
    // downloaded, and Electron runs cannot yield line coverage anyway). Strip only that
    // trailing segment so the preceding `nyc … npm run test-release-tasks` still measures
    // the package — this is what produced the 93.87% table before the crash.
    if (/\s*&&\s*(?:xvfb-maybe\s+)?electron-mocha\b/.test(updatedCmd)) {
      updatedCmd = updatedCmd.replace(/\s*&&\s*(?:xvfb-maybe\s+)?electron-mocha\b[^&]*$/, '').trim();
    }
    // If a package test script ONLY runs electron-mocha without node unit tests, neutralize it
    if ((sName === 'test' || sName === 'test-ci') && /^\s*(xvfb-maybe\s+)?electron-mocha\b/.test(updatedCmd)) {
      updatedCmd = 'node -e "console.log(\'skipping standalone electron smoke suite\'); process.exit(0)" --';
    }
    // Handle hadron-build test (which wraps electron-mocha)
    if ((sName === 'test' || sName === 'test-ci') && /(?:^|\s)(?:xvfb-maybe\s+)?hadron-build\s+test\b/.test(updatedCmd)) {
      if (fs.existsSync(path.join(pkgDir, 'test/enzyme/_setup.js'))) {
        updatedCmd = 'mocha -r ./test/enzyme/_setup.js "./test/enzyme/**/*.test.js"';
      } else {
        updatedCmd = 'node -e "console.log(\'skipping standalone electron smoke suite\'); process.exit(0)" --';
      }
    }
    if (updatedCmd !== sCmd) {
      pkg.scripts[sName] = updatedCmd;
      modified = true;
    }
  }

  for (const [sName, sCmd] of Object.entries(pkg.scripts)) {
    if (typeof sCmd !== 'string') continue;

    // electron-rebuild targets the Electron ABI, which is irrelevant to Node unit
    // tests; when it runs it fails the gyp build for kerberos/keytar and aborts the
    // whole install. Previously only naked `postinstall` was neutralized, so eras
    // that chain it from another script (e.g. mongodb-compass) still broke.
    if (sCmd.includes('electron-rebuild')) {
      pkg.scripts[sName] = 'node -e "console.log(\'skipping electron-rebuild\')" --';
      modified = true;
      continue;
    }

    if (sCmd.includes('download-csfle') || sCmd.includes('download-akzidenz')) {
      let cleaned = sCmd
        .replace(/node\s+(?:\.\.\/\.\.\/)?scripts\/download-(?:akzidenz|csfle)\.js(?:\s+--[a-z-]+)?\s*&&\s*/g, '')
        .replace(/\s*&&\s*node\s+(?:\.\.\/\.\.\/)?scripts\/download-(?:akzidenz|csfle)\.js(?:\s+--[a-z-]+)?/g, '');
      if (cleaned === sCmd || cleaned.trim() === '') {
        cleaned = 'node -e "console.log(\'skipping external asset download\')" --';
      }
      pkg.scripts[sName] = cleaned;
      modified = true;
    }

    const isOldMocha = /^[~^]?[1-5]\./.test((pkg.devDependencies && pkg.devDependencies.mocha) || (pkg.dependencies && pkg.dependencies.mocha) || '');

    if (/(^|[\s/])(electron-)?mocha(?:\.js)?(\s|$)/.test(pkg.scripts[sName]) && !pkg.scripts[sName].includes('mocha-webpack') && !pkg.scripts[sName].startsWith('node -e')) {
      let updatedCmd = pkg.scripts[sName];
      if (!isOldMocha) {
        if (!updatedCmd.includes('--no-bail') && !updatedCmd.includes('-b')) {
          updatedCmd += ' --no-bail';
        }
        if (!updatedCmd.includes('--exit')) {
          updatedCmd += ' --exit';
        }
      }
      if (updatedCmd !== pkg.scripts[sName]) {
        pkg.scripts[sName] = updatedCmd;
        modified = true;
      }
    }

    if (/\bjest\b/.test(sCmd)) {
      if (!sCmd.includes('--forceExit')) {
        pkg.scripts[sName] = sCmd + ' --forceExit';
        modified = true;
      }
    }

    if (typeof sCmd === 'string' && sCmd.includes('nyc') && !sCmd.includes('reporter=lcov')) {
      pkg.scripts[sName] = sCmd.replace(/\bnyc\b/, 'nyc --reporter=lcov --reporter=text');
      modified = true;
    }

    if (sCmd.includes('--bail')) {
      pkg.scripts[sName] = pkg.scripts[sName].replace(/--bail/g, isOldMocha ? '' : '--no-bail');
      modified = true;
    }
  }

  if (pkg.scripts['test'] && !pkg.scripts['test-cov'] && !pkg.scripts['test-ci']) {
    pkg.scripts['test-cov'] = 'nyc --reporter=lcov --reporter=text npm run test';
    pkg.scripts['test-ci'] = 'npm run test-cov';
    modified = true;
  } else if (pkg.scripts['test'] && pkg.scripts['test-ci'] && !pkg.scripts['test-ci'].includes('test-cov') && !pkg.scripts['test-ci'].includes('nyc')) {
    pkg.scripts['test-ci'] = 'nyc --reporter=lcov --reporter=text ' + pkg.scripts['test-ci'];
    modified = true;
  }

  // Packages that start a mongodb-runner share port 27018 in the 2021-05..2023-05
  // era. npm only runs `posttest` when `test` exits 0, so a failing suite leaves its
  // mongod running and the NEXT package's `pretest` dies with mongod exit code 48
  // ("address already in use"); its DB-touching hooks then time out and the suite
  // reports MongoTopologyClosedError. With lerna --concurrency 1 no sibling test is
  // ever running, so clearing stray mongod/mongos processes immediately before
  // starting a runner is safe. Upstream shipped scripts/killall-mongo.js for exactly
  // this purpose; it is absent after 2023-05 because upstream then gave every package
  // its own runner port (no collision possible), so this guard is inert there.
  const killallPath = path.resolve('scripts/killall-mongo.js');
  if (fs.existsSync(killallPath)) {
    const relKillall = path.relative(path.resolve(pkgDir), killallPath);
    for (const [sName, sCmd] of Object.entries(pkg.scripts || {})) {
      if (typeof sCmd !== 'string') continue;
      if (!/^(pre)?test(-|$)/.test(sName) && !/^start/.test(sName)) continue;
      if (!/mongodb-runner\b[\s\S]*\bstart\b/.test(sCmd)) continue;
      if (sCmd.includes('killall-mongo')) continue;
      pkg.scripts[sName] = `node ${relKillall} && ${sCmd}`;
      modified = true;
    }
  }

  // A package-level .nycrc that disables instrumentation is only valid while the
  // suite is bundled by mocha-webpack (babel-plugin-istanbul instruments at build
  // time). Once the package runs plain mocha + ts-node, nyc must instrument the
  // sources itself, otherwise it reports "All files | 0 | 0 | 0 | 0" and emits no
  // lcov at all. compass-crud moved to plain mocha in 2022-07 and then produced
  // zero coverage for 2,516 consecutive runs despite running 500+ passing tests.
  // Conditioned on the test scripts (not on dates), so the mocha-webpack era keeps
  // its working configuration.
  const nycrcPath = path.join(pkgDir, '.nycrc');
  if (fs.existsSync(nycrcPath)) {
    try {
      const nycrc = readJson(nycrcPath);
      const usesWebpackBundling = Object.values(pkg.scripts || {}).some(
        (s) => typeof s === 'string' && s.includes('mocha-webpack')
      );
      if (nycrc.instrument === false && !usesWebpackBundling) {
        nycrc.instrument = true;
        const ext = new Set(Array.isArray(nycrc.extension) ? nycrc.extension : ['.js']);
        ext.add('.js');
        ext.add('.ts');
        ext.add('.tsx');
        nycrc.extension = [...ext];
        const reporters = new Set(Array.isArray(nycrc.reporter) ? nycrc.reporter : []);
        reporters.add('lcov');
        reporters.add('text');
        reporters.add('html');
        nycrc.reporter = [...reporters];
        writeJson(nycrcPath, nycrc);
        modified = true;
      }
    } catch (e) {
      console.error(`WARN: could not repair ${nycrcPath}: ${e.message}`);
    }
  }

  if (modified) {
    writeJson(pkgFile, pkg);
  }
}

if (fs.existsSync('lerna.json')) {
  try {
    const lerna = readJson('lerna.json');
    lerna.concurrency = 1;
    if (!lerna.command) lerna.command = {};
    if (!lerna.command.run) lerna.command.run = {};
    if (!lerna.command.exec) lerna.command.exec = {};
    lerna.command.run.bail = false;
    lerna.command.run.concurrency = 1;
    lerna.command.exec.bail = false;
    lerna.command.exec.concurrency = 1;
    lerna.useNx = false;
    writeJson('lerna.json', lerna);
  } catch (e) {}
}

if (fs.existsSync('package.json')) {
  try {
    const rootPkg = readJson('package.json');
    if (rootPkg.scripts) {
      if (!rootPkg.scripts['test-ci']) {
        if (rootPkg.scripts['test-evergreen'] && rootPkg.scripts['test-evergreen'].includes('lerna run test-ci')) {
          rootPkg.scripts['test-ci'] = rootPkg.scripts['test-evergreen'];
        } else if (rootPkg.scripts['test'] && rootPkg.scripts['test'].includes('lerna run test')) {
          rootPkg.scripts['test-ci'] = rootPkg.scripts['test'].replace(/\blerna run test\b/, 'lerna run test-ci');
        }
      }
      for (const [k, v] of Object.entries(rootPkg.scripts)) {
        if (typeof v === 'string' && v.includes('lerna run')) {
          let updated = v;
          if (!updated.includes('--no-bail')) {
            updated += ' --no-bail';
          }
          if (!updated.includes('--stream')) {
            updated += ' --stream';
          }
          rootPkg.scripts[k] = updated;
        }
      }
      writeJson('package.json', rootPkg);
    }
  } catch (e) {}
}
