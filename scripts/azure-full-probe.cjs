#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
async function main() {
  const origin = new URL(process.argv[2]);
  if (origin.protocol !== 'https:' || origin.username || origin.password) throw Error('An HTTPS backend origin is required.');
  const config = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
  if (!config.anonKey) throw Error('Destination client key is required. Never use a service key.');
  const payload = JSON.parse(Buffer.from(config.anonKey.split('.')[1], 'base64url'));
  if (payload.role !== 'anon') throw Error('Only the destination anon client key is accepted.');
  const report = {timestamp: new Date().toISOString(), origin: origin.origin, checks: [],
    data_migration: 'not assessed by this probe', limitation: 'Platform probes do not verify restored accounts, financial RPCs, Storage ownership or device acceptance.'};
  const check = async (name, route, expected, withKey, inspect) => {
    const response = await fetch(new URL(route, origin), {signal: AbortSignal.timeout(20000),
      headers: withKey ? {apikey: config.anonKey, Authorization: `Bearer ${config.anonKey}`} : {}});
    const body = await response.text();
    let success = response.status === expected;
    if (inspect && success) success = inspect(JSON.parse(body));
    report.checks.push({name, status: response.status, outcome: success ? 'passed' : 'failed'});
  };
  await check('TLS and Auth health with client key', '/auth/v1/health', 200, true);
  await check('Auth signup disabled during migration', '/auth/v1/settings', 200, true, body => body.disable_signup === true);
  await check('Requests without API key denied', '/rest/v1/__tabby_missing_table__', 401, false);
  await check('Client key reaches PostgREST', '/rest/v1/__tabby_missing_table__', 404, true, body => body.code === 'PGRST205');
  await check('OpenAPI protected from client roles', '/rest/v1/', 403, true);
  await check('Admin dashboard requires authentication', '/', 401, false);
  console.log(JSON.stringify(report, null, 2));
  if (report.checks.some(item => item.outcome !== 'passed')) process.exitCode = 1;
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
