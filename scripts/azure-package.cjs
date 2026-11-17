#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const destination = path.join(root, '.dart_tool/azure-workers/package');
// Allowlist only: no .env, mobile artifacts, credentials, tests or SQL.
const files = ['backend/app.mjs', 'backend/server.mjs',
  ...['account-deletion', 'reminder-push', 'recurring-obligations'].map(name => `supabase/functions/${name}/worker.mjs`)];
for (const file of files) {
  const target = path.join(destination, file);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  fs.copyFileSync(path.join(root, file), target);
}
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'backend/package.json'), 'utf8'));
manifest.scripts = {start: 'node backend/server.mjs'};
fs.writeFileSync(path.join(destination, 'package.json'), JSON.stringify(manifest, null, 2) + '\n');
// Refuse stale/unexpected files rather than silently shipping them.
function walk(dir) {
  return fs.readdirSync(dir, {withFileTypes: true}).flatMap(e => e.isDirectory() ? walk(path.join(dir, e.name)) : [path.relative(destination, path.join(dir, e.name)).split(path.sep).join('/')]);
}
const allowed = new Set([...files, 'package.json']);
if (walk(destination).some(file => !allowed.has(file))) throw Error('Unexpected staging file: inspect ignored .dart_tool/azure-workers/package before packaging');
console.log('Prepared credential-free package in .dart_tool/azure-workers/package');
