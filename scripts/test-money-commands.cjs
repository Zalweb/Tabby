// Local PostgreSQL/WASM contract tests; not deployed Supabase or multi-session
// concurrency evidence. Install test tooling outside the app manifest:
// npm install --prefix .dart_tool/sql-check --no-save @electric-sql/pglite@0.5.14
// node scripts/test-money-commands.cjs
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const migration = name => read('supabase/migrations/' + name);
const A='00000000-0000-4000-8000-000000000001';
const B='00000000-0000-4000-8000-000000000002';
const C='00000000-0000-4000-8000-000000000003';
const TAB='00000000-0000-4000-8000-000000000010';
const OP='00000000-0000-4000-8000-000000000020';
const PAY='00000000-0000-4000-8000-000000000021';
async function runMoneyContract(db, {native = false} = {}) {
  console.log((await db.query('SELECT version()')).rows[0].version);
  // Supabase's JWT subject boundary is injected; public financial tables,
  // allocation validation, balance helpers and write RPCs are real source SQL.
  await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    GRANT USAGE ON SCHEMA auth TO anon, authenticated;
    CREATE SCHEMA storage;
    CREATE TABLE storage.buckets(id text PRIMARY KEY,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql IMMUTABLE AS
      $$ SELECT string_to_array($1,'/') $$;
    CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid() PRIMARY KEY,bucket_id text NOT NULL,name text NOT NULL,UNIQUE(bucket_id,name));
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    GRANT USAGE ON SCHEMA storage TO anon,authenticated;
    GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO anon,authenticated;
    CREATE POLICY fixture_proof_upload ON storage.objects FOR INSERT TO authenticated
      WITH CHECK(bucket_id='payment-proofs' AND name LIKE auth.uid()::text||'/%');`);
  const files = [
    '20260913000001_core_schema.sql', '20260913000002_rls_policies.sql',
    '20260913000003_balance_functions.sql', '20260917000005_payment_methods.sql',
    '20261029000001_atomic_money_contract.sql',
    '20261029000002_participant_identity_hardening.sql',
    '20261029000003_money_integrity_hardening.sql',
    '20261031000001_restrict_pair_outstanding.sql',
    '20261031000002_idempotent_money_commands.sql',
    '20261031000003_contact_financial_parties.sql',
    '20261031000004_atomic_group_creation.sql',
    '20261031000005_money_amount_limits.sql',
    '20261031000006_payment_decisions.sql',
    '20261101000001_payment_proof_revisions.sql',
    '20261101000002_expense_receipt_revisions.sql',
    '20261101000003_payment_method_access.sql',
    '20261101000004_atomic_payment_methods.sql',
    '20261101000005_reminder_acceptance.sql',
    '20261101000006_background_reminders.sql',
    '20261101000007_canonical_profile_phones.sql',
    '20261101000008_profile_writes.sql',
    '20261101000009_profile_avatars.sql',
    '20261101000010_connection_preferences.sql',
    '20261102000004_bilateral_expense_changes.sql',
    '20261102000005_expense_revision_projection.sql',
    '20261102000006_group_contact_expense_changes.sql',
    '20261102000007_ledger_read_pages.sql',
    '20261104000001_m1_cancellation_reminder_guards.sql',
  ];
  for (const name of files) {
    // PGlite's build supplies gen_random_uuid, but not these native extensions.
    const sql = migration(name);
    try { await db.exec(native ? sql : sql.replace(/^CREATE EXTENSION[^;]+;/gm, '')); }
    catch(error) { error.message = name + ': ' + error.message + ' position=' + error.position; throw error; }
  }
  // Minimal Auth fixture, deliberately created after core SQL: not a full GoTrue inventory.
  await db.exec("CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,phone text,raw_user_meta_data jsonb DEFAULT '{}'::jsonb)");
  await db.exec(`INSERT INTO public.users(id,display_name) VALUES
    ('${A}','Fixture A'),('${B}','Fixture B'),('${C}','Fixture outsider');
    INSERT INTO public.tabs(id,user_a,user_b) VALUES ('${TAB}','${A}','${B}');
    INSERT INTO public.tab_members(tab_id,user_id) VALUES ('${TAB}','${A}'),('${TAB}','${B}');`);
  const actor = async id => {
    await db.exec('RESET ROLE');
    await db.query("SELECT set_config('request.jwt.claim.sub',$1,false)", [id]);
    await db.exec('SET ROLE authenticated');
  };
  const call = async (rpc, op, command) => (await db.query(
    `SELECT public.${rpc}($1::uuid,$2::jsonb) AS id`, [op,JSON.stringify(command)])).rows[0].id;
  const denied = async (work, code) => assert.rejects(work, error => error.code === code);
  const expense={p_tab_id:TAB,p_description:'Fixture expense',p_category:'food',
    p_total_amount_centavos:10000,p_paid_by_user_id:A,p_participants:[
      {user_id:A,participant_role:'payer',share_amount_centavos:5000,acknowledged:true},
      {user_id:B,participant_role:'debtor',share_amount_centavos:5000,acknowledged:false}],
    p_due_date:null,p_receipt_url:null};
  await actor(A);
  // Deliberately discard the first response, then retry the exact command.
  await call('create_expense_v1',OP,expense);
  const original = await call('create_expense_v1',OP,expense);
  const replays = [];
  for(let i=0;i<8;i++) replays.push(await call('create_expense_v1',OP,expense));
  assert(replays.every(id=>id===original));
  await denied(()=>call('create_expense_v1',OP,{...expense,p_description:'changed'}),'22023');
  await denied(()=>call('submit_payment_v1',OP,{p_tab_id:TAB}),'22023');
  await denied(()=>call('create_expense_v1',null,expense),'22023');
  await actor(C);
  await denied(()=>call('create_expense_v1',OP,expense),'42501');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.transactions')).rows[0].n,1);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.financial_operations')).rows[0].n,1);
  await actor(A);
  const invalid='00000000-0000-4000-8000-000000000099';
  await denied(()=>call('create_expense_v1',invalid,{...expense,p_total_amount_centavos:0}),'P0001');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.financial_operations WHERE operation_id=$1',[invalid])).rows[0].n,0);
  await actor(A);
  assert(await call('create_expense_v1',invalid,expense));
  await actor(B);
  const payment={p_tab_id:TAB,p_submitted_by_user_id:B,p_recipient_user_id:A,
    p_amount_centavos:1000,p_payment_method:'cash',p_note:null};
  const paid = await call('submit_payment_v1',PAY,payment);
  assert.equal(await call('submit_payment_v1',PAY,payment),paid);
  await denied(()=>call('submit_payment_v1',PAY,{...payment,p_amount_centavos:2000}),'22023');
  await actor(A);
  await db.query('SELECT public.confirm_payment($1::uuid)',[paid]);
  await actor(B);
  assert.equal(await call('submit_payment_v1',PAY,payment),paid);
  // Actor scope allows B to reuse A's operation ID without overwriting A.
  const other = await call('create_expense_v1',OP,expense);
  assert.notEqual(other,original);
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.payments')).rows[0].n,1);
  for (const role of ['anon','authenticated']) {
    const grants = await db.query(`SELECT
      has_function_privilege($1,'public.execute_money_command_v1(uuid,text,jsonb)','execute') AS internal,
      has_function_privilege($1,'public.create_expense_atomic(uuid,text,text,bigint,uuid,jsonb,date,text)','execute') AS legacy,
      has_table_privilege($1,'public.financial_operations','select') AS registry,
      has_table_privilege($1,'public.transactions','insert') AS direct`,[role]);
    assert.deepEqual(grants.rows[0],{internal:false,legacy:false,registry:false,direct:false});
  }
  await actor(A);
  const D='00000000-0000-4000-8000-000000000040';
  const E='00000000-0000-4000-8000-000000000041';
  const resolve = async id => (await db.query('SELECT public.resolve_contact_tab_v1($1::uuid,$2) AS result',[id,'Same name'])).rows[0].result;
  const d = await resolve(D), e = await resolve(E);
  await denied(()=>resolve(A),'22023');
  assert.notEqual(d.tab_id,e.tab_id);
  assert.deepEqual(await resolve(D),d);
  const contactExpense={...expense,p_tab_id:d.tab_id,p_participants:[
    {user_id:A,participant_role:'payer',share_amount_centavos:5000,acknowledged:true},
    {contact_id:D,participant_role:'debtor',share_amount_centavos:5000,acknowledged:false}]};
  await call('create_expense_v1','00000000-0000-4000-8000-000000000050',contactExpense);
  const contactPayer={...expense,p_tab_id:e.tab_id,p_paid_by_user_id:E,p_participants:[
    {contact_id:E,participant_role:'payer',share_amount_centavos:4000,acknowledged:false},
    {user_id:A,participant_role:'debtor',share_amount_centavos:6000,acknowledged:true}]};
  await call('create_expense_v1','00000000-0000-4000-8000-000000000051',contactPayer);
  const received={p_tab_id:d.tab_id,payer:{kind:'contact',id:D},recipient:{kind:'user',id:A},amount_centavos:2500,method:'cash',note:'Fixture cash received'};
  const contactPayOp='00000000-0000-4000-8000-000000000052';
  const cashId=await call('record_received_payment_v1',contactPayOp,received);
  assert.equal(await call('record_received_payment_v1',contactPayOp,received),cashId);
  await denied(()=>call('record_received_payment_v1',contactPayOp,{...received,amount_centavos:3000}),'22023');
  const outgoing={p_tab_id:e.tab_id,payer:{kind:'user',id:A},recipient:{kind:'contact',id:E},amount_centavos:1000,method:'cash',note:'Fixture cash paid'};
  await call('record_received_payment_v1','00000000-0000-4000-8000-000000000053',outgoing);
  await denied(()=>call('record_received_payment_v1','00000000-0000-4000-8000-000000000054',{...received,amount_centavos:3000}),'22023');
  await actor(B);
  await denied(()=>resolve(D),'42501');
  await denied(()=>call('record_received_payment_v1','00000000-0000-4000-8000-000000000055',received),'42501');
  await db.exec('RESET ROLE');
  assert.equal(Number((await db.query('SELECT public.calculate_user_tab_balance_unchecked($1::uuid,$2::uuid) AS balance',[d.tab_id,A])).rows[0].balance),2500);
  assert.equal(Number((await db.query('SELECT public.calculate_user_tab_balance_unchecked($1::uuid,$2::uuid) AS balance',[e.tab_id,A])).rows[0].balance),-5000);
  assert.equal((await db.query('SELECT payer_contact_id FROM public.payments WHERE id=$1',[cashId])).rows[0].payer_contact_id,D);
  await actor(A);
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS balance',[d.tab_id,A])).rows[0].balance),2500);
  // A group is a ledger container, never a payment recipient. Bob's payment
  // to Carol must leave uninvolved Alice unchanged, pending or confirmed.
  const GROUP='00000000-0000-4000-8000-000000000060';
  await db.exec('RESET ROLE');
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[GROUP]);
  for(const id of [A,B,C]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[GROUP,id]);
  await actor(C);
  await call('create_expense_v1','00000000-0000-4000-8000-000000000061',{
    ...expense,p_tab_id:GROUP,p_paid_by_user_id:C,p_participants:[
      {user_id:A,participant_role:'debtor',share_amount_centavos:3000},
      {user_id:B,participant_role:'debtor',share_amount_centavos:3000},
      {user_id:C,participant_role:'payer',share_amount_centavos:4000}]});
  const balance = async id => {
    await actor(id);
    return Number((await db.query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS n',[GROUP,id])).rows[0].n);
  };
  assert.equal(await balance(A),-3000);
  await actor(B);
  const groupPayment=await call('submit_payment_v1','00000000-0000-4000-8000-000000000062',{
    ...payment,p_tab_id:GROUP,p_recipient_user_id:C});
  assert.equal(await balance(A),-3000);
  await actor(C);
  await db.query('SELECT public.confirm_payment($1::uuid)',[groupPayment]);
  assert.equal(await balance(A),-3000);
  assert.equal(await balance(B),-2000);
  assert.equal(await balance(C),5000);
  // Plain explicit allocations already belong to M1: payer owns zero, two
  // debtors own 150/300. Replays and new equal-valued operations are distinct.
  const customTab=randomUUID(), customOperation=randomUUID();
  await db.exec('RESET ROLE');
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[customTab]);
  for(const id of [A,B,C]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[customTab,id]);
  await actor(A);
  const custom={...expense,p_tab_id:customTab,p_total_amount_centavos:45000,
    p_description:'Custom 0/150/300',p_participants:[
      {user_id:A,participant_role:'payer',share_amount_centavos:0},
      {user_id:B,participant_role:'debtor',share_amount_centavos:15000},
      {user_id:C,participant_role:'debtor',share_amount_centavos:30000}]};
  const customId=await call('create_expense_v1',customOperation,custom);
  assert.equal(await call('create_expense_v1',customOperation,custom),customId);
  for(const [id,expected] of [[A,45000],[B,-15000],[C,-30000]]) {
    await actor(id);
    assert.equal(Number((await db.query('SELECT public.get_net_balance($1,$2) AS n',[customTab,id])).rows[0].n),expected);
  }
  await actor(A);
  await denied(()=>call('create_expense_v1',customOperation,{...custom,p_description:'Changed retry'}),'22023');
  assert.notEqual(await call('create_expense_v1',randomUUID(),custom),customId);
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1,$2) AS n',[customTab,A])).rows[0].n),90000);
  console.log('CUSTOM_PLAIN_ALLOCATIONS_OK: existing M1 RPC validates 0/150/300, both debtors, exact replay and intentional second expense.');
  const zeroTab=randomUUID();
  await db.exec('RESET ROLE');
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[zeroTab]);
  for(const id of [A,B,C]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[zeroTab,id]);
  await actor(A);
  for(const [payer,debtor] of [[A,B],[C,A]]) {
    await call('create_expense_v1',randomUUID(),{...expense,p_tab_id:zeroTab,p_paid_by_user_id:payer,
      p_participants:[{user_id:payer,participant_role:'payer',share_amount_centavos:5000},
        {user_id:debtor,participant_role:'debtor',share_amount_centavos:5000}]});
  }
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS n',[zeroTab,A])).rows[0].n),0);
  const zeroPayment=await call('submit_payment_v1',randomUUID(),{...payment,p_tab_id:zeroTab,
    p_submitted_by_user_id:A,p_recipient_user_id:C,p_amount_centavos:4000});
  await actor(C);
  await db.query('SELECT public.confirm_payment($1::uuid)',[zeroPayment]);
  await actor(B);
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS n',[zeroTab,B])).rows[0].n),-5000);
  // Every member can pay an odd-cent bill. Preserve the exact individual
  // allocation and check all perspectives, never assign an aggregate to payer.
  await db.exec('RESET ROLE');
  const extras=[randomUUID(),randomUUID()];
  for(const id of extras) await db.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Fixture member')",[id]);
  for(const memberIds of [[A,B,C],[A,B,C,...extras]]) {
    const sorted=[...memberIds].sort();
    const share=new Map(sorted.map((id,i)=>[id,Math.floor(10001/sorted.length)+(i<10001%sorted.length?1:0)]));
    for(const payer of memberIds) {
      await db.exec('RESET ROLE');
      const tab=randomUUID();
      await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
      for(const id of memberIds) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,id]);
      await actor(payer);
      await call('create_expense_v1',randomUUID(),{...expense,p_tab_id:tab,
        p_total_amount_centavos:10001,p_paid_by_user_id:payer,p_participants:memberIds.map(id=>({
          user_id:id,participant_role:id===payer?'payer':'debtor',share_amount_centavos:share.get(id)}))});
      let sum=0;
      for(const id of memberIds) {
        await actor(id);
        const actual=Number((await db.query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS n',[tab,id])).rows[0].n);
        assert.equal(actual,id===payer?10001-share.get(id):-share.get(id)); sum+=actual;
      }
      assert.equal(sum,0);
    }
  }
  await db.exec('RESET ROLE');
  await db.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES ($1,$2,'accepted')",[A,B]);
  const groupCommand={name:'Atomic fixture group',member_user_ids:[B]};
  const groupOperation=randomUUID();
  const createGroup=async(op,command)=>(await db.query('SELECT public.create_group_v1($1::uuid,$2::jsonb) AS result',[op,JSON.stringify(command)])).rows[0].result;
  const groupTables=['groups','group_members','tabs','tab_members','group_creation_commands'];
  const counts=async()=>{
    const result={};for(const table of groupTables)result[table]=(await db.query(`SELECT count(*)::int AS n FROM public.${table}`)).rows[0].n;
    return result;
  };
  const before=await counts();
  await db.exec("CREATE FUNCTION pg_temp.fail_group_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected fixture failure'; END; $$");
  for(const table of groupTables) {
    await db.exec(`CREATE TRIGGER fixture_group_failure BEFORE INSERT ON public.${table} FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_group_insert()`);
    await actor(A);
    await denied(()=>createGroup(groupOperation,groupCommand),'P0001');
    await db.exec('RESET ROLE');
    assert.deepEqual(await counts(),before,`No partial state after ${table} insert failure`);
    await db.exec(`DROP TRIGGER fixture_group_failure ON public.${table}`);
  }
  await actor(A);
  const createdGroup=await createGroup(groupOperation,groupCommand);
  assert.deepEqual(await createGroup(groupOperation,groupCommand),createdGroup);
  await denied(()=>createGroup(groupOperation,{...groupCommand,name:'Changed group'}),'22023');
  await denied(()=>createGroup(randomUUID(),{...groupCommand,member_user_ids:[B,B]}),'22023');
  await denied(()=>createGroup(randomUUID(),{...groupCommand,member_user_ids:[C]}),'42501');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.group_members WHERE group_id=$1',[createdGroup.group_id])).rows[0].n,2);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.tab_members WHERE tab_id=$1',[createdGroup.tab_id])).rows[0].n,2);
  for(const table of groupTables) assert.equal((await counts())[table],before[table]+(table==='group_members'||table==='tab_members'?2:1));
  assert.equal((await db.query("SELECT has_table_privilege('authenticated','public.groups','insert') AS allowed")).rows[0].allowed,false);
  console.log('GROUP_ATOMICITY_OK: failures at all five insert stages roll back every row; same-operation retry reuses one complete group/tab; duplicates and nonfriends denied.');
  await actor(A);
  const maximum={...expense,p_total_amount_centavos:99999999999,p_participants:[
    {user_id:A,participant_role:'payer',share_amount_centavos:50000000000},
    {user_id:B,participant_role:'debtor',share_amount_centavos:49999999999}]};
  assert(await call('create_expense_v1',randomUUID(),maximum));
  await denied(()=>call('create_expense_v1',randomUUID(),{...maximum,p_total_amount_centavos:100000000000,
    p_participants:[{user_id:A,participant_role:'payer',share_amount_centavos:50000000000},
      {user_id:B,participant_role:'debtor',share_amount_centavos:50000000000}]}),'23514');
  await denied(()=>call('create_expense_v1',randomUUID(),{...expense,p_total_amount_centavos:'100.5'}),'22P02');
  await denied(()=>call('submit_payment_v1',randomUUID(),{...payment,p_payment_method:'gcash'}),'22023');
  assert.equal((await db.query("SELECT has_function_privilege('authenticated','public.decide_payment_internal(uuid,boolean,text)','execute') AS allowed")).rows[0].allowed,false);
  assert.equal((await db.query("SELECT has_table_privilege('authenticated','public.payments','update') AS allowed")).rows[0].allowed,false);
  await actor(B);
  const proofPath=B+'/fixture-proof.jpg';
  await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('payment-proofs',$1)",[proofPath]);
  const proofPaymentOp=randomUUID();
  const withProof={...payment,p_amount_centavos:100,proof_path:proofPath,reference:'Synthetic reference'};
  const proofPayment=await call('submit_payment_v2',proofPaymentOp,withProof);
  assert.equal(await call('submit_payment_v2',proofPaymentOp,withProof),proofPayment);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.payment_proofs WHERE payment_id=$1',[proofPayment])).rows[0].n,1);
  await actor(A);
  assert.equal((await db.query('SELECT reference FROM public.payment_proofs WHERE payment_id=$1',[proofPayment])).rows[0].reference,'Synthetic reference');
  assert.equal((await db.query('SELECT name FROM storage.objects WHERE name=$1',[proofPath])).rows.length,1);
  await actor(C);
  assert.equal((await db.query('SELECT name FROM storage.objects WHERE name=$1',[proofPath])).rows.length,0);
  assert.equal((await db.query('SELECT id FROM public.payment_proofs WHERE payment_id=$1',[proofPayment])).rows.length,0);
  await actor(B);
  assert.equal((await db.query('DELETE FROM storage.objects WHERE name=$1 RETURNING name',[proofPath])).rows.length,0);
  assert.equal((await db.query('UPDATE storage.objects SET name=$1 WHERE name=$1 RETURNING name',[proofPath])).rows.length,0);
  await denied(()=>call('append_payment_proof_v1',randomUUID(),{payment_id:proofPayment,proof_path:A+'/guessed.jpg'}),'42501');
  const failedProofOp=randomUUID();
  await denied(()=>call('submit_payment_v2',failedProofOp,{...withProof,proof_path:B+'/missing.jpg'}),'42501');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.financial_operations WHERE operation_id=$1',[failedProofOp])).rows[0].n,0);
  console.log('PAYMENT_PROOF_CONTRACT_OK: payment/proof atomic replay, recipient exact-object read, stranger denial, referenced-object immutability and failed-proof rollback passed. Storage schema is a minimal local fixture, not Supabase Storage HTTP.');
  await db.exec('RESET ROLE');
  const legacyPath=A+'/legacy-receipt.jpg';
  await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('payment-proofs',$1)",[legacyPath]);
  await db.query('UPDATE public.transactions SET receipt_url=$1 WHERE id=$2',[legacyPath,original]);
  await actor(A);
  const receiptOp=randomUUID(),receiptPath=A+'/revision-1.jpg';
  await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('payment-proofs',$1)",[receiptPath]);
  const receiptCommand={transaction_id:original,proof_path:receiptPath};
  const revisionId=await call('append_transaction_receipt_v1',receiptOp,receiptCommand);
  assert.equal(await call('append_transaction_receipt_v1',receiptOp,receiptCommand),revisionId);
  await denied(()=>call('append_transaction_receipt_v1',receiptOp,{...receiptCommand,proof_path:A+'/changed.jpg'}),'22023');
  assert.equal((await db.query('DELETE FROM storage.objects WHERE name=$1 RETURNING name',[receiptPath])).rows.length,0);
  await actor(B);
  assert.equal((await db.query('SELECT name FROM storage.objects WHERE name=ANY($1::text[])',[[legacyPath,receiptPath]])).rows.length,2);
  assert.equal((await db.query('SELECT id FROM public.transaction_receipt_revisions WHERE transaction_id=$1',[original])).rows.length,1);
  await actor(C);
  assert.equal((await db.query('SELECT id FROM public.transaction_receipt_revisions WHERE transaction_id=$1',[original])).rows.length,0);
  await denied(()=>call('append_transaction_receipt_v1',randomUUID(),receiptCommand),'42501');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT receipt_url FROM public.transactions WHERE id=$1',[original])).rows[0].receipt_url,legacyPath);
  assert.equal((await db.query("SELECT has_table_privilege('authenticated','public.transactions','update') AS allowed")).rows[0].allowed,false);
  console.log('EXPENSE_RECEIPT_REVISION_OK: exact replay, original receipt retention, member read, outsider denial and referenced-object protection passed.');
  await require('./test-payment-method-access.cjs')(db,{actor,call,expense});
  await require('./test-payment-method-lifecycle.cjs')(db,{actor});
  await require('./test-reminder-acceptance.cjs')(db,{A,B,C,actor,expense});
  const pushFixture=await require('./test-background-reminders.cjs')(db,{A,B,C,actor,expense});
  await require('./test-profile-phones.cjs')(db,{A,B,C,actor});
  await require('./test-profile-writes.cjs')(db,{A,B,C,actor});
  await require('./test-profile-avatars.cjs')(db,{actor});
  const socialFixture=await require('./test-connection-preferences.cjs')(db,{actor});
  const expenseChangeFixture=await require('./test-expense-changes.cjs')(db,{actor,expense});
  const groupChangeFixture=await require('./test-group-contact-changes.cjs')(db,{actor,expense});
  await require('./test-ledger-pages.cjs')(db,{actor,A,B,C,TAB});
  await require('./test-account-anonymization.cjs')(db,{actor,A,expense});
  const m2Fixture=await require('./test-m2-contracts.cjs')(db,{actor});
  await db.exec('RESET ROLE');
  await db.exec('SET ROLE anon');
  await denied(()=>call('create_expense_v1',OP,expense),'42501');
  console.log(`MONEY_COMMAND_CONTRACT_OK: ${native ? 'native PostgreSQL' : 'PostgreSQL/WASM'} financial migration subset allocation/payment/replay/conflict/role/group-party checks passed.`);
  return {A,B,C,TAB,expense,groupCommand,pushFixture,socialFixture,expenseChangeFixture,groupChangeFixture,m2Fixture};
}
module.exports = {runMoneyContract};
if(require.main === module) (async () => {
  const {PGlite}=require('../.dart_tool/sql-check/node_modules/@electric-sql/pglite');
  const db=new PGlite();
  try { await runMoneyContract(db); }
  finally { await db.close(); }
})().catch(error => { console.error(error.message); process.exitCode=1; });
