'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
module.exports=async(db,{actor,owner,peer,tab,command})=>{
  await db.exec('RESET ROLE');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261102000010_recurring_obligations.sql'),'utf8'));
  for(const [anchor,index,date] of [['2028-01-31',1,'2028-02-29'],['2028-01-31',2,'2028-03-31'],['2027-01-31',1,'2027-02-28']]){
    assert.equal((await db.query("SELECT public.recurrence_date_v1($1,'monthly',1,$2)::text AS occurrence_day",[anchor,index])).rows[0].occurrence_day,date);
  }
  const dst=(await db.query("SELECT extract(epoch FROM (('2026-03-09'::date::timestamp AT TIME ZONE 'America/New_York')-('2026-03-08'::date::timestamp AT TIME ZONE 'America/New_York')))/3600 hours")).rows[0].hours;
  assert.equal(Number(dst),23);
  const today=(await db.query("SELECT (statement_timestamp() AT TIME ZONE 'Asia/Manila')::date::text AS occurrence_day")).rows[0].occurrence_day;
  const rule=randomUUID(),create={p_expected_actor:owner,action:'create',rule_id:rule,expected_revision:0,p_tab_id:tab,
    anchor:today,timezone:'Asia/Manila',unit:'daily',step:1,end_date:null,template:command};
  const call=async(name,op,c)=>(await db.query(`SELECT public.${name}($1,$2) id`,[op,c])).rows[0].id;
  await actor(owner);await assert.rejects(call('change_recurrence_v1',randomUUID(),create),e=>e.code==='42501');
  await db.exec('RESET ROLE');await db.exec("UPDATE public.m2_feature_flags SET enabled=true WHERE feature='recurring'");
  await actor(owner);const op=randomUUID();assert.equal(await call('change_recurrence_v1',op,create),rule);assert.equal(await call('change_recurrence_v1',op,create),rule);
  await assert.rejects(call('change_recurrence_v1',op,{...create,step:2}),e=>e.code==='22023');
  const materialize={p_expected_actor:owner,rule_id:rule,occurrence_date:today};
  const occurrence=await call('materialize_recurrence_v1',randomUUID(),materialize);
  assert.equal(await call('materialize_recurrence_v1',randomUUID(),materialize),occurrence);
  await actor(peer);await assert.rejects(call('materialize_recurrence_v1',randomUUID(),{...materialize,p_expected_actor:peer}),e=>e.code==='42501');
  assert.equal((await db.query('SELECT public.list_recurrences_v1($1) data',[tab])).rows[0].data.records.length,0);
  await actor(owner);const pause={p_expected_actor:owner,rule_id:rule,action:'pause',expected_revision:1};
  const pausedOp=randomUUID();await call('change_recurrence_v1',pausedOp,pause);await call('change_recurrence_v1',pausedOp,pause);
  const tomorrow=(await db.query("SELECT ($1::date+1)::text AS occurrence_day",[today])).rows[0].occurrence_day;
  await assert.rejects(call('materialize_recurrence_v1',randomUUID(),{...materialize,occurrence_date:tomorrow}),e=>e.code==='22023');
  await call('change_recurrence_v1',randomUUID(),{p_expected_actor:owner,rule_id:rule,action:'resume',expected_revision:2});
  assert.equal(await call('materialize_recurrence_v1',randomUUID(),materialize),occurrence);
  await call('change_recurrence_v1',randomUUID(),{p_expected_actor:owner,rule_id:rule,action:'end',expected_revision:3});
  await assert.rejects(call('change_recurrence_v1',randomUUID(),{p_expected_actor:owner,rule_id:rule,action:'resume',expected_revision:4}),e=>e.code==='22023');
  await db.exec('RESET ROLE');
  const snapshot=(await db.query('SELECT to_jsonb(t) data FROM public.transactions t WHERE id=$1',[occurrence])).rows[0].data;
  const second=randomUUID();await actor(owner);
  await call('change_recurrence_v1',randomUUID(),{...create,rule_id:second});
  await call('change_recurrence_v1',randomUUID(),{...create,rule_id:second,action:'edit',expected_revision:1,step:2,
    template:{...command,p_description:'Updated future template'}});
  await assert.rejects(call('change_recurrence_v1',randomUUID(),{...create,rule_id:second,action:'edit',expected_revision:2,timezone:'UTC'}),e=>e.code==='22023');
  await db.exec('RESET ROLE');
  assert.deepEqual((await db.query('SELECT to_jsonb(t) data FROM public.transactions t WHERE id=$1',[occurrence])).rows[0].data,snapshot);
  await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE service_role');
  const batch=(await db.query('SELECT public.materialize_due_recurrences_v1(100) data')).rows[0].data;
  assert.equal(batch.needs_attention,0);assert.equal(batch.processed,1);
  assert.equal((await db.query('SELECT public.materialize_due_recurrences_v1(100) data')).rows[0].data.processed,0);
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.recurrence_occurrences WHERE rule_id=$1',[rule])).rows[0].n,1);
  const raceRule=randomUUID();await actor(owner);await call('change_recurrence_v1',randomUUID(),{...create,rule_id:raceRule});
  // A separate real SQL lifecycle fixture exercises the new privacy wrapper,
  // without retiring the owner retained for independent-session race tests.
  await db.exec('RESET ROLE');const retired=randomUUID(),retiredTab=randomUUID(),retiredRule=randomUUID();
  await db.query("INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES($1,'recurrence-private@example.invalid','{}')",[retired]);
  await db.query('INSERT INTO public.tabs(id,user_a,user_b) VALUES($1,$2,$3)',[retiredTab,retired,peer]);
  const retiredCommand={...command,p_expected_actor:retired,p_tab_id:retiredTab,p_paid_by_user_id:retired,
    p_participants:command.p_participants.map(p=>({...p,user_id:p.user_id===owner?retired:p.user_id})),
    split:{...command.split,base_shares:command.split.base_shares.map(p=>({...p,party:{...p.party,id:p.party.id===owner?retired:p.party.id}}))}};
  retiredCommand.p_participants=(await db.query('SELECT public.allocate_custom_split_v1($1,$2) data',[retiredCommand.split,retired])).rows[0].data.participants;
  await actor(retired);await call('change_recurrence_v1',randomUUID(),{...create,rule_id:retiredRule,p_expected_actor:retired,p_tab_id:retiredTab,template:retiredCommand});
  await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify({amr:[{method:'password',timestamp:Math.floor(Date.now()/1000)}]})]);
  const request=(await db.query('SELECT public.request_account_deletion_v1() data')).rows[0].data.id;
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE service_role');
  await db.query('SELECT public.review_account_deletion_v1($1)',[request]);await db.query('SELECT public.prepare_account_deletion_v1($1)',[request]);
  await db.exec('RESET ROLE');
  assert.deepEqual((await db.query('SELECT status,template FROM public.recurrence_rules WHERE id=$1',[retiredRule])).rows[0],{status:'ended',template:{}});
  assert.equal((await db.query("SELECT bool_and(snapshot->>'redacted'='true') ok FROM public.recurrence_events WHERE rule_id=$1",[retiredRule])).rows[0].ok,true);
  await actor(retired);await assert.rejects(call('change_recurrence_v1',randomUUID(),{...create,rule_id:randomUUID(),p_expected_actor:retired}),e=>e.code==='42501');
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");
  console.log('RECURRENCE_CONTRACT_OK: disabled rollout, calendar/DST, owner/replay/conflict, pause/resume/end, immutable history and service scheduler replay passed. No JWT impersonation or live scheduler used.');
  return {rule:raceRule,date:today,owner};
};
