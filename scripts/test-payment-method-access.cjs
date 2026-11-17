'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');

// Invoked by both native PostgreSQL and PGlite runners with source migrations.
module.exports=async function testPaymentMethodAccess(db,{actor,call,expense}) {
  const [owner,friend,debtor,bystander,pending,stranger]=Array.from({length:6},randomUUID);
  const tab=randomUUID(),method=randomUUID(),image=owner+'/receiving.png';
  await db.exec('RESET ROLE');
  for(const id of [owner,friend,debtor,bystander,pending,stranger])
    await db.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Synthetic QR account')",[id]);
  await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
  for(const id of [owner,debtor,bystander])
    await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[tab,id]);
  await db.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES ($1,$2,'accepted'),($1,$3,'pending')",[owner,friend,pending]);
  await db.query("INSERT INTO public.payment_methods(id,owner_user_id,provider,display_name,qr_storage_path,is_default) VALUES ($1,$2,'other','Synthetic QR',$3,true)",[method,owner,image]);
  for(const name of [image,owner+'/unbound.png'])
    await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('payment-methods',$1)",[name]);
  await actor(owner);
  await call('create_expense_v1',randomUUID(),{...expense,p_tab_id:tab,p_paid_by_user_id:owner,
    p_participants:[{user_id:owner,participant_role:'payer',share_amount_centavos:5000},
      {user_id:debtor,participant_role:'debtor',share_amount_centavos:5000},
      {user_id:bystander,participant_role:'debtor',share_amount_centavos:0}]});
  // Debtor's aggregate is zero, but the direct pair still owes the owner.
  await actor(debtor);
  await call('create_expense_v1',randomUUID(),{...expense,p_tab_id:tab,p_paid_by_user_id:debtor,
    p_participants:[{user_id:debtor,participant_role:'payer',share_amount_centavos:5000},
      {user_id:bystander,participant_role:'debtor',share_amount_centavos:5000}]});
  assert.equal(Number((await db.query('SELECT public.get_net_balance($1,$2) AS n',[tab,debtor])).rows[0].n),0);
  const row=async()=> (await db.query('SELECT id FROM public.payment_methods WHERE id=$1',[method])).rows.length;
  const file=async(name=image)=> (await db.query("SELECT id FROM storage.objects WHERE bucket_id='payment-methods' AND name=$1",[name])).rows.length;
  const listed=async()=> (await db.query('SELECT id FROM public.list_payment_methods_for_tab($1,$2)',[tab,owner])).rows.length;
  for(const id of [owner,friend,debtor]) {
    await actor(id); assert.equal(await row(),1); assert.equal(await file(),1);
    assert.equal(await file(owner+'/unbound.png'),0);
    assert.equal(await file(owner+'/guessed.png'),0);
  }
  await actor(debtor); assert.equal(await listed(),1);
  for(const id of [bystander,pending,stranger]) {
    await actor(id); assert.equal(await row(),0); assert.equal(await file(),0);
    assert.equal(await listed(),0);
    assert.equal((await db.query('SELECT public.can_read_payment_method($1) AS allowed',[method])).rows[0].allowed,false);
  }
  await actor(debtor);
  const payment=await call('submit_payment_v1',randomUUID(),{p_tab_id:tab,
    p_submitted_by_user_id:debtor,p_recipient_user_id:owner,p_amount_centavos:5000,p_payment_method:'cash',p_note:null});
  await actor(owner); await db.query('SELECT public.confirm_payment($1)',[payment]);
  await actor(debtor); assert.equal(await listed(),0); assert.equal(await row(),0); assert.equal(await file(),0);
  await actor(friend); assert.equal(await row(),1); assert.equal(await file(),1);
  await db.exec('RESET ROLE');
  await db.query('UPDATE public.payment_methods SET is_active=false WHERE id=$1',[method]);
  await actor(friend); assert.equal(await row(),0); assert.equal(await file(),0);
  await db.exec('RESET ROLE'); await db.exec('SET ROLE anon');
  await assert.rejects(()=>db.query('SELECT public.can_read_payment_method($1)',[method]),e=>e.code==='42501');
  assert.equal(await file(),0);
  await db.exec('RESET ROLE');
  console.log('PAYMENT_METHOD_ACCESS_OK: owner, accepted friend and actual zero-aggregate group debtor can read exact active objects; uninvolved member, pending friend, stranger, anonymous and guessed/unbound paths denied; settlement and removal revoke new access.');
};
