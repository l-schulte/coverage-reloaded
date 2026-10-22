#!/usr/bin/env node
'use strict';

// Adds `command: ["--innodb-use-native-aio=0"]` to every mysql/mariadb service in
// the given docker-compose files so InnoDB uses simulated AIO and never calls
// io_setup(). Without it, each instance reserves ~17 400 events of the host-wide
// fs.aio-max-nr budget, which a few concurrent containers (or a large shared
// host) exhaust -> the engine aborts at boot with EAGAIN.
//
// The option is valid in every engine version in the study range (MySQL 5.7-8.4,
// MariaDB 10.3-11.6) and the official image entrypoints prepend the server binary
// when the first argument starts with '-' (`set -- mysqld "$@"` /
// `set -- mariadbd "$@"`).
//
// Usage: node disable-innodb-native-aio.js <compose-file> [<compose-file> ...]
//
// Uses js-yaml (installed under /opt/aio-patch). Idempotent.

const fs = require('fs');
const yaml = require('js-yaml');

const FLAG = '--innodb-use-native-aio=0';
const files = process.argv.slice(2);
if (files.length === 0) {
  console.error('[ERR] disable-innodb-native-aio: no compose files given');
  process.exit(1);
}

const isDb = image => typeof image === 'string' && /mysql|mariadb/i.test(image);
const commandHasFlag = command => {
  if (Array.isArray(command)) return command.some(arg => /innodb-use-native-aio/.test(String(arg)));
  if (typeof command === 'string') return /innodb-use-native-aio/.test(command);
  return false;
};

let injected = 0;
let already = 0;
let skipped = 0;
let dbServices = 0;

for (const file of files) {
  const doc = yaml.load(fs.readFileSync(file, 'utf8'));
  if (!doc || typeof doc !== 'object' || !doc.services || typeof doc.services !== 'object') {
    continue;
  }
  let changed = false;
  for (const [name, svc] of Object.entries(doc.services)) {
    if (!svc || typeof svc !== 'object' || !isDb(svc.image)) continue;
    dbServices++;
    if (svc.command === undefined) {
      svc.command = [FLAG];
      injected++;
      changed = true;
    } else if (commandHasFlag(svc.command)) {
      already++;
    } else {
      skipped++;
      console.error(`[NFO] NOTICE: service '${name}' in ${file} already defines a different 'command:'; native AIO left enabled there`);
    }
  }
  if (changed) fs.writeFileSync(file, yaml.dump(doc, { lineWidth: -1, noRefs: true }));
}

console.log(`[NFO] InnoDB native AIO disabled: ${files.length} compose file(s), ${dbServices} mysql/mariadb service(s), ${injected} command(s) added, ${already} already present, ${skipped} skipped`);
