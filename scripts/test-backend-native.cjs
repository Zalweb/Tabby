// Optional local-only native PostgreSQL contract/concurrency acceptance.
// npm install --prefix .dart_tool/native-db --no-save embedded-postgres@17.11.0-beta.19
// node scripts/test-backend-native.cjs
'use strict';
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const crypto=require('node:crypto');
const net=require('node:net');
const assert=require('node:assert/strict');
const {runMoneyContract}=require('./test-money-commands.cjs');

async function availablePort() {
 const server=net.createServer();
 await new Promise((resolve,reject)=>server.once('error',reject).listen(0,'127.0.0.1',resolve));
 const port=server.address().port;
 await new Promise(resolve=>server.close(resolve));
 return port;
}
(async()=>{
 const modulePath=process.env.TABBY_NATIVE_DB_MODULE || path.resolve(__dirname,'../.dart_tool/native-db/node_modules/embedded-postgres/dist/index.js');
 const {default:EmbeddedPostgres}=await import(pathToFileURL(modulePath).href);
 // Persistent avoids library recursive cleanup; the unique synthetic cluster
 // stays in ignored workspace tooling. No host users or existing DB are used.
 const db=new EmbeddedPostgres({
  databaseDir:path.resolve(__dirname,'../.dart_tool/native-db/cluster-'+crypto.randomUUID()),
  port:await availablePort(),user:'postgres',password:crypto.randomBytes(32).toString('hex'),
  authMethod:'scram-sha-256',persistent:true,createPostgresUser:false,autoRehydrateSymlinks:false,
  postgresFlags:['-c','listen_addresses=127.0.0.1'],onLog:()=>{},onError:()=>{},
 });
 const clients=[];
 async function connect(actor) {
  const client=db.getPgClient('postgres','127.0.0.1');
  await client.connect(); clients.push(client);
  if(actor) {
   await client.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[actor]);
   await client.query('SET ROLE authenticated');
  }
  return client;
 }
 try {
  await db.initialise(); await db.start();
  const admin=await connect();
  const fixture=await runMoneyContract({exec:sql=>admin.query(sql),query:(sql,params)=>admin.query(sql,params)},{native:true});
  const sessions=await Promise.all(Array.from({length:8},()=>connect(fixture.A)));
  const pids=await Promise.all(sessions.map(async c=>(await c.query('SELECT pg_backend_pid() AS id')).rows[0].id));
  assert.equal(new Set(pids).size,8,'Eight independent native backend sessions required');
  const operation=crypto.randomUUID();
  const ids=await Promise.all(sessions.map(async c=>(await c.query(
   'SELECT public.create_expense_v1($1::uuid,$2::jsonb) AS id',[operation,JSON.stringify(fixture.expense)])).rows[0].id));
  assert(ids.every(id=>id===ids[0]));
  await admin.query('RESET ROLE');
  const rows=await admin.query('SELECT count(*)::int AS n FROM public.financial_operations WHERE actor_id=$1 AND operation_id=$2',[fixture.A,operation]);
  assert.equal(rows.rows[0].n,1);
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.transactions WHERE id=$1',[ids[0]])).rows[0].n,1);
  await assert.rejects(()=>sessions[1].query('SELECT public.create_expense_v1($1::uuid,$2::jsonb)',[
   operation,JSON.stringify({...fixture.expense,p_description:'Conflicting retry'})]),e=>e.code==='22023');
  const groupOperation=crypto.randomUUID();
  const groups=await Promise.all(sessions.map(async c=>(await c.query(
   'SELECT public.create_group_v1($1::uuid,$2::jsonb) AS result',[groupOperation,JSON.stringify(fixture.groupCommand)])).rows[0].result));
  groups.forEach(g=>assert.deepEqual(g,groups[0]));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.group_creation_commands WHERE actor_id=$1 AND operation_id=$2',[fixture.A,groupOperation])).rows[0].n,1);
  const methodOperation=crypto.randomUUID();
  const methodCommand={method_id:crypto.randomUUID(),expected_revision:null,
    provider:'other',display_name:'Concurrent method',account_label:'Synthetic',
    qr_storage_path:null,make_default:false};
  const methodResults=await Promise.all(sessions.map(c=>c.query(
    "SELECT public.change_payment_method_v1($1,'save',$2::jsonb) AS result",
    [methodOperation,JSON.stringify(methodCommand)])));
  methodResults.forEach(r=>assert.equal(r.rows[0].result.id,methodCommand.method_id));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.payment_method_operations WHERE actor_id=$1 AND operation_id=$2',[fixture.A,methodOperation])).rows[0].n,1);
  const methodIds=sessions.map(()=>crypto.randomUUID());
  await Promise.all(sessions.map((c,i)=>c.query(
    "SELECT public.change_payment_method_v1($1,'save',$2::jsonb)",
    [crypto.randomUUID(),JSON.stringify({...methodCommand,method_id:methodIds[i],make_default:true})])));
  await Promise.all(sessions.map((c,i)=>c.query(
    "SELECT public.change_payment_method_v1($1,'prefer',$2::jsonb)",
    [crypto.randomUUID(),JSON.stringify({method_id:methodIds[i]})])));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.payment_methods WHERE owner_user_id=$1 AND is_active AND is_default',[fixture.A])).rows[0].n,1);
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.payment_methods WHERE owner_user_id=$1 AND is_active',[fixture.A])).rows[0].n,9);
  console.log('PAYMENT_METHOD_CONCURRENCY_OK: eight independent sessions replay one method operation and serialize concurrent creation/preference changes with exactly one active default.');
  const reminderTab=crypto.randomUUID(),reminderOperation=crypto.randomUUID();
  await admin.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[reminderTab]);
  for(const id of [fixture.A,fixture.B]) await admin.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[reminderTab,id]);
  await sessions[0].query('SELECT public.create_expense_v1($1,$2::jsonb)',[crypto.randomUUID(),JSON.stringify({...fixture.expense,p_tab_id:reminderTab})]);
  const reminderCommand={tab_id:reminderTab,recipient_user_id:fixture.B,title:'Concurrent reminder',body:'Open Tabby.'};
  const reminders=await Promise.all(sessions.map(c=>c.query('SELECT public.send_tab_reminder_v1($1,$2::jsonb) AS id',[reminderOperation,JSON.stringify(reminderCommand)])));
  assert(reminders.every(r=>r.rows[0].id===reminders[0].rows[0].id));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.reminder_operations WHERE actor_id=$1 AND operation_id=$2',[fixture.A,reminderOperation])).rows[0].n,1);
  await admin.query("UPDATE public.reminder_operations SET accepted_at=now()-interval '6 hours 1 second' WHERE actor_id=$1 AND operation_id=$2",[fixture.A,reminderOperation]);
  const doubleTap=await Promise.allSettled(sessions.map((c,i)=>c.query(
    'SELECT public.send_tab_reminder_v1($1,$2::jsonb) AS id',[crypto.randomUUID(),JSON.stringify(reminderCommand)])));
  assert.equal(doubleTap.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(doubleTap.filter(r=>r.status==='rejected').length,7);
  assert(doubleTap.filter(r=>r.status==='rejected').every(r=>r.reason.code==='PT429'));
  assert.equal((await admin.query("SELECT count(*)::int AS n FROM public.notifications WHERE related_tab_id=$1 AND notification_type='manual_nudge'",[reminderTab])).rows[0].n,2);
  assert.equal((await admin.query("SELECT count(*)::int AS n FROM public.activity_logs WHERE tab_id=$1 AND event_type='REMINDER_SENT'",[reminderTab])).rows[0].n,2);
  console.log('REMINDER_CONCURRENCY_OK: exact replay is idempotent; eight distinct concurrent operations admit one and return seven PT429 responses with one notification/audit added.');
  const push=fixture.pushFixture;
  for(let i=0;i<8;i++) {
    const event=crypto.randomUUID();
    await admin.query("INSERT INTO public.notifications(id,recipient_user_id,notification_type,related_tab_id,title,body) VALUES ($1,$2,'manual_nudge',$3,'Synthetic','Synthetic')",[event,push.recipient,push.tab]);
    await admin.query('INSERT INTO public.reminder_operations(actor_id,operation_id,command,notification_id) VALUES ($1,$2,$3::jsonb,$4)',[fixture.A,crypto.randomUUID(),JSON.stringify({tab_id:push.tab,recipient_user_id:push.recipient}),event]);
  }
  const pendingPush=(await admin.query("SELECT count(*)::int AS n FROM public.push_delivery_jobs WHERE status='pending'")).rows[0].n;
  const workers=await Promise.all(Array.from({length:8},async()=>{const c=await connect();await c.query('SET ROLE service_role');return c;}));
  const claims=(await Promise.all(workers.map(c=>c.query('SELECT * FROM public.claim_reminder_push_v1(2)')))).flatMap(r=>r.rows);
  assert.equal(claims.length,pendingPush);assert.equal(new Set(claims.map(j=>j.job_id)).size,pendingPush);
  console.log('PUSH_LEASE_CONCURRENCY_OK: eight independent service-role workers claim each ready job once with disjoint leases.');
  // Data-integrity race as fixture owners, not profile API/RLS evidence.
  const phoneOwners=Array.from({length:8},()=>crypto.randomUUID());
  for(const id of phoneOwners)await admin.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Synthetic phone owner')",[id]);
  const phoneWriters=await Promise.all(phoneOwners.map(()=>connect()));
  const phoneForms=['09181234567','+639181234567','639181234567','9181234567'];
  const phoneResults=await Promise.allSettled(phoneWriters.map((c,i)=>c.query('UPDATE public.users SET phone=$1 WHERE id=$2',[phoneForms[i%4],phoneOwners[i]])));
  assert.equal(phoneResults.filter(r=>r.status==='fulfilled').length,1);
  assert(phoneResults.filter(r=>r.status==='rejected').every(r=>r.reason.code==='23505'));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.users WHERE phone=$1',['+639181234567'])).rows[0].n,1);
  console.log('PROFILE_PHONE_CONCURRENCY_OK: eight owner-role writes using equivalent formats produce one canonical phone; profile API/RLS remains outside this subset.');
  // Two distinct pending submissions together exceed the debt. Independent
  // recipient sessions must re-read the balance after obtaining the lock.
  const raceTab=crypto.randomUUID();
  await admin.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[raceTab]);
  for(const id of [fixture.A,fixture.B])await admin.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[raceTab,id]);
  await sessions[0].query('SELECT public.create_expense_v1($1::uuid,$2::jsonb)',[crypto.randomUUID(),JSON.stringify({...fixture.expense,p_tab_id:raceTab})]);
  const payer=await connect(fixture.B);
  const pending=[];
  for(let i=0;i<2;i++)pending.push((await payer.query('SELECT public.submit_payment_v1($1::uuid,$2::jsonb) AS id',[crypto.randomUUID(),JSON.stringify({
    p_tab_id:raceTab,p_submitted_by_user_id:fixture.B,p_recipient_user_id:fixture.A,p_amount_centavos:4000,p_payment_method:'gcash',p_note:null,
  })])).rows[0].id);
  // Delay after each balance check would occur without the lock: the old
  // implementation could admit both rows during this deterministic race.
  await admin.query("CREATE FUNCTION pg_temp.slow_confirmation_fixture() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN PERFORM pg_sleep(0.3); RETURN NEW; END; $$");
  await admin.query("CREATE TRIGGER slow_confirmation_fixture BEFORE UPDATE ON public.payments FOR EACH ROW WHEN (OLD.status='submitted' AND NEW.status='confirmed') EXECUTE FUNCTION pg_temp.slow_confirmation_fixture()");
  const decisions=await Promise.allSettled(pending.map((id,i)=>sessions[i].query('SELECT public.confirm_payment($1::uuid) AS id',[id])));
  await admin.query('DROP TRIGGER slow_confirmation_fixture ON public.payments');
  assert.equal(decisions.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(decisions.filter(r=>r.status==='rejected').length,1);
  assert.equal(decisions.find(r=>r.status==='rejected').reason.code,'22023');
  const winner=decisions.find(r=>r.status==='fulfilled').value.rows[0].id;
  const repeat=await Promise.all(sessions.map(c=>c.query('SELECT public.confirm_payment($1::uuid) AS id',[winner])));
  assert(repeat.every(r=>r.rows[0].id===winner));
  assert.equal((await admin.query("SELECT sum(amount_centavos)::int AS n FROM public.payments WHERE tab_id=$1 AND status='confirmed'",[raceTab])).rows[0].n,4000);
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.payments WHERE tab_id=$1',[raceTab])).rows[0].n,2);
  const loser=pending.find(id=>id!==winner);
  await assert.rejects(()=>sessions[0].query('SELECT public.reject_payment_v1($1::uuid,$2)',[loser,'']),e=>e.code==='22023');
  await sessions[0].query('SELECT public.reject_payment_v1($1::uuid,$2)',[loser,'Fixture duplicate submission']);
  await sessions[1].query('SELECT public.reject_payment_v1($1::uuid,$2)',[loser,'Fixture duplicate submission']);
  await assert.rejects(()=>sessions[0].query('SELECT public.reject_payment_v1($1::uuid,$2)',[loser,'Changed reason']),e=>e.code==='22023');
  await assert.rejects(()=>sessions[0].query('SELECT public.confirm_payment($1::uuid)',[loser]),e=>e.code==='22023');
  await assert.rejects(()=>payer.query('SELECT public.confirm_payment($1::uuid)',[winner]),e=>e.code==='42501');
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.payment_decisions WHERE payment_id=ANY($1::uuid[])',[pending])).rows[0].n,2);
  const finalPayment=(await payer.query('SELECT public.submit_payment_v1($1::uuid,$2::jsonb) AS id',[crypto.randomUUID(),JSON.stringify({
    p_tab_id:raceTab,p_submitted_by_user_id:fixture.B,p_recipient_user_id:fixture.A,p_amount_centavos:1000,p_payment_method:'gcash',p_note:null,
  })])).rows[0].id;
  await sessions[0].query('SELECT public.confirm_payment($1::uuid)',[finalPayment]);
  assert.equal(Number((await sessions[0].query('SELECT public.get_net_balance($1::uuid,$2::uuid) AS n',[raceTab,fixture.A])).rows[0].n),0);
  console.log('PAYMENT_DECISION_CONCURRENCY_OK: competing confirmations cannot overpay; repeated same-ID confirmation/rejection is idempotent; payer denied; original payment rows retained.');
  const social=fixture.socialFixture;
  const socialSessions=await Promise.all(Array.from({length:8},async()=>{const c=await connect();
    await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[social.owner]);await c.query('SET ROLE authenticated');return c;}));
  const socialOperation=crypto.randomUUID(),socialCommand={owner_id:social.owner,action:'archive',target_id:social.tab,expected_revision:4};
  const socialResults=await Promise.all(socialSessions.map(c=>c.query('SELECT public.change_connection_v1($1,$2::jsonb) AS value',[socialOperation,JSON.stringify(socialCommand)])));
  socialResults.forEach(result=>assert.deepEqual(result.rows[0].value,socialResults[0].rows[0].value));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.connection_operations WHERE owner_id=$1 AND operation_id=$2',[social.owner,socialOperation])).rows[0].n,1);
  const socialRaces=await Promise.allSettled(socialSessions.map(c=>c.query('SELECT public.change_connection_v1($1,$2::jsonb)',[crypto.randomUUID(),JSON.stringify({...socialCommand,action:'restore',expected_revision:5})])));
  assert.equal(socialRaces.filter(r=>r.status==='fulfilled').length,1);
  assert(socialRaces.filter(r=>r.status==='rejected').every(r=>r.reason.code==='40001'));
  console.log('CONNECTION_PREFERENCES_CONCURRENCY_OK: eight authenticated sessions replay one command; competing revision-bound writes admit one new intent and reject seven stale intents.');
  const changes=fixture.expenseChangeFixture;
  const requesters=await Promise.all(Array.from({length:8},()=>connect(changes.A)));
  const reviewers=await Promise.all(Array.from({length:8},()=>connect(changes.B)));
  const changeOperation=crypto.randomUUID();
  const requested=await Promise.all(requesters.map(c=>c.query(
    "SELECT public.request_expense_change_v1($1,$2,'correct',9001,'Concurrent correction',$3) AS id",[changeOperation,changes.source,changes.A])));
  const changeId=requested[0].rows[0].id;
  assert(requested.every(r=>r.rows[0].id===changeId));
  const accepted=await Promise.all(reviewers.map(c=>c.query('SELECT public.decide_expense_change_v1($1,true,$2) AS id',[changeId,changes.B])));
  assert(accepted.every(r=>r.rows[0].id===changeId));
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.expense_change_results WHERE transaction_id=$1',[changes.source])).rows[0].n,1);
  const another=(await requesters[0].query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[crypto.randomUUID(),JSON.stringify(changes.command)])).rows[0].id;
  const proposals=await Promise.all([7001,8001].map((amount,i)=>requesters[i].query(
    "SELECT public.request_expense_change_v1($1,$2,'correct',$3,'Competing correction',$4) AS id",[crypto.randomUUID(),another,amount,changes.A])));
  const outcomes=await Promise.allSettled(proposals.map((r,i)=>reviewers[i].query('SELECT public.decide_expense_change_v1($1,true,$2)',[r.rows[0].id,changes.B])));
  assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(outcomes.filter(r=>r.status==='rejected').length,1);
  assert.equal(outcomes.find(r=>r.status==='rejected').reason.code,'22023');
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.expense_change_results WHERE transaction_id=$1',[another])).rows[0].n,1);
  console.log('EXPENSE_CHANGE_CONCURRENCY_OK: eight request/decision replays apply one revision; competing proposals admit one accepted result.');
  const groupChange=fixture.groupChangeFixture;
  const finalReviewers=await Promise.all([connect(groupChange.reviewer),connect(groupChange.reviewer)]);
  const groupOutcomes=await Promise.allSettled(groupChange.proposals.map((id,i)=>finalReviewers[i].query(
    'SELECT public.decide_expense_change_v1($1,true,$2)',[id,groupChange.reviewer])));
  assert.equal(groupOutcomes.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(groupOutcomes.filter(r=>r.status==='rejected').length,1);
  assert.equal(groupOutcomes.find(r=>r.status==='rejected').reason.code,'22023');
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.expense_change_results WHERE transaction_id=$1',[groupChange.source])).rows[0].n,1);
  console.log('GROUP_CHANGE_CONCURRENCY_OK: competing final approvals after different partial votes apply exactly one group revision.');
  const custom=fixture.m2Fixture;
  const m2Sessions=await Promise.all(Array.from({length:8},()=>connect(custom.owner)));
  const m2Operation=crypto.randomUUID();
  const customRows=await Promise.all(m2Sessions.map(c=>c.query('SELECT public.create_expense_v3($1,$2) id',[m2Operation,custom.command])));
  assert(customRows.every(r=>r.rows[0].id===customRows[0].rows[0].id));
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.financial_operations WHERE actor_id=$1 AND operation_id=$2',[custom.owner,m2Operation])).rows[0].n,1);
  await assert.rejects(m2Sessions[0].query('SELECT public.create_expense_v3($1,$2)',[m2Operation,{...custom.command,p_description:'Changed'}]),e=>e.code==='22023');
  console.log('M2_CUSTOM_CONCURRENCY_OK: eight independent sessions create one charged expense and reject changed intent.');
  const recurrence=custom.recurrence;
  const recurrenceRows=await Promise.all(m2Sessions.map(c=>c.query('SELECT public.materialize_recurrence_v1($1,$2) id',[
    crypto.randomUUID(),{p_expected_actor:recurrence.owner,rule_id:recurrence.rule,occurrence_date:recurrence.date}])));
  assert(recurrenceRows.every(r=>r.rows[0].id===recurrenceRows[0].rows[0].id));
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.recurrence_occurrences WHERE rule_id=$1',[recurrence.rule])).rows[0].n,1);
  console.log('RECURRENCE_CONCURRENCY_OK: eight distinct owner operation IDs for one calendar occurrence produce one immutable expense.');
  const claim=custom.claim;
  const claimSessions=await Promise.all(Array.from({length:8},()=>connect(claim.peer)));
  const claimRows=await Promise.all(claimSessions.map(c=>c.query('SELECT public.decide_contact_claim_v1($1,$2) id',[
    crypto.randomUUID(),{p_expected_actor:claim.peer,claim_id:claim.claim,accept:true,snapshot_digest:claim.digest}])));
  assert(claimRows.every(r=>r.rows[0].id===claim.claim));
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.transactions WHERE tab_id=$1',[claim.source.tab])).rows[0].n,2);
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.contact_claim_invitations WHERE id=$1 AND transfer_id IS NOT NULL',[claim.claim])).rows[0].n,1);
  console.log('CONTACT_CLAIM_CONCURRENCY_OK: eight distinct acceptance commands append one offset and one registered transfer while preserving originals.');
  const review=custom.review;
  const reviewRows=await Promise.all(claimSessions.map(c=>c.query('SELECT public.review_expense_v1($1,$2) id',[
    crypto.randomUUID(),{p_expected_actor:review.peer,transaction_id:review.expense,action:'acknowledge'}])));
  assert(reviewRows.every(r=>r.rows[0].id===reviewRows[0].rows[0].id));
  const resolutionRows=await Promise.all(claimSessions.map(c=>c.query('SELECT public.review_expense_v1($1,$2) id',[
    crypto.randomUUID(),{p_expected_actor:review.peer,transaction_id:review.expense,action:'vote_resolution',dispute_id:review.dispute,resolution_id:review.resolution,accept:true}])));
  assert(resolutionRows.every(r=>r.rows[0].id===review.resolution));
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.expense_resolution_votes WHERE resolution_id=$1',[review.resolution])).rows[0].n,2);
  const proposalRows=await Promise.all(claimSessions.map(c=>c.query('SELECT public.review_expense_v1($1,$2) id',[
    crypto.randomUUID(),{p_expected_actor:review.peer,transaction_id:review.expense,action:'decide_proposal',change_id:review.proposal,accept:true}])));
  assert(proposalRows.every(r=>r.rows[0].id===review.proposal));
  assert.equal((await admin.query('SELECT count(*)::int n FROM public.expense_change_results WHERE transaction_id=$1',[review.expense])).rows[0].n,1);
  console.log('EXPENSE_REVIEW_CONCURRENCY_OK: eight sessions acknowledge once, finalize one unanimous resolution and apply one compensating proposal result.');
  console.log('NATIVE_CONCURRENCY_OK: financial, social and expense-change session races passed. Native extensions and migration subset applied. No Supabase services or deployment tested.');
 } finally {
  await Promise.allSettled(clients.map(c=>c.end()));
  await db.stop();
 }
})().catch(error=>{console.error(error.message);process.exitCode=1;});
