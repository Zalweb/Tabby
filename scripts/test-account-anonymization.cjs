'use strict';
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
module.exports=async(db,{actor,A,expense})=>{
  await db.exec('RESET ROLE');
  await db.exec(`ALTER TABLE auth.users ADD COLUMN deleted_at timestamptz;
    CREATE TABLE auth.sessions(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES auth.users(id));
    CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS
      $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
    CREATE ROLE authenticator;
    ALTER TABLE public.users ADD CONSTRAINT privacy_fixture_auth_fk FOREIGN KEY(id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;
    CREATE TRIGGER fixture_auth_sync AFTER INSERT OR UPDATE OF email,phone,raw_user_meta_data ON auth.users
      FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();`);
  for(const file of ['20261102000001_private_account_export.sql','20261102000002_account_deletion_requests.sql',
    '20261102000003_private_ledger_export_pages.sql','20261102000008_reviewed_account_anonymization.sql']) {
    const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations',file),'utf8');
    if(file.includes('000008_')) {
      const snapshot=fs.readFileSync(path.join(__dirname,'../supabase/schema_all.sql'),'utf8').replace(/\r\n/g,'\n');
      const marker='-- SEC-005 reviewed privacy processing\n';
      const start=snapshot.indexOf(marker)+marker.length,source=sql.replace(/\r\n/g,'\n');
      assert.equal(snapshot.slice(start,start+source.length),source);
      await db.exec("ALTER ROLE authenticator SET pgrst.db_pre_request='public.existing_hook'");
      await assert.rejects(db.exec(sql),e=>e.message.includes('Compose existing pre-request hook'));
      await db.exec('ROLLBACK');
      assert.equal((await db.query("SELECT count(*)::int n FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='anonymized_at'")).rows[0].n,0);
      await db.exec('ALTER ROLE authenticator RESET pgrst.db_pre_request');
    }
    await db.exec(sql);
  }
  const owner='94000000-0000-4000-8000-000000000001',tab=randomUUID(),method=randomUUID();
  const proof=owner+'/shared-proof.png',avatar=owner+'/private-avatar.png',qr=owner+'/private-qr.png';
  await db.query("INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES($1,'privacy-fixture@example.invalid','{\"display_name\":\"Private fixture\"}')",[owner]);
  await db.query('INSERT INTO auth.sessions(user_id) VALUES($1)',[owner]);
  await db.query('INSERT INTO public.tabs(id,user_a,user_b) VALUES($1,$2,$3)',[tab,owner,A]);
  await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES('payment-proofs',$1),('profile-avatars',$2),('payment-methods',$3)",[proof,avatar,qr]);
  await db.query("INSERT INTO public.contacts(owner_user_id,display_name,email) VALUES($1,'Private contact','private@example.invalid')",[owner]);
  await db.query("INSERT INTO public.payment_methods(id,owner_user_id,provider,display_name,account_label,qr_storage_path) VALUES($1,$2,'Fixture','Private method','Private account',$3)",[method,owner,qr]);
  await db.query('INSERT INTO public.payment_method_revisions(method_id,owner_user_id,revision,snapshot) SELECT id,owner_user_id,1,to_jsonb(p) FROM public.payment_methods p WHERE id=$1',[method]);
  await db.query("INSERT INTO public.connection_preferences(owner_id,nicknames) VALUES($1,'{\"private\":\"Private nickname\"}')",[owner]);
  const call=async(name,params)=>(await db.query(`SELECT public.${name}(${params.map((_,i)=>'$'+(i+1)).join(',')}) data`,params)).rows[0].data;
  await actor(owner);
  const command={...expense,p_tab_id:tab,p_paid_by_user_id:owner,p_receipt_url:proof,p_participants:[
    {user_id:owner,participant_role:'payer',share_amount_centavos:5000,acknowledged:true},
    {user_id:A,participant_role:'debtor',share_amount_centavos:5000,acknowledged:false}]};
  await call('create_expense_v1',[randomUUID(),command]);
  await actor(A);
  const payment=await call('submit_payment_v1',[randomUUID(),{p_tab_id:tab,p_submitted_by_user_id:A,
    p_recipient_user_id:owner,p_amount_centavos:1000,p_payment_method:'cash',p_note:null}]);
  await actor(owner);await call('confirm_payment',[payment]);
  const initialBalance=await call('get_net_balance',[tab,owner]);
  for(const section of ['receiving_methods','connections','contacts','notifications','reminders']){
    const page=await call('export_private_page_v1',[section,null,1]);
    assert.equal(page.account_id,owner);assert.ok(page.records.length<=1);
    assert.equal(JSON.stringify(page).includes('qr_storage_path'),false);
  }
  await actor(A);
  assert.equal((await call('export_private_page_v1',['receiving_methods',null,50])).records.some(r=>r.id===method),false);
  await actor(owner);
  await db.query("SELECT set_config('request.jwt.claims',$1,false)",[JSON.stringify({amr:[{method:'password',timestamp:Math.floor(Date.now()/1000)}]})]);
  const request=await call('request_account_deletion_v1',[]),id=request.id;
  await assert.rejects(call('prepare_account_deletion_v1',[id]),e=>e.code==='42501');
  await db.exec('RESET ROLE');
  const financial=async()=>({
    transactions:(await db.query('SELECT to_jsonb(t) data FROM public.transactions t WHERE tab_id=$1 ORDER BY id',[tab])).rows,
    shares:(await db.query('SELECT to_jsonb(s) data FROM public.transaction_participants s JOIN public.transactions t ON t.id=s.transaction_id WHERE t.tab_id=$1 ORDER BY s.id',[tab])).rows,
    payments:(await db.query('SELECT to_jsonb(p) data FROM public.payments p WHERE tab_id=$1 ORDER BY id',[tab])).rows});
  const before=await financial();
  async function service(){await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE service_role');}
  await service();
  await assert.rejects(call('prepare_account_deletion_v1',[id]),e=>e.code==='42501');
  assert.equal((await call('review_account_deletion_v1',[id])).auth_deleted,false);
  await call('prepare_account_deletion_v1',[id]);
  await call('prepare_account_deletion_v1',[id]); // Interrupted preparation is replayable.
  await assert.rejects(call('finish_account_deletion_v1',[id]),e=>e.code==='55000');
  const objects=await call('pending_deletion_objects_v1',[id]);
  assert.deepEqual(objects.map(o=>o.bucket).sort(),['payment-methods','profile-avatars']);
  await assert.rejects(call('acknowledge_deletion_object_v1',[id,'payment-methods',qr]),e=>e.code==='55000');
  await actor(owner); // Simulate an already-issued JWT; no token-expiry assumption.
  for(const [name,args] of [['tabby_pre_request',[]],['export_account_data_v1',[]],
    ['export_ledger_page_v1',['expenses',null,50]],['export_private_page_v1',['contacts',null,50]],
    ['get_net_balance',[tab,owner]],['get_tab_balances_v1',[[tab]]],
    ['update_profile_v1',[{display_name:'Restore PII'}]]]) {
    await assert.rejects(call(name,args),e=>e.code==='42501');
  }
  await assert.rejects(db.query('SELECT id FROM public.users'),e=>e.code==='42501');
  assert.equal((await db.query("SELECT name FROM storage.objects WHERE bucket_id='payment-proofs'")).rows.length,0);
  await actor(A);
  assert.equal(String(await call('get_net_balance',[tab,A])),String(-Number(initialBalance)));
  await db.exec('RESET ROLE'); // Exercise a definer-equivalent insert on behalf of active A.
  await assert.rejects(db.query("INSERT INTO public.notifications(recipient_user_id,notification_type,title,body) VALUES($1,'manual_nudge','New private notice','New body')",[owner]),e=>e.code==='42501');
  await assert.rejects(db.query("INSERT INTO public.friendships(requester_id,addressee_id) VALUES($1,$2)",[A,owner]),e=>e.code==='42501');
  await actor(A);
  await assert.rejects(call('create_expense_v1',[randomUUID(),{...command,p_paid_by_user_id:A,
    p_participants:[{user_id:A,participant_role:'payer',share_amount_centavos:5000},
      {user_id:owner,participant_role:'debtor',share_amount_centavos:5000}]}]),e=>e.code==='42501');
  await db.exec('RESET ROLE');
  // Exercise the actual source Auth synchronization trigger after soft-delete-like updates.
  // This is a SQL fixture, not GoTrue/provider/session-revocation HTTP evidence.
  await db.query("UPDATE auth.users SET deleted_at=now(),email='hashed-fixture@deleted.invalid',raw_user_meta_data='{}' WHERE id=$1",[owner]);
  await service();
  await assert.rejects(call('finish_account_deletion_v1',[id]),e=>e.code==='55000'); // Session + objects still exist.
  await db.exec('RESET ROLE');
  await db.query('DELETE FROM auth.sessions WHERE user_id=$1',[owner]);
  for(const o of objects){
    await db.query('DELETE FROM storage.objects WHERE bucket_id=$1 AND name=$2',[o.bucket,o.path]);
    await service();assert.equal(await call('acknowledge_deletion_object_v1',[id,o.bucket,o.path]),true);await db.exec('RESET ROLE');
  }
  await service();
  assert.equal((await call('review_account_deletion_v1',[id])).auth_deleted,true);
  assert.equal(await call('finish_account_deletion_v1',[id]),true);
  assert.equal(await call('finish_account_deletion_v1',[id]),true);
  await db.exec('RESET ROLE');
  assert.deepEqual(await financial(),before);
  assert.equal((await db.query('SELECT count(*)::int n FROM storage.objects WHERE name=$1',[proof])).rows[0].n,1);
  const redacted=(await db.query('SELECT display_name,email,phone,anonymized_at FROM public.users WHERE id=$1',[owner])).rows[0];
  assert.equal(redacted.display_name,'Former member');assert.equal(redacted.email,null);assert.equal(redacted.phone,null);assert.ok(redacted.anonymized_at);
  assert.equal((await db.query('SELECT is_active,account_label,qr_storage_path FROM public.payment_methods WHERE id=$1',[method])).rows[0].qr_storage_path,null);
  assert.equal((await db.query('SELECT snapshot FROM public.payment_method_revisions WHERE method_id=$1',[method])).rows[0].snapshot.redacted,true);
  assert.equal((await db.query('SELECT status FROM public.account_deletion_requests WHERE id=$1',[id])).rows[0].status,'completed');
  assert.equal((await db.query('SELECT count(*)::int n FROM auth.users WHERE id=$1 AND deleted_at IS NOT NULL',[owner])).rows[0].n,1);
  await assert.rejects(db.query('DELETE FROM auth.users WHERE id=$1',[owner]),e=>['23503','23001'].includes(e.code));
  await db.exec('ALTER TABLE public.users DROP CONSTRAINT privacy_fixture_auth_fk');
  console.log('ACCOUNT_ANONYMIZATION_OK: service-only review, owner private export, resumable cleanup, stale-actor denial, Auth-sync redaction, session/media completion gates and byte-equivalent shared financial rows/proof retention passed. Auth/Storage HTTP remain unverified.');
};
