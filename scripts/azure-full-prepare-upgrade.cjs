#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const {seal} = require('./azure-full-seal.cjs');
const {gzipSync} = require('node:zlib');
const project = 'ziaqrkagsvozhotremsx';
async function main() {
  if (!process.env.SUPABASE_ACCESS_TOKEN) throw Error('Source management authorization is missing.');
  const query = `SELECT json_build_object(
    'history',(SELECT json_agg(t ORDER BY version) FROM (SELECT version,name,statements FROM supabase_migrations.schema_migrations) t),
    'policies',(SELECT coalesce(json_agg(p),'[]') FROM pg_policies p WHERE schemaname IN ('auth','storage')),
    'triggers',(SELECT coalesce(json_agg(t),'[]') FROM (SELECT n.nspname AS schema,c.relname AS table,t.tgname AS name,pg_get_triggerdef(t.oid) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace pn ON pn.oid=p.pronamespace WHERE n.nspname IN ('auth','storage') AND pn.nspname='public' AND NOT t.tgisinternal) t),
    'publications',(SELECT coalesce(json_agg(t),'[]') FROM pg_publication_tables t WHERE pubname='supabase_realtime'),
    'event_triggers',(SELECT coalesce(json_agg(t),'[]') FROM (SELECT e.evtname AS name,e.evtevent AS event,e.evtenabled AS enabled,e.evttags AS tags,e.evtfoid::regprocedure::text AS function FROM pg_event_trigger e JOIN pg_proc p ON p.oid=e.evtfoid JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') t),
    'vault_secret_count',(SELECT count(*) FROM vault.secrets)) AS inventory`;
  const response = await fetch(`https://api.supabase.com/v1/projects/${project}/database/query/read-only`, {
    method: 'POST', headers: {Authorization: `Bearer ${process.env.SUPABASE_ACCESS_TOKEN}`, 'Content-Type': 'application/json'},
    body: JSON.stringify({query}), signal: AbortSignal.timeout(30000),
  });
  if (!response.ok) throw Error(`Read-only inventory request failed (HTTP ${response.status}); details withheld.`);
  const rows = await response.json();
  const inventory = rows[0].inventory;
  fs.writeFileSync('.dart_tool/azure-full/source-upgrade-inventory.json', JSON.stringify(inventory));
  const aliases = {'20260930000001': '20260930161339', '20260930000002': '20260930161351'};
  const applied = new Set(inventory.history.map(row => row.version));
  const all = fs.readdirSync('supabase/migrations').filter(file => /^\d{14}_.+\.sql$/.test(file)).sort();
  const normalize = sql => sql.replace(/--[^\n]*/g, '').replace(/\s+/g, ' ').trim().replace(/;$/, '');
  for (const [local, remote] of Object.entries(aliases)) {
    const row = inventory.history.find(value => value.version === remote);
    const file = all.find(value => value.startsWith(local + '_'));
    if (!row?.statements || !file || normalize(row.statements.join('\n')) !== normalize(fs.readFileSync('supabase/migrations/' + file, 'utf8'))) throw Error('Migration alias SQL differs; manual reconciliation required.');
  }
  const pending = all.filter(file => !applied.has(file.slice(0,14)) && !applied.has(aliases[file.slice(0,14)]));
  if (inventory.history.length !== 18 || pending.length !== 32 || inventory.vault_secret_count !== 0) throw Error('Source drift or Vault secrets require explicit review; no upgrade prepared.');
  const packet = {inventory, aliases, migrations: pending.map(file => ({file, sql: fs.readFileSync('supabase/migrations/' + file, 'utf8')}))};
  const envelope = seal(fs.readFileSync('.dart_tool/azure-full/migration-public.pem'), gzipSync(Buffer.from(JSON.stringify(packet))));
  fs.writeFileSync('.dart_tool/azure-full/upgrade-capsule.json', JSON.stringify(envelope));
  console.log(JSON.stringify({prepared: true, history: inventory.history.length, pending: pending.length, policies: inventory.policies.length, triggers: inventory.triggers.length, event_triggers: inventory.event_triggers.length, vault_secrets: inventory.vault_secret_count, versions: pending.map(file => file.slice(0,14))}));
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
