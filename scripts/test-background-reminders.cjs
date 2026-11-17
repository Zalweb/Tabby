'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
module.exports=async function(db,{A,B,C,actor,expense}) {
  await db.exec('RESET ROLE');
  const tab=randomUUID(),installation=randomUUID(),binding=randomUUID();
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
  for(const user of [A,B]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,user]);
  await actor(A);
  await db.query('SELECT public.create_expense_v1($1,$2::jsonb)',[randomUUID(),JSON.stringify({...expense,p_tab_id:tab})]);
  const token='synthetic-token-for-local-contract-'+randomUUID();
  const register=(i,b,t,enabled)=>db.query('SELECT public.register_push_device_v1($1,$2,$3,$4) AS yes',[i,b,t,enabled]);
  const revoke=(i,b)=>db.query('SELECT public.revoke_push_device_v1($1,$2) AS yes',[i,b]);
  const notification=async()=>{
    await db.exec('RESET ROLE');
    const id=(await db.query("INSERT INTO public.notifications(recipient_user_id,notification_type,related_tab_id,title,body) VALUES ($1,'manual_nudge',$2,'Synthetic','Synthetic') RETURNING id",[B,tab])).rows[0].id;
    await db.query('INSERT INTO public.reminder_operations(actor_id,operation_id,command,notification_id) VALUES ($1,$2,$3::jsonb,$4)',[A,randomUUID(),JSON.stringify({tab_id:tab,recipient_user_id:B}),id]);
    return id;
  };
  const claim=async()=>{await db.exec('RESET ROLE');await db.exec('SET ROLE service_role');return (await db.query('SELECT * FROM public.claim_reminder_push_v1(50)')).rows;};
  const finish=(job,outcome,lease=job.lease_id)=>db.query('SELECT public.finish_reminder_push_v1($1,$2,$3) AS yes',[job.job_id,lease,outcome]);
  await actor(B);
  assert.equal((await register(installation,binding,token,false)).rows[0].yes,true);
  await notification();
  assert.equal((await claim()).length,0);
  await actor(B);await register(installation,binding,token,true);
  const event=await notification();
  const [first]=await claim();
  assert.equal(first.notification_id,event);assert.equal(first.user_id,B);assert.equal(first.binding_id,binding);assert.equal(first.token,token);
  assert.equal((await claim()).length,0); // No double lease.
  await db.exec('RESET ROLE');
  await db.query("UPDATE public.push_delivery_jobs SET lease_until=now()-interval '1 second' WHERE id=$1",[first.job_id]);
  const [second]=await claim();assert.notEqual(second.lease_id,first.lease_id);
  assert.equal((await finish(second,'accepted',first.lease_id)).rows[0].yes,false);
  assert.equal((await finish(second,'retry')).rows[0].yes,true);
  assert.equal((await claim()).length,0); // Backoff.
  await db.exec('RESET ROLE');await db.query("UPDATE public.push_delivery_jobs SET next_attempt_at=now()-interval '1 second' WHERE id=$1",[first.job_id]);
  const [third]=await claim();await finish(third,'accepted');
  assert.equal((await claim()).length,0);
  await notification();const [rotating]=await claim();
  const rotatedToken='synthetic-rotated-token-'+randomUUID();
  await actor(B);await register(installation,binding,rotatedToken,true);
  await db.exec('RESET ROLE');await db.exec('SET ROLE service_role');
  assert.equal((await finish(rotating,'unregistered')).rows[0].yes,false);
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT token FROM public.push_device_bindings WHERE installation_id=$1',[installation])).rows[0].token,rotatedToken);
  await notification();const [old]=await claim();
  const replacement=randomUUID();await actor(B);await register(installation,replacement,token,true);
  await db.exec('RESET ROLE');await db.exec('SET ROLE service_role');
  assert.equal((await finish(old,'accepted')).rows[0].yes,false); // Replaced binding invalidates lease.
  await actor(B);assert.equal((await revoke(installation,binding)).rows[0].yes,false);
  await notification();const [fresh]=await claim();assert.equal(fresh.binding_id,replacement);
  await finish(fresh,'unregistered');
  await db.exec('RESET ROLE');assert.equal((await db.query('SELECT count(*)::int AS n FROM public.push_device_bindings WHERE installation_id=$1',[installation])).rows[0].n,0);
  // Account switch owns the new binding; an old account cannot revoke it.
  await actor(A);const switched=randomUUID();await register(installation,switched,token,true);
  await actor(B);assert.equal((await revoke(installation,replacement)).rows[0].yes,false);
  await actor(A);assert.equal((await revoke(installation,switched)).rows[0].yes,true);
  // A recipient removed from a shared tab cannot receive a queued push.
  await actor(B);await register(installation,replacement,token,true);await notification();
  await db.exec('RESET ROLE');await db.query('DELETE FROM public.tab_members WHERE tab_id=$1 AND user_id=$2',[tab,B]);
  assert.equal((await claim()).length,0);
  await db.exec('RESET ROLE');await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,B]);
  await notification();await db.query("UPDATE public.push_device_bindings SET expires_at=now()-interval '1 second' WHERE installation_id=$1",[installation]);
  assert.equal((await claim()).length,0);
  await db.exec('RESET ROLE');
  for(const role of ['anon','authenticated']) {
    const grants=(await db.query(`SELECT has_table_privilege($1,'public.push_device_bindings','select') AS tokens,
      has_table_privilege($1,'public.push_delivery_jobs','select') AS jobs,
      has_function_privilege($1,'public.claim_reminder_push_v1(integer)','execute') AS claim,
      has_function_privilege($1,'public.finish_reminder_push_v1(uuid,uuid,text)','execute') AS finish`,[role])).rows[0];
    assert.deepEqual(grants,{tokens:false,jobs:false,claim:false,finish:false});
  }
  await actor(B);await register(installation,replacement,token,true);
  await notification();
  await db.query("UPDATE public.push_delivery_jobs SET status='sending',attempts=6,lease_until=now()-interval '1 second' WHERE installation_id=$1 AND status='pending'",[installation]);
  assert.equal((await claim()).length,0);
  await notification();
  await actor(B);
  const payment=(await db.query('SELECT public.submit_payment_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify({
    p_tab_id:tab,p_submitted_by_user_id:B,p_recipient_user_id:A,p_amount_centavos:5000,p_payment_method:'cash',p_note:null,
  })])).rows[0].id;
  await actor(A);await db.query('SELECT public.confirm_payment($1)',[payment]);
  assert.equal((await claim()).length,0); // Settled before worker pickup.
  await actor(A);
  await assert.rejects(()=>db.query('SELECT * FROM public.claim_reminder_push_v1(1)'),e=>e.code==='42501');
  await assert.rejects(()=>db.query('SELECT token FROM public.push_device_bindings'),e=>e.code==='42501');
  await db.query('SELECT public.create_expense_v1($1,$2::jsonb)',[randomUUID(),JSON.stringify({...expense,p_tab_id:tab})]);
  console.log('BACKGROUND_REMINDER_CONTRACT_OK: private tokens/jobs, opt-out, binding replacement, stale logout/lease rejection, backoff, invalid-token retirement, removed member and expiry checks passed.');
  return {tab,installation,binding:replacement,recipient:B};
};
