'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
module.exports=async(db,{actor})=>{
  await db.exec('RESET ROLE');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261102000009_custom_splits.sql'),'utf8'));
  const owner='a0000000-0000-4000-8000-000000000001',peer='a0000000-0000-4000-8000-000000000002',outsider='a0000000-0000-4000-8000-000000000003',tab=randomUUID();
  for(const id of [owner,peer,outsider])await db.query("INSERT INTO auth.users(id,raw_user_meta_data) VALUES($1,'{\"display_name\":\"Synthetic M2 user\"}')",[id]);
  await db.query('INSERT INTO public.tabs(id,user_a,user_b) VALUES($1,$2,$3)',[tab,owner,peer]);
  const command={p_expected_actor:owner,p_tab_id:tab,p_description:'Custom fixture',p_category:'food',
    p_total_amount_centavos:12201,p_paid_by_user_id:owner,p_due_date:null,p_receipt_url:null,
    p_participants:[{user_id:owner,participant_role:'payer',share_amount_centavos:6100,acknowledged:false},
      {user_id:peer,participant_role:'debtor',share_amount_centavos:6101,acknowledged:false}],
    split:{base_centavos:10001,tax_basis_points:1200,service_basis_points:1000,
      base_shares:[{party:{kind:'user',id:owner},amount:5000},{party:{kind:'user',id:peer},amount:5001}]}};
  const create=async(op,c=command)=>(await db.query('SELECT public.create_expense_v3($1,$2) id',[op,c])).rows[0].id;
  await actor(owner);
  await assert.rejects(create(randomUUID()),e=>e.code==='42501');
  await db.exec('RESET ROLE');await db.exec("UPDATE public.m2_feature_flags SET enabled=true WHERE feature='custom_splits'");
  await actor(owner);const op=randomUUID();const id=await create(op);assert.equal(await create(op),id);
  await assert.rejects(create(op,{...command,p_description:'Different'}),e=>e.code==='22023');
  await assert.rejects(create(randomUUID(),{...command,p_expected_actor:peer}),e=>e.code==='42501');
  for(const split of [{...command.split,tax_basis_points:10001},{...command.split,service_basis_points:-1},
    {...command.split,base_centavos:1},{...command.split,base_shares:[command.split.base_shares[0],command.split.base_shares[0]]}]) {
    await assert.rejects(create(randomUUID(),{...command,split}),e=>e.code==='22023');
  }
  const row=(await db.query('SELECT breakdown FROM public.expense_split_details WHERE transaction_id=$1',[id])).rows[0];
  assert.equal(row.breakdown.tax_centavos,1200);assert.equal(row.breakdown.service_centavos,1000);
  await actor(outsider);assert.equal((await db.query('SELECT * FROM public.expense_split_details WHERE transaction_id=$1',[id])).rows.length,0);
  await assert.rejects(create(randomUUID(),{...command,p_expected_actor:outsider}),e=>e.code==='42501');
  await actor(peer);assert.equal((await db.query('SELECT breakdown FROM public.expense_split_details WHERE transaction_id=$1',[id])).rows.length,1);
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT count(*)::int n FROM public.transactions WHERE id=$1',[id])).rows[0].n,1);
  const allocated=(await db.query('SELECT user_id,share_amount_centavos FROM public.transaction_participants WHERE transaction_id=$1 ORDER BY user_id',[id])).rows;
  assert.equal(String(allocated[0].share_amount_centavos),'6100');assert.equal(String(allocated[1].share_amount_centavos),'6101');
  const zero={...command,p_total_amount_centavos:3,p_participants:[
    {user_id:owner,participant_role:'payer',share_amount_centavos:0,acknowledged:false},
    {user_id:peer,participant_role:'debtor',share_amount_centavos:3,acknowledged:false}],
    split:{base_centavos:1,tax_basis_points:5000,service_basis_points:5000,
      base_shares:[{party:{kind:'user',id:owner},amount:0},{party:{kind:'user',id:peer},amount:1}]}};
  await actor(owner);await create(randomUUID(),zero);
  await db.exec('RESET ROLE');
  const group=randomUUID(),groupTab=randomUUID();
  await db.query("INSERT INTO public.groups(id,name,created_by) VALUES($1,'Synthetic split group',$2)",[group,owner]);
  await db.query("INSERT INTO public.group_members(group_id,user_id,status) VALUES($1,$2,'active'),($1,$3,'active'),($1,$4,'active')",[group,owner,peer,outsider]);
  await db.query("INSERT INTO public.tabs(id,tab_type,group_id) VALUES($1,'group',$2)",[groupTab,group]);
  await actor(owner);
  const groupCommand={...command,p_tab_id:groupTab,
    split:{...command.split,base_shares:[{party:{kind:'user',id:owner},amount:3333},
      {party:{kind:'user',id:peer},amount:6668},{party:{kind:'user',id:outsider},amount:0}]}};
  for(const payer of [owner,peer,outsider]){
    const c={...groupCommand,p_paid_by_user_id:payer,p_participants:[
      {user_id:owner,share_amount_centavos:4066},{user_id:peer,share_amount_centavos:8135},{user_id:outsider,share_amount_centavos:0}]
      .map(p=>({...p,participant_role:p.user_id===payer?'payer':'debtor',acknowledged:false}))};
    await create(randomUUID(),c);
  }
  await db.exec('RESET ROLE');
  await db.query("UPDATE public.group_members SET status='left' WHERE group_id=$1 AND user_id=$2",[group,outsider]);
  // A legacy durable tab membership must not grant new obligations after leaving.
  await db.query("INSERT INTO public.tab_members(tab_id,user_id,role) VALUES($1,$2,'participant')",[groupTab,outsider]);
  await actor(owner);
  const fresh={...groupCommand,p_participants:[
    {user_id:owner,participant_role:'payer',share_amount_centavos:4066,acknowledged:false},
    {user_id:peer,participant_role:'debtor',share_amount_centavos:8135,acknowledged:false},
    {user_id:outsider,participant_role:'debtor',share_amount_centavos:0,acknowledged:false}]};
  await assert.rejects(create(randomUUID(),fresh),e=>e.code==='42501');
  await assert.rejects(db.query('SELECT public.create_expense_v1($1,$2)',[randomUUID(),fresh]),e=>e.code==='42501');
  console.log('M2_CUSTOM_SPLIT_OK: rollout denial, independent integer charges, odd-cent/zero allocations, persisted breakdown, replay/conflict and role isolation passed. Local source only.');
  const recurrence=await require('./test-recurring-obligations.cjs')(db,{actor,owner,peer,tab,command});
  const claim=await require('./test-contact-claims.cjs')(db,{actor,owner,peer,outsider});
  const review=await require('./test-expense-review.cjs')(db,{actor,owner,peer,outsider,tab,command});
  return {owner,peer,outsider,tab,command,recurrence,claim,review};
};
