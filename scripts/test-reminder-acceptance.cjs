'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
module.exports=async function(db,{A,B,C,actor,expense}) {
  await db.exec('RESET ROLE');
  const tab=randomUUID();
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
  for(const id of [A,B,C]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,id]);
  await actor(A);
  await db.query('SELECT public.create_expense_v1($1,$2::jsonb)',[randomUUID(),JSON.stringify({...expense,p_tab_id:tab})]);
  const command={tab_id:tab,recipient_user_id:B,title:'Fixture reminder',body:'Open Tabby to review.'};
  const call=(id,cmd=command)=>db.query('SELECT public.send_tab_reminder_v1($1,$2::jsonb) AS id',[id,JSON.stringify(cmd)]);
  const operation=randomUUID();
  const original=(await call(operation)).rows[0].id;
  assert.equal((await call(operation)).rows[0].id,original);
  await assert.rejects(()=>call(operation,{...command,title:'Changed'}),e=>e.code==='22023');
  await assert.rejects(()=>call(randomUUID()),e=>e.code==='PT429'); // HTTP 429 rate-limit contract.
  await assert.rejects(()=>call(randomUUID(),{...command,recipient_user_id:C}),e=>e.code==='22023'); // Same group, uninvolved pair.
  await actor(B);
  await assert.rejects(()=>call(randomUUID(),{...command,recipient_user_id:A}),e=>e.code==='22023'); // Debtor cannot nudge creditor.
  await actor(C);
  await assert.rejects(()=>call(randomUUID()),e=>e.code==='22023');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.reminder_operations WHERE actor_id=$1 AND operation_id=$2',[A,operation])).rows[0].n,1);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM public.activity_logs WHERE tab_id=$1 AND event_type='REMINDER_SENT'",[tab])).rows[0].n,1);
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.notifications WHERE id=$1',[original])).rows[0].n,1);
  await db.query("UPDATE public.reminder_operations SET accepted_at=now()-interval '5 hours 59 minutes' WHERE actor_id=$1 AND operation_id=$2",[A,operation]);
  await actor(A);
  await assert.rejects(()=>call(randomUUID()),e=>e.code==='PT429');
  await db.exec('RESET ROLE');
  await db.query("UPDATE public.reminder_operations SET accepted_at=now()-interval '6 hours 1 second' WHERE actor_id=$1 AND operation_id=$2",[A,operation]);
  await actor(A);
  const afterWindow=(await call(randomUUID())).rows[0].id;
  assert.notEqual(afterWindow,original,'new reminder is allowed after the six-hour window');
  await db.exec('RESET ROLE');
  assert.equal((await db.query("SELECT count(*)::int AS n FROM public.notifications WHERE related_tab_id=$1 AND notification_type='manual_nudge'",[tab])).rows[0].n,2);
  await db.query("UPDATE public.tabs SET status='archived' WHERE id=$1",[tab]);
  await actor(A);
  assert.equal((await call(operation)).rows[0].id,original); // Replay even after eligibility changes.
  await assert.rejects(()=>call(randomUUID()),e=>e.code==='42501');
  await db.exec('RESET ROLE');
  for(const role of ['anon','authenticated']) {
    assert.equal((await db.query("SELECT has_table_privilege($1,'public.reminder_operations','select') AS yes",[role])).rows[0].yes,false);
  }
  console.log('REMINDER_ACCEPTANCE_OK: idempotent replay, PT429 six-hour window, expiry, uninvolved group pairs, debtor direction and archive denied.');
};
