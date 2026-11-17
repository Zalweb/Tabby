'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {sourceEnvironment} = require('./azure-full-prepare-export.cjs');
test('export preserves percent-encoded passwords while enforcing verified TLS and read-only connections', () => {
  const secret = 'synthetic:@/#?$password';
  const env = sourceEnvironment('\uFEFFSUPABASE_DB_URL="postgresql://postgres.project:' + encodeURIComponent(secret) + '@aws-0-ap-northeast-2.pooler.supabase.com:5432/postgres?sslmode=disable"');
  assert.equal(env.PGPASSWORD, secret);
  assert.equal(env.PGSSLMODE, 'verify-full');
  assert.equal(env.PGOPTIONS, '-c default_transaction_read_only=on');
});
test('export rejects spoofed hosts, missing credentials and injected environment lines without echoing secrets', () => {
  for (const uri of ['postgres://postgres:synthetic-secret@supabase.attacker.invalid/postgres', 'postgres://postgres@db.project.supabase.co/postgres', 'postgres://postgres:synthetic-secret%0AINJECT=1@db.project.supabase.co/postgres', 'invalid-synthetic-secret', 'postgres://postgres:synthetic-secret@db.project.supabase.co/postgres#fragment']) {
    assert.throws(() => sourceEnvironment('SUPABASE_DB_URL=' + uri), error => !error.message.includes('synthetic-secret'));
  }
});
