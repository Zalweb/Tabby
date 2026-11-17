#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {seal} = require('./azure-full-seal.cjs');
const {createHash} = require('node:crypto');
async function pinnedDownload(file, url, expected) {
  let bytes = fs.existsSync(file) ? fs.readFileSync(file) : null;
  if (!bytes) {
    const response = await fetch(url, {signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw Error('Public migration dependency download failed.');
    bytes = Buffer.from(await response.arrayBuffer());
  }
  if (createHash('sha256').update(bytes).digest('hex') !== expected) throw Error('Public migration dependency integrity failed.');
  fs.mkdirSync(path.dirname(file), {recursive: true});
  fs.writeFileSync(file, bytes);
}
function sourceEnvironment(input) {
  const line = input.replace(/^\uFEFF/, '').split(/\r?\n/).find(value => /^SUPABASE_DB_URL\s*=/.test(value));
  if (!line) throw Error('Private connection field is missing.');
  let url;
  try { url = new URL(line.slice(line.indexOf('=') + 1).trim().replace(/^(['"])(.*)\1$/, '$2')); }
  catch { throw Error('Private connection URL is invalid; value withheld.'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.password || url.hash || !/^(?:db\.[a-z0-9]+\.supabase\.co|[a-z0-9-]+\.pooler\.supabase\.com)$/.test(url.hostname)) throw Error('Private source connection needs correction.');
  const env = {PGHOST: url.hostname, PGPORT: url.port || '5432', PGUSER: decodeURIComponent(url.username),
    PGPASSWORD: decodeURIComponent(url.password), PGDATABASE: decodeURIComponent(url.pathname.slice(1)) || 'postgres',
    PGSSLMODE: 'verify-full', PGSSLROOTCERT: '/tmp/tabby-source-ca.crt', PGCONNECT_TIMEOUT: '20',
    PGOPTIONS: '-c default_transaction_read_only=on', PGTZ: 'UTC', PGAPPNAME: 'tabby-migration-export'};
  if (Object.values(env).some(value => /[\r\n\0]/.test(value))) throw Error('Connection contains unsupported control characters.');
  return env;
}
async function main() {
  const folder = path.resolve('.dart_tool/azure-full');
  const env = sourceEnvironment(fs.readFileSync('.env.azure-migration', 'utf8'));
  const base = 'https://raw.githubusercontent.com/supabase/cli/v3.1.0/apps/cli/src/command-internal/';
  await Promise.all([
    pinnedDownload(path.join(folder, 'cli-dump-source/pg-dump.scripts.ts'), base + 'pg-dump.scripts.ts', '82d053abc29361b38cf6a34985842018ca82156dc88d3f1bfd3e04c59406d006'),
    pinnedDownload(path.join(folder, 'cli-dump-source/pg-dump.env.ts'), base + 'pg-dump.env.ts', 'dd43832b695c7e065b1d5c028df9cae1251a5be3daf4404c1528587f3904732b'),
  ]);
  if (!fs.existsSync(path.join(folder, 'source-ca.crt'))) {
    const response = await fetch('https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt', {signal: AbortSignal.timeout(30000)});
    if (!response.ok) throw Error('Official source CA download failed.');
    const pem = await response.text();
    fs.writeFileSync(path.join(folder, 'source-ca.crt'), pem);
  }
  const definitions = await import(pathToFileURL(path.join(folder, 'cli-dump-source/pg-dump.scripts.ts')).href);
  const lists = await import(pathToFileURL(path.join(folder, 'cli-dump-source/pg-dump.env.ts')).href);
  const runId = 'run-' + new Date().toISOString().replace(/[-:.]/g, '').replace('Z', 'z');
  const sourceCa = fs.readFileSync(path.join(folder, 'source-ca.crt'), 'utf8');
  const certificate = new (require('node:crypto').X509Certificate)(sourceCa);
  // Official Studio download: hooks/custom-content/custom-content.json, prod SSL CA.
  if (certificate.fingerprint256 !== '80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA') throw Error('Source CA requires fingerprint review.');
  const packet = {run_id: runId, cli_version: '3.1.0', env, source_ca: sourceCa,
    scripts: {schema: definitions.dumpSchemaScript, data: definitions.dumpDataScript, roles: definitions.dumpRoleScript},
    options: {schema: {EXCLUDED_SCHEMAS: lists.INTERNAL_SCHEMAS.join('|'), EXTRA_SED: '/^--/d'},
      data: {EXCLUDED_SCHEMAS: lists.EXCLUDED_SCHEMAS.join('|'), INCLUDED_SCHEMAS: '*'},
      roles: {RESERVED_ROLES: lists.RESERVED_ROLES.join('|'), ALLOWED_CONFIGS: lists.ALLOWED_CONFIGS.join('|'), EXTRA_SED: '/^--/d'}}};
  const envelope = seal(fs.readFileSync(path.join(folder, 'migration-public.pem')), Buffer.from(JSON.stringify(packet)));
  const python = fs.readFileSync('deploy/azure-full/export-source.py').toString('base64');
  const capsule = Buffer.from(JSON.stringify(envelope)).toString('base64');
  const script = `#!/bin/bash\nset -euo pipefail\numask 077\ninstall -d -m 0700 /srv/tabby/migration\n` +
    `python3 -c 'import cryptography' >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq python3-cryptography)\n` +
    `printf '%s' '${python}' | base64 -d > /srv/tabby/migration/export-source.py\n` +
    `printf '%s' '${capsule}' | base64 -d > /srv/tabby/migration/export-capsule.json\n` +
    `python3 /srv/tabby/migration/export-source.py\n`;
  fs.writeFileSync(path.join(folder, 'run-source-export.sh'), script);
  console.log(JSON.stringify({prepared: true, run_id: runId, credentials: 'encrypted capsule only', tls: 'verify-full', source: 'read-only exported snapshot'}));
}
module.exports = {sourceEnvironment};
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
