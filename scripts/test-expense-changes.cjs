'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');

module.exports=async function(db,{actor,expense}) {
 const a=randomUUID(),b=randomUUID(),tab=randomUUID();
 await db.exec('RESET ROLE');
 await db.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Change A'),($2,'Change B')",[a,b]);
 await db.query('INSERT INTO public.tabs(id,user_a,user_b) VALUES ($1,$2,$3)',[tab,a,b]);
 await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2),($1,$3)',[tab,a,b]);
 const command={...expense,p_tab_id:tab,p_description:'Original fixture',p_total_amount_centavos:10001,
   p_paid_by_user_id:a,p_participants:[
     {user_id:a,participant_role:'payer',share_amount_centavos:5000},
     {user_id:b,participant_role:'debtor',share_amount_centavos:5001}]};
 async function create(){await actor(a);return (await db.query('SELECT public.create_expense_v1($1,$2) AS id',[randomUUID(),JSON.stringify(command)])).rows[0].id;}
 async function request(source,kind='correct',total=7001,reason='Wrong amount',op=randomUUID(),expected=a) {
   return (await db.query('SELECT public.request_expense_change_v1($1,$2,$3,$4,$5,$6) AS id',[op,source,kind,total,reason,expected])).rows[0].id;
 }
 const decide=async(id,accept=true,expected=b)=>(await db.query('SELECT public.decide_expense_change_v1($1,$2,$3) AS id',[id,accept,expected])).rows[0].id;
 const list=async id=>(await db.query('SELECT public.list_expense_changes_v1($1) AS data',[id])).rows[0].data;
 const balance=async()=>{const row=(await db.query('SELECT public.get_net_balance($1,auth.uid()) AS n,auth.uid() AS actor',[tab])).rows[0];return Number(row.n)*(row.actor===a?1:-1)||0;};
 const source=await create();
 await actor(b);
 const payment=(await db.query('SELECT public.submit_payment_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify({
   p_tab_id:tab,p_submitted_by_user_id:b,p_recipient_user_id:a,p_amount_centavos:1000,p_payment_method:'gcash',p_note:'Confirmed original payment'})])).rows[0].id;
 await actor(a);await db.query('SELECT public.confirm_payment($1)',[payment]);
 await db.exec('RESET ROLE');
 const paymentBefore=(await db.query('SELECT to_jsonb(p) AS row FROM public.payments p WHERE id=$1',[payment])).rows[0].row;
 const before=(await db.query('SELECT to_jsonb(t) AS row FROM public.transactions t WHERE id=$1',[source])).rows[0].row;
 const shares=(await db.query('SELECT to_jsonb(s) AS row FROM public.transaction_participants s WHERE transaction_id=$1 ORDER BY id',[source])).rows;
 await actor(a);
 const op=randomUUID(),change=await request(source,'correct',7001,'Wrong amount',op);
 assert.equal(await request(source,'correct',7001,'Wrong amount',op),change);
 await assert.rejects(request(source,'correct',9000,'Wrong amount',op),e=>e.code==='22023');
 assert.equal(await balance(),4001);
 assert.equal((await list(source)).changes[0].status,'pending');
 await assert.rejects(decide(change,true,a),e=>e.code==='42501');
 await actor(b);
 await assert.rejects(request(source),e=>e.code==='42501');
 await assert.rejects(decide(change,true,a),e=>e.code==='42501');
 assert.equal((await list(source)).changes[0].reason,'Wrong amount');
 assert.equal(await decide(change),change);
 assert.equal(await decide(change),change);
 await assert.rejects(decide(change,false),e=>e.code==='22023');
 // floor(7001 * 5001 / 10001) = 3500, payer receives remainder.
 assert.equal(await balance(),2500);
 const result=(await list(source)).changes[0];
 assert.equal(result.status,'applied');
 assert.ok(result.reversal_id);assert.ok(result.replacement_id);
 await db.exec('RESET ROLE');
 assert.deepEqual((await db.query('SELECT to_jsonb(t) AS row FROM public.transactions t WHERE id=$1',[source])).rows[0].row,before);
 assert.deepEqual((await db.query('SELECT to_jsonb(s) AS row FROM public.transaction_participants s WHERE transaction_id=$1 ORDER BY id',[source])).rows,shares);
 assert.equal((await db.query('SELECT count(*)::int AS n FROM public.transactions WHERE tab_id=$1',[tab])).rows[0].n,3);
 await actor(a);
 await assert.rejects(request(result.reversal_id,'cancel',null),e=>e.code==='22023');
 const cancel=await request(result.replacement_id,'cancel',null,'Entered by mistake');
 await actor(b);await decide(cancel);
 assert.equal(await balance(),-1000);
 await db.exec('RESET ROLE');
 const cancelled=(await db.query('SELECT id,total_amount_centavos,status FROM public.transactions WHERE id=$1',[result.replacement_id])).rows[0];
 assert.equal(cancelled.id,result.replacement_id);
 assert.equal(Number(cancelled.total_amount_centavos),7001,
   'ADR-006 cancellation retains the original amount');
 assert.equal(cancelled.status,'cancelled',
   'ADR-006 cancellation changes status while retaining the original row');
 assert.equal((await db.query("SELECT count(*)::int AS n FROM public.activity_logs WHERE transaction_id=$1 AND event_type='EXPENSE_CHANGE_APPLIED' AND metadata->>'reason'='Entered by mistake'",[result.replacement_id])).rows[0].n,1);
 assert.deepEqual((await db.query('SELECT to_jsonb(p) AS row FROM public.payments p WHERE id=$1',[payment])).rows[0].row,paymentBefore);
 await actor(b);
 await assert.rejects(db.query('DELETE FROM public.expense_change_requests'),e=>e.code==='42501');
 await assert.rejects(db.query('UPDATE public.transactions SET total_amount_centavos=1 WHERE id=$1',[source]),e=>e.code==='42501');
 const rejectedSource=await create();
 const rejected=await request(rejectedSource,'cancel',null,'Duplicate');
 await actor(b);await decide(rejected,false);
 assert.equal((await list(rejectedSource)).changes[0].status,'rejected');
 assert.equal(await balance(),4001);
 await actor(a);
 const competing1=await request(rejectedSource,'correct',6001,'Option one');
 const competing2=await request(rejectedSource,'correct',8001,'Option two');
 await actor(b);await decide(competing1);
 await assert.rejects(decide(competing2),e=>e.code==='22023');
 assert.equal((await list(rejectedSource)).changes.find(r=>r.id===competing2).status,'superseded');
 const staleSource=await create(),stale=await request(staleSource);
 await db.exec('RESET ROLE');
 await db.query("UPDATE public.transactions SET description='Administrative repair' WHERE id=$1",[staleSource]);
 await actor(b);await assert.rejects(decide(stale),e=>e.code==='22023');
 await actor(a);
 await assert.rejects(request(staleSource,'correct',0),e=>e.code==='22023');
 await assert.rejects(request(staleSource,'correct',10001),e=>e.code==='22023');
 await assert.rejects(request(staleSource,'cancel',null,' '),e=>e.code==='22023');
 await db.exec('RESET ROLE');
 const groupTab=randomUUID();
 await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[groupTab]);
 await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2),($1,$3)',[groupTab,a,b]);
 await actor(a);
 const groupSource=(await db.query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify({...command,p_tab_id:groupTab})])).rows[0].id;
 assert.ok(await request(groupSource));
 assert.equal((await list(groupSource)).can_request,true);
 await db.exec('RESET ROLE');
 const contact=randomUUID(),contactTab=randomUUID();
 await db.query("INSERT INTO public.contacts(id,owner_user_id,display_name) VALUES ($1,$2,'Manual contact')",[contact,a]);
 await db.query('INSERT INTO public.tabs(id,user_a) VALUES ($1,$2)',[contactTab,a]);
 await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2)',[contactTab,a]);
 await db.query('INSERT INTO public.tab_members(tab_id,contact_id) VALUES ($1,$2)',[contactTab,contact]);
 await actor(a);
 const contactSource=(await db.query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify({...command,p_tab_id:contactTab,
   p_participants:[command.p_participants[0],{contact_id:contact,participant_role:'debtor',share_amount_centavos:5001}]})])).rows[0].id;
 await assert.rejects(request(contactSource),e=>e.code==='22023');
 assert.equal((await list(contactSource)).can_request,true);
 assert.equal((await list(contactSource)).manual_contact,true);
 await db.exec('RESET ROLE; SET ROLE anon');
 await assert.rejects(list(source),e=>e.code==='42501');
 await assert.rejects(decide(change),e=>e.code==='42501');
 await actor('00000000-0000-4000-8000-000000000003');
 await assert.rejects(list(source),e=>e.code==='42501');
 await assert.rejects(request(source),e=>e.code==='42501');
 const concurrentSource=await create();
 console.log('EXPENSE_CHANGE_OK: replay/conflict, counterpart consent, odd-cent replay, cancellation with retained confirmed payment/refund obligation, immutable originals, stale/competing decisions, missing manual agreement/cross-account denial and authorization passed.');
 return {A:a,B:b,tab,source:concurrentSource,command};
};
