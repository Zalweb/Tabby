'use strict';
const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
module.exports=async(db,{actor})=>{
  await db.exec('RESET ROLE');const owner=randomUUID(),friend=randomUUID(),outsider=randomUUID(),tab=randomUUID();
  for(const id of [owner,friend,outsider]) await db.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Canonical fixture name')",[id]);
  await db.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES ($1,$2,'accepted')",[owner,friend]);
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
  for(const id of [owner,friend]) await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,id]);
  const read=async()=>(await db.query('SELECT public.connection_preferences_v1() AS value')).rows[0].value;
  const change=async(op,cmd)=>(await db.query('SELECT public.change_connection_v1($1,$2::jsonb) AS value',[op,JSON.stringify({owner_id:owner,...cmd})])).rows[0].value;
  await actor(owner);
  await db.query('SELECT public.create_expense_v1($1,$2::jsonb)',[randomUUID(),JSON.stringify({p_tab_id:tab,p_description:'Preserved group bill',p_category:'food',p_total_amount_centavos:10000,p_paid_by_user_id:owner,
    p_participants:[{user_id:owner,participant_role:'payer',share_amount_centavos:5000,acknowledged:true},{user_id:friend,participant_role:'debtor',share_amount_centavos:5000,acknowledged:false}],p_due_date:null,p_receipt_url:null})]);
  await actor(friend);
  const payment=(await db.query('SELECT public.submit_payment_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify({p_tab_id:tab,p_submitted_by_user_id:friend,p_recipient_user_id:owner,p_amount_centavos:1000,p_payment_method:'cash',p_note:null})])).rows[0].id;
  await actor(owner);await db.query('SELECT public.confirm_payment($1)',[payment]);
  await db.exec('RESET ROLE');
  const history=async()=>JSON.stringify({expenses:(await db.query('SELECT to_jsonb(t) AS row FROM public.transactions t WHERE tab_id=$1 ORDER BY id',[tab])).rows,
    payments:(await db.query('SELECT to_jsonb(p) AS row FROM public.payments p WHERE tab_id=$1 ORDER BY id',[tab])).rows});
  const originalHistory=await history();
  await actor(owner);const op=randomUUID(),cmd={action:'nickname',target_id:friend,nickname:'Private fixture',expected_revision:0};
  const accepted=await change(op,cmd);assert.equal(accepted.nicknames[friend],'Private fixture');
  assert.deepEqual(await change(op,cmd),accepted);
  await assert.rejects(()=>change(op,{...cmd,nickname:'Changed replay'}),e=>e.code==='22023');
  await assert.rejects(()=>change(randomUUID(),{...cmd,nickname:'Stale'}),e=>e.code==='40001');
  await assert.rejects(()=>change(randomUUID(),{...cmd,expected_revision:1,phone:'forged'}),e=>e.code==='22023');
  const archived=await change(randomUUID(),{action:'archive',target_id:tab,expected_revision:1});
  assert.deepEqual(archived.archived_tab_ids,[tab]);
  await actor(friend);assert.deepEqual(await read(),{revision:0,nicknames:{},archived_tab_ids:[]});
  await actor(outsider);await assert.rejects(()=>change(randomUUID(),{owner_id:outsider,action:'archive',target_id:tab,expected_revision:0}),e=>e.code==='42501');
  await assert.rejects(()=>db.query('SELECT public.update_profile_v2($1,$2::jsonb)',[owner,'{"display_name":"Wrong actor"}']),e=>e.code==='42501');
  await assert.rejects(()=>db.query('SELECT public.remove_friend_v2($1,$2)',[owner,friend]),e=>e.code==='42501');
  await assert.rejects(()=>change(randomUUID(),{action:'archive',target_id:tab,expected_revision:2}),e=>e.code==='42501');
  await assert.rejects(()=>change(randomUUID(),{owner_id:outsider,action:'nickname',target_id:friend,nickname:'Intruder',expected_revision:0}),e=>e.code==='42501');
  await actor(owner);const restored=await change(randomUUID(),{action:'restore',target_id:tab,expected_revision:2});
  assert.deepEqual(restored.archived_tab_ids,[]);
  const unfriend=randomUUID(),remove={action:'unfriend',target_id:friend,expected_revision:3};
  const result=await change(unfriend,remove);assert.deepEqual(await change(unfriend,remove),result);
  await db.exec('RESET ROLE');
  assert.equal(await history(),originalHistory);
  assert.equal((await db.query('SELECT display_name FROM public.users WHERE id=$1',[friend])).rows[0].display_name,'Canonical fixture name');
  assert.equal((await db.query('SELECT status FROM public.tabs WHERE id=$1',[tab])).rows[0].status,'active');
  assert.equal((await db.query('SELECT count(*)::int AS n FROM public.tab_members WHERE tab_id=$1',[tab])).rows[0].n,2);
  assert.equal((await db.query("SELECT count(*)::int AS n FROM public.friendships WHERE requester_id=$1 AND addressee_id=$2 AND status='accepted'",[owner,friend])).rows[0].n,0);
  await actor(owner);for(const table of ['connection_preferences','connection_operations']) {
    await assert.rejects(()=>db.query('SELECT * FROM public.'+table),e=>e.code==='42501');
  }
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1,$2) AS amount',[tab,owner])).rows[0].amount),4000);
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE anon');
  await assert.rejects(()=>read(),e=>e.code==='42501');await db.exec('RESET ROLE');
  console.log('CONNECTION_PREFERENCES_CONTRACT_OK: private owner snapshots, accepted-friend labels, replay/conflict/stale revision denial, archive/restore without shared-tab mutation, unfriend without roster deletion and anonymous/outsider denial passed.');
  return {owner,friend,tab};
};
