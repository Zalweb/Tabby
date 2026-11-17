'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
module.exports=async function(db,{actor,expense}) {
 const [a,b,c,d,tab]=Array.from({length:5},randomUUID);
 await db.exec('RESET ROLE');
 await db.query("INSERT INTO public.users(id,display_name) SELECT v,'Revision member' FROM unnest($1::uuid[]) v",[[a,b,c,d]]);
 await db.query("INSERT INTO public.tabs(id,tab_type) VALUES ($1,'group')",[tab]);
 await db.query('INSERT INTO public.tab_members(tab_id,user_id) SELECT $1,v FROM unnest($2::uuid[]) v',[tab,[a,b,c,d]]);
 const command={...expense,p_tab_id:tab,p_description:'Group original',p_total_amount_centavos:10001,p_paid_by_user_id:a,
   p_participants:[{user_id:a,participant_role:'payer',share_amount_centavos:3401},
     {user_id:b,participant_role:'debtor',share_amount_centavos:3300},
     {user_id:c,participant_role:'debtor',share_amount_centavos:3300}]};
 const create=async()=>{await actor(a);return (await db.query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify(command)])).rows[0].id;};
 const propose=async(source,owner,total=7001,contact=false,kind='correct',op=randomUUID())=>
   (await db.query('SELECT public.request_expense_change_v2($1,$2,$3,$4,$5,$6,$7) AS id',[op,source,kind,total,'Agreed correction',owner,contact])).rows[0].id;
 const decide=async(id,owner,accept=true)=>(await db.query('SELECT public.decide_expense_change_v1($1,$2,$3) AS id',[id,accept,owner])).rows[0].id;
 const list=async source=>(await db.query('SELECT public.list_expense_changes_v1($1) AS value',[source])).rows[0].value;
 const balance=async target=>Number((await db.query('SELECT public.get_net_balance($1,$2) AS n',[target, (await db.query('SELECT auth.uid() AS id')).rows[0].id])).rows[0].n);
 const source=await create();
 await db.exec('RESET ROLE');
 const original=(await db.query('SELECT to_jsonb(t) AS value FROM public.transactions t WHERE id=$1',[source])).rows[0].value;
 const reminder=randomUUID(),installation=randomUUID(),binding=randomUUID(),notification=randomUUID();
 await db.query("INSERT INTO public.reminders(id,transaction_id,created_by,recipient_user_id,reminder_type,scheduled_for) VALUES($1,$2,$3,$4,'before_due',now()+interval '1 day')",[reminder,source,a,b]);
 await actor(b);await db.query('SELECT public.register_push_device_v1($1,$2,$3,true)',[installation,binding,'synthetic-group-contact-push-token']);
 await db.exec('RESET ROLE');
 await db.query("INSERT INTO public.notifications(id,recipient_user_id,notification_type,related_tab_id,related_transaction_id,title,body) VALUES($1,$2,'manual_nudge',$3,$4,'Synthetic reminder','Synthetic')",[notification,b,tab,source]);
 await actor(a);
 await assert.rejects(propose(source,a,7001,true),e=>e.code==='22023');
 const change=await propose(source,a);
 await actor(b);await decide(change,b);
 assert.equal(await balance(tab),-3300);
 assert.equal((await list(source)).changes[0].accepted_reviewers,1);
 assert.equal((await list(source)).changes[0].status,'pending');
 await db.exec('RESET ROLE');
 assert.equal((await db.query('SELECT status FROM public.reminders WHERE id=$1',[reminder])).rows[0].status,'scheduled');
 await actor(c);await decide(change,c);
 assert.equal(await balance(tab),-2310);
 const applied=(await list(source)).changes[0];
 assert.equal(applied.status,'applied');assert.equal(applied.accepted_reviewers,2);
 assert.equal(applied.reversal_ids.length,2);
 await db.exec('RESET ROLE');
 assert.deepEqual((await db.query('SELECT to_jsonb(t) AS value FROM public.transactions t WHERE id=$1',[source])).rows[0].value,original);
 assert.equal((await db.query('SELECT status FROM public.reminders WHERE id=$1',[reminder])).rows[0].status,'cancelled');
 assert.equal((await db.query('SELECT status FROM public.push_delivery_jobs WHERE notification_id=$1',[notification])).rows[0].status,'cancelled');
 await actor(a);assert.equal(await balance(tab),4620);
 const ref=async(id,fakeTab=null)=>(await db.query('SELECT public.expense_revision(jsonb_populate_record(NULL::public.transactions,$1::jsonb)) AS value',[JSON.stringify({id,tab_id:fakeTab})])).rows[0].value;
 assert.equal((await ref(source)).role,'original');
 assert.equal((await ref(applied.replacement_id)).role,'replacement');
 await actor(d);assert.equal(await ref(source,tab),null);
 await assert.rejects(list(source),e=>e.code==='42501');
 await assert.rejects(decide(change,d),e=>e.code==='42501');

 const rejectedSource=await create(),rejected=await propose(rejectedSource,a);
 await actor(b);await decide(rejected,b);
 await actor(c);await decide(rejected,c,false);
 assert.equal((await list(rejectedSource)).changes[0].status,'rejected');
 assert.equal(await balance(tab),-5610); // previous 2310 + unchanged new 3300

 for(const contactPays of [false,true]) {
   const contact=randomUUID(),contactTab=randomUUID();
   await db.exec('RESET ROLE');
   await db.query("INSERT INTO public.contacts(id,owner_user_id,display_name) VALUES($1,$2,'Manual member')",[contact,a]);
   await db.query('INSERT INTO public.tabs(id,user_a) VALUES($1,$2)',[contactTab,a]);
   await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES($1,$2)',[contactTab,a]);
   await db.query('INSERT INTO public.tab_members(tab_id,contact_id) VALUES($1,$2)',[contactTab,contact]);
   await actor(a);
   const payer=contactPays?{contact_id:contact}:{user_id:a},debtor=contactPays?{user_id:a}:{contact_id:contact};
   const contactCommand={...command,p_tab_id:contactTab,p_paid_by_user_id:contactPays?contact:a,p_participants:[
     {...payer,participant_role:'payer',share_amount_centavos:5000},{...debtor,participant_role:'debtor',share_amount_centavos:5001}]};
   const id=(await db.query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify(contactCommand)])).rows[0].id;
   await assert.rejects(propose(id,a),e=>e.code==='22023');
   const op=randomUUID(),accepted=await propose(id,a,7001,true,'correct',op);
   assert.equal(await propose(id,a,7001,true,'correct',op),accepted);
   assert.equal(await balance(contactTab),contactPays?-3500:3500);
   const result=(await list(id)).changes[0];
   assert.equal(result.status,'applied');assert.equal(result.manual_contact_agreement,true);assert.equal(result.required_reviewers,0);
   assert.equal((await ref(result.replacement_id)).role,'replacement');
   const cancelled=await propose(result.replacement_id,a,null,true,'cancel');
   assert.equal((await list(result.replacement_id)).changes[0].id,cancelled);
   assert.equal(await balance(contactTab),0);
   const unreviewed=(await db.query('SELECT public.create_expense_v1($1,$2::jsonb) AS id',[randomUUID(),JSON.stringify(contactCommand)])).rows[0].id;
   await db.exec('RESET ROLE');
   await db.query("UPDATE public.contacts SET claimed_user_id=$1,claim_status='claimed' WHERE id=$2",[b,contact]);
   await actor(a);await assert.rejects(propose(unreviewed,a,7001,true),e=>e.code==='22023');
   await actor(b);await assert.rejects(propose(id,b,7001,true),e=>e.code==='42501');
 }
 const concurrentSource=await create(),first=await propose(concurrentSource,a,8001);
 await actor(b);const second=await propose(concurrentSource,b,9001);await decide(first,b);
 await actor(a);await decide(second,a);
 console.log('GROUP_CONTACT_CHANGE_OK: unanimous registered approval, no partial/rejected balance change, all reversal references, stale reminder/job retirement, private projection and explicit owner-attested contact corrections in both payer directions passed.');
 return {reviewer:c,source:concurrentSource,proposals:[first,second]};
};
