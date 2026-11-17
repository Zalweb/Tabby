'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
module.exports=async(db,{actor,owner,peer,outsider})=>{
 await db.exec('RESET ROLE');await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261102000011_explicit_contact_claims.sql'),'utf8').replace(/^\uFEFF/,''));
 const call=async(name,args)=>(await db.query(`SELECT public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) data`,args)).rows[0].data;
 async function source(amount=5001,contactPays=false){
  const contact=randomUUID();await actor(owner);const tab=(await call('resolve_contact_tab_v1',[contact,'Synthetic contact'])).tab_id;
  const command={p_tab_id:tab,p_description:'Retained original',p_category:'food',p_total_amount_centavos:amount,p_paid_by_user_id:contactPays?contact:owner,
   p_due_date:null,p_receipt_url:null,p_participants:[{user_id:owner,participant_role:contactPays?'debtor':'payer',share_amount_centavos:contactPays?amount:0},
    {contact_id:contact,participant_role:contactPays?'payer':'debtor',share_amount_centavos:contactPays?0:amount}]};
  const original=await call('create_expense_v1',[randomUUID(),command]);return {contact,tab,command,original};
 }
 async function invite(s){await actor(owner);const snapshot=(await call('contact_claim_preview_v1',[s.contact,s.tab])).snapshot;
  const command={p_expected_actor:owner,claim_id:randomUUID(),contact_id:s.contact,target_id:peer,source_tab_id:s.tab,snapshot_digest:snapshot.digest};
  const op=randomUUID(),id=await call('invite_contact_claim_v1',[op,command]);assert.equal(await call('invite_contact_claim_v1',[op,command]),id);
  return {id,command,snapshot};}
 const s=await source();const snapshot=(await call('contact_claim_preview_v1',[s.contact,s.tab])).snapshot;
 await assert.rejects(call('invite_contact_claim_v1',[randomUUID(),{p_expected_actor:owner,claim_id:randomUUID(),contact_id:s.contact,target_id:peer,source_tab_id:s.tab,snapshot_digest:snapshot.digest}]),e=>e.code==='42501');
 await db.exec('RESET ROLE');await db.exec("UPDATE public.m2_feature_flags SET enabled=true WHERE feature='contact_claiming'");
 const c=await invite(s),decision={p_expected_actor:peer,claim_id:c.id,accept:false,snapshot_digest:c.snapshot.digest};
 await actor(outsider);await assert.rejects(call('decide_contact_claim_v1',[randomUUID(),{...decision,p_expected_actor:outsider}]),e=>e.code==='42501');
 await assert.rejects(call('contact_claim_history_page_v1',[c.id]),e=>e.code==='42501');
 await actor(peer);assert.equal((await call('contact_claim_history_page_v1',[c.id])).records[0].id,s.original);
 await call('decide_contact_claim_v1',[randomUUID(),decision]);
 await db.exec('RESET ROLE');assert.equal((await db.query('SELECT claimed_user_id FROM public.contacts WHERE id=$1',[s.contact])).rows[0].claimed_user_id,null);
 assert.equal((await db.query('SELECT count(*)::int n FROM public.transactions WHERE tab_id=$1',[s.tab])).rows[0].n,1);
 const destBefore=(await db.query("SELECT id FROM public.tabs WHERE tab_type='individual' AND status='active' AND least(user_a,user_b)=least($1::uuid,$2::uuid) AND greatest(user_a,user_b)=greatest($1::uuid,$2::uuid)",[owner,peer])).rows[0].id;
 const before=Number(await call('get_party_outstanding_internal',[destBefore,'user',peer,'user',owner]))-Number(await call('get_party_outstanding_internal',[destBefore,'user',owner,'user',peer]));
 const originalBefore=(await db.query('SELECT to_jsonb(t) data FROM public.transactions t WHERE id=$1',[s.original])).rows[0].data;
 const accepted=await invite(s);await actor(peer);const accept={...decision,claim_id:accepted.id,accept:true,snapshot_digest:accepted.snapshot.digest};
 const result=await call('decide_contact_claim_v1',[randomUUID(),accept]);assert.equal(await call('decide_contact_claim_v1',[randomUUID(),accept]),result);
 await assert.rejects(call('decide_contact_claim_v1',[randomUUID(),{...accept,accept:false}]),e=>e.code==='22023');
 assert.equal(await call('is_tab_member',[s.tab,peer]),true);
 await db.exec('RESET ROLE');const row=(await db.query('SELECT * FROM public.contact_claim_invitations WHERE id=$1',[result])).rows[0];
 assert.equal(row.status,'accepted');assert(row.reverse_id&&row.transfer_id&&row.destination_tab_id);
 assert.equal((await db.query('SELECT contact_id FROM public.transaction_participants WHERE transaction_id=$1 AND contact_id IS NOT NULL',[s.original])).rows[0].contact_id,s.contact);
 assert.equal((await db.query('SELECT count(*)::int n FROM public.transaction_participants WHERE transaction_id=$1 AND user_id=$2',[s.original,peer])).rows[0].n,0);
 assert.equal(Number(await call('get_party_outstanding_internal',[s.tab,'contact',s.contact,'user',owner])),0);
 const after=Number(await call('get_party_outstanding_internal',[row.destination_tab_id,'user',peer,'user',owner]))-Number(await call('get_party_outstanding_internal',[row.destination_tab_id,'user',owner,'user',peer]));
 assert.equal(after-before,5001);
 assert.deepEqual((await db.query('SELECT to_jsonb(t) data FROM public.transactions t WHERE id=$1',[s.original])).rows[0].data,originalBefore);
 await actor(owner);await assert.rejects(call('create_expense_v1',[randomUUID(),s.command]),e=>e.code==='42501');
 await assert.rejects(call('claim_contact',[s.contact,peer]),e=>e.code==='42501');
 await assert.rejects(db.query("UPDATE public.contacts SET claimed_user_id=NULL,claim_status='unclaimed' WHERE id=$1",[s.contact]),e=>e.code==='42501');
 const stale=await source();const staleInvite=await invite(stale);await call('create_expense_v1',[randomUUID(),stale.command]);await actor(peer);
 await assert.rejects(call('decide_contact_claim_v1',[randomUUID(),{...accept,claim_id:staleInvite.id,snapshot_digest:staleInvite.snapshot.digest}]),e=>e.code==='40001');
 const reverse=await source(3001,true),reverseInvite=await invite(reverse);await actor(peer);
 await call('decide_contact_claim_v1',[randomUUID(),{...accept,claim_id:reverseInvite.id,snapshot_digest:reverseInvite.snapshot.digest}]);
 const race=await source(2001);const raceInvite=await invite(race);
 await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");
 console.log('CONTACT_CLAIM_CONTRACT_OK: disabled rollout, explicit target consent, decline no financial/identity change, stale/foreign denial, original contact references retained, both transfer directions, replay and old-write denial passed.');
 return {owner,peer,claim:raceInvite.id,digest:raceInvite.snapshot.digest,source:race};
};
