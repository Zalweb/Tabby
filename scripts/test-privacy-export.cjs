// Local PostgreSQL/WASM authorization evidence, not deployed Supabase evidence.
// Install @electric-sql/pglite in .dart_tool/sql-check, or set TABBY_PGLITE_MODULE.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const {PGlite} = require(process.env.TABBY_PGLITE_MODULE ||
  path.join(root, '.dart_tool/sql-check/node_modules/@electric-sql/pglite'));
(async () => {
  const db = new PGlite();
  try {
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;
      GRANT USAGE ON SCHEMA auth TO authenticated;`);
    const sql = name => fs.readFileSync(path.join(root, 'supabase/migrations', name), 'utf8');
    const snapshot = fs.readFileSync(path.join(root,'supabase/schema_all.sql'),'utf8');
    const core = process.env.TABBY_PRIVACY_SCHEMA === 'snapshot'
      ? snapshot.slice(snapshot.indexOf('-- 1. USERS TABLE'),snapshot.indexOf('-- Supabase Auth Auto-Provisioning'))
      : sql('20260913000001_core_schema.sql');
    await db.exec(core.replace(/^CREATE EXTENSION[^;]+;/gm, ''));
    await db.exec(sql('20261102000001_private_account_export.sql'));
    await db.exec(`CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
      $$ SELECT COALESCE(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;`);
    await db.exec(sql('20261102000002_account_deletion_requests.sql'));
    await db.exec(sql('20261102000003_private_ledger_export_pages.sql'));
    const a = '00000000-0000-4000-8000-000000000001';
    const b = '00000000-0000-4000-8000-000000000002';
    await db.exec(`INSERT INTO public.users(id,display_name,email) VALUES
      ('${a}','Owner A','a@example.invalid'),('${b}','Owner B','b@example.invalid');
      INSERT INTO public.contacts(owner_user_id,display_name) VALUES
      ('${a}','A private contact'),('${b}','B private contact');
      INSERT INTO public.tabs(id,user_a,user_b) VALUES ('00000000-0000-4000-8000-000000000010','${a}','${b}');
      INSERT INTO public.transactions(tab_id,created_by,description,total_amount_centavos,status)
      VALUES ('00000000-0000-4000-8000-000000000010','${a}','Shared history fixture',10000,'acknowledged');`);
    const financialBefore = (await db.query('SELECT to_jsonb(t) AS data FROM public.transactions t')).rows;
    const actor = async id => {
      await db.exec('RESET ROLE');
      await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
      await db.exec('SET ROLE authenticated');
    };
    for (const id of [a,b]) {
      await actor(id);
      const result = (await db.query('SELECT public.export_account_data_v1() AS data')).rows[0].data;
      assert.equal(result.account_id, id);
      assert.equal(result.profile.id, id);
      assert.equal(result.contacts.length, 1);
      assert.equal(result.contacts[0].display_name, id === a ? 'A private contact' : 'B private contact');
      assert.equal(result.scope, 'profile_and_owned_contacts');
      assert.ok(result.excluded.includes('shared_ledger'));
      assert.equal(result.profile.gcash_number, undefined);
    }
    await actor(a);
    const request = async () => (await db.query('SELECT public.request_account_deletion_v1() AS data')).rows[0].data;
    for (const claims of [{}, {amr: [{method: 'password', timestamp: 1}]},
      {amr: [{method: 'anonymous', timestamp: Math.floor(Date.now()/1000)}]},
      {amr: [{method: 'password', timestamp: 'bad'}]},
      {amr: [{method: 'password', timestamp: Math.floor(Date.now()/1000)+3600}]}]) {
      await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify(claims)]);
      await assert.rejects(request, e => e.code === '42501');
    }
    await db.query("SELECT set_config('request.jwt.claims',$1,false)", [JSON.stringify({
      amr: [{method: 'password', timestamp: Math.floor(Date.now()/1000)}]})]);
    const first = await request();
    assert.equal(first.status, 'requested');
    assert.deepEqual(await request(), first);
    assert.deepEqual((await db.query('SELECT public.get_account_deletion_request_v1() AS data')).rows[0].data, first);
    await assert.rejects(db.query('DELETE FROM public.account_deletion_requests'), e => e.code === '42501');
    await actor(b);
    assert.equal((await db.query('SELECT public.get_account_deletion_request_v1() AS data')).rows[0].data, null);
    assert.equal((await db.query('SELECT * FROM public.account_deletion_requests')).rows.length, 0);
    await db.exec('RESET ROLE');
    assert.equal((await db.query('SELECT count(*)::int AS n FROM public.users')).rows[0].n, 2);
    assert.equal((await db.query('SELECT count(*)::int AS n FROM public.contacts')).rows[0].n, 2);
    assert.deepEqual((await db.query('SELECT to_jsonb(t) AS data FROM public.transactions t')).rows, financialBefore);
    const c = '00000000-0000-4000-8000-000000000003';
    const shared = '00000000-0000-4000-8000-000000000010';
    const unrelated = '00000000-0000-4000-8000-000000000011';
    await db.exec(`INSERT INTO public.users(id,display_name) VALUES ('${c}','Other account');
      INSERT INTO public.tabs(id,user_a,user_b) VALUES ('${unrelated}','${b}','${c}');
      INSERT INTO public.transactions(id,tab_id,created_by,description,total_amount_centavos,status)
        SELECT ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
          '${shared}','${a}','Page fixture '||i,101,'acknowledged' FROM generate_series(1,103) i;
      INSERT INTO public.transactions(id,tab_id,created_by,description,total_amount_centavos)
        VALUES ('20000000-0000-4000-8000-000000000001','${unrelated}','${b}','Unrelated secret',9900);
      INSERT INTO public.transaction_participants(transaction_id,user_id,share_amount_centavos)
        VALUES ('10000000-0000-4000-8000-000000000001','${a}',51),
        ('20000000-0000-4000-8000-000000000001','${c}',4950);
      INSERT INTO public.payments(tab_id,submitted_by,recipient_user_id,amount_centavos)
        VALUES ('${shared}','${a}','${b}',50),('${unrelated}','${b}','${c}',90);`);
    const page = async (section, after = null, limit = 50) => (await db.query(
      'SELECT public.export_ledger_page_v1($1,$2,$3) AS data',[section,after,limit])).rows[0].data;
    await actor(a);
    const seen = new Set();
    let cursor = null, pages = 0;
    do {
      const result = await page('expenses',cursor,7);
      assert.equal(result.account_id, a);
      assert.equal(result.section, 'expenses');
      assert.ok(result.records.length <= 7);
      for (const row of result.records) {
        assert.equal(row.tab_id, shared);
        assert.equal(row.status, 'acknowledged');
        assert.equal(row.receipt_url, undefined);
        assert.ok(!seen.has(row.id)); seen.add(row.id);
        assert.ok(cursor === null || row.id > cursor);
      }
      cursor = result.next_cursor;
      if (cursor) assert.equal(cursor, result.records.at(-1).id);
      assert.ok(++pages < 30);
    } while (cursor);
    assert.equal(seen.size,104);
    for (const section of ['tabs','shares','payments']) {
      const result = await page(section);
      assert.equal(result.records.length,1);
      assert.equal(result.next_cursor,null);
    }
    for (const [section,limit] of [['bad',50],['expenses',0],['expenses',101],['expenses',null]]) {
      await assert.rejects(page(section,null,limit), e => e.code === '22023');
    }
    const empty = await page('expenses','ffffffff-ffff-ffff-ffff-ffffffffffff');
    assert.equal(empty.records.length,0); assert.equal(empty.next_cursor,null);
    await actor(c);
    assert.equal((await page('expenses')).records[0].description,'Unrelated secret');
    assert.equal((await page('expenses')).records.length,1);
    await actor('00000000-0000-4000-8000-000000000004');
    for (const section of ['tabs','expenses','shares','payments']) {
      assert.deepEqual((await page(section)).records,[]);
    }
    await actor('');
    await assert.rejects(db.query('SELECT public.export_account_data_v1()'), e => e.code === '42501');
    await db.exec('RESET ROLE; SET ROLE anon');
    await assert.rejects(db.query('SELECT public.export_account_data_v1()'), e => e.code === '42501');
    await assert.rejects(request, e => e.code === '42501');
    await assert.rejects(page('expenses'), e => e.code === '42501');
    await assert.rejects(db.query('SELECT public.get_account_deletion_request_v1()'), e => e.code === '42501');
    console.log('PRIVACY_EXPORT_OK: owner isolation, allowlist, anonymous denial; deletion recent-auth/replay/status/preservation; bounded keyset ledger pages and unrelated-tab denial');
  } finally { await db.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
