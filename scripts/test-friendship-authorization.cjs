// Disposable native PostgreSQL source/RLS acceptance, not a live Supabase test.
// Requires the same ignored embedded-postgres install as test-backend-native.cjs.
'use strict';
const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const crypto=require('node:crypto');
const net=require('node:net');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const fix='20261113000001_friendship_rpc_only.sql';
const pairFix='20261113000002_friend_request_pair_lock.sql';
// Auth/Storage are intentionally injected. Public tables, grants, policies,
// triggers and RPCs come from every actual source migration in sorted order.
const setup=`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
CREATE SCHEMA auth; CREATE SCHEMA storage; CREATE SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,phone text,raw_user_meta_data jsonb NOT NULL DEFAULT '{}',raw_app_meta_data jsonb NOT NULL DEFAULT '{}',deleted_at timestamptz,email_confirmed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claim.role',true),''),current_user::text) $$;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb) $$;
CREATE TABLE storage.buckets(id text PRIMARY KEY,name text NOT NULL,public boolean NOT NULL DEFAULT false,file_size_limit bigint,allowed_mime_types text[],owner_id uuid,owner text,type text,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now());
CREATE TABLE storage.objects(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),bucket_id text NOT NULL,name text NOT NULL,owner_id text,owner uuid,created_at timestamptz DEFAULT now(),updated_at timestamptz DEFAULT now(),last_accessed_at timestamptz,metadata jsonb,user_metadata jsonb,path_tokens text[],version text,UNIQUE(bucket_id,name));
CREATE FUNCTION storage.foldername(text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN position('/' in $1)=0 THEN ARRAY[]::text[] ELSE string_to_array(regexp_replace($1,'/[^/]*$',''),'/') END $$;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE PUBLICATION supabase_realtime;
GRANT USAGE ON SCHEMA public,auth,storage TO anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON storage.objects TO anon,authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO anon,authenticated,service_role;`;

async function freePort(){const s=net.createServer();await new Promise((ok,no)=>s.once('error',no).listen(0,'127.0.0.1',ok));const p=s.address().port;await new Promise(ok=>s.close(ok));return p;}
async function main(){
 const {default:EmbeddedPostgres}=await import(pathToFileURL(process.env.TABBY_NATIVE_DB_MODULE||path.join(root,'.dart_tool/native-db/node_modules/embedded-postgres/dist/index.js')).href);
 const db=new EmbeddedPostgres({databaseDir:path.join(root,'.dart_tool/native-db/cluster-'+crypto.randomUUID()),port:await freePort(),user:'postgres',password:crypto.randomBytes(24).toString('hex'),authMethod:'scram-sha-256',persistent:true,createPostgresUser:false,autoRehydrateSymlinks:false,initdbFlags:['--encoding=UTF8','--locale=C'],postgresFlags:['-c','listen_addresses=127.0.0.1','-c','wal_level=logical'],onLog:()=>{},onError:()=>{}});
 const clients=[];const files=fs.readdirSync(path.join(root,'supabase/migrations')).filter(f=>f.endsWith('.sql')).sort();
 const read=f=>fs.readFileSync(path.join(root,'supabase/migrations',f),'utf8');
 const latestFix=files.includes(pairFix)?pairFix:fix;
 if(files.includes(latestFix))assert(fs.readFileSync(path.join(root,'supabase/schema_all.sql'),'utf8').endsWith(read(latestFix)),'Schema snapshot must retain the exact additive repair');
 async function connect(name,actor,role='authenticated'){const c=db.getPgClient(name,'127.0.0.1');await c.connect();clients.push(c);await c.query("SET statement_timeout='10s'");if(actor){await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[actor]);await c.query('SET ROLE '+role);}return c;}
 async function seed(c){
  const [A,B,C,D]=Array.from({length:4},()=>crypto.randomUUID());
  for(const id of [A,B,C,D]){await c.query('INSERT INTO auth.users(id) VALUES($1)',[id]);await c.query('INSERT INTO public.users(id,display_name) VALUES($1,$2) ON CONFLICT(id) DO UPDATE SET display_name=excluded.display_name',[id,'Synthetic fixture']);}
  const method=crypto.randomUUID(),avatar=B+'/'+crypto.randomUUID()+'.png';
  await c.query("INSERT INTO storage.objects(bucket_id,name) VALUES('profile-avatars',$1)",[avatar]);
  await c.query("UPDATE public.users SET avatar_url=$2 WHERE id=$1",[B,'avatar:'+avatar]);
  await c.query("INSERT INTO public.payment_methods(id,owner_user_id,provider,display_name,account_label) VALUES($1,$2,'other','Synthetic receiving','Synthetic only')",[method,B]);
  await c.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')",[C,D]);
  return {A,B,C,D,method,avatar,code:(await c.query('SELECT friend_code FROM public.users WHERE id=$1',[B])).rows[0].friend_code};
 }
 async function exercise(admin,name,f){
  const {A,B,C,method,avatar,code}=f;
  const [a,b,c,anon]=await Promise.all([connect(name,A),connect(name,B),connect(name,C),connect(name,A,'anon')]);
  const visible=async client=>({method:(await client.query('SELECT public.can_read_payment_method($1) AS allowed',[method])).rows[0].allowed,avatar:(await client.query('SELECT public.can_read_profile_avatar_v1($1) AS allowed',[avatar])).rows[0].allowed,profile:(await client.query('SELECT id FROM public.users WHERE id=$1',[B])).rowCount,method_rows:(await client.query('SELECT id FROM public.payment_methods WHERE id=$1',[method])).rowCount,avatar_objects:(await client.query("SELECT id FROM storage.objects WHERE bucket_id='profile-avatars' AND name=$1",[avatar])).rowCount});
  const denied={method:false,avatar:false,profile:0,method_rows:0,avatar_objects:0};
  assert.deepEqual(await visible(a),denied);
  for(const status of ['accepted','pending','declined','blocked']){
   let error=null;
   try{await a.query('INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES($1,$2,$3)',[A,B,status]);}catch(e){error=e;}
   if(!error){console.log(JSON.stringify({finding:'DIRECT_FRIENDSHIP_INSERT_BYPASSES_CONSENT',status,before:denied,after:await visible(a)}));throw Error('Direct friendship insertion must fail before recipient consent');}
   assert.equal(error.code,'42501');
  }
  await assert.rejects(()=>anon.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES($1,$2,'accepted')",[A,B]),e=>e.code==='42501');
  await assert.rejects(()=>anon.query('SELECT * FROM public.send_friend_request($1)',[code]),e=>e.code==='42501');
  // A later table grant must not re-enable the removed INSERT policy.
  await admin.query('GRANT INSERT ON public.friendships TO authenticated');
  try {
   for(const status of ['accepted','pending'])await assert.rejects(()=>a.query('INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES($1,$2,$3)',[A,B,status]),e=>e.code==='42501');
  } finally {await admin.query('REVOKE INSERT ON public.friendships FROM authenticated');}
  assert.deepEqual(await visible(a),denied);
  const request=(await a.query('SELECT * FROM public.send_friend_request($1)',[code])).rows[0];
  assert.equal(request.status,'pending');assert.equal(request.requester_id,A);assert.equal(request.addressee_id,B);
  assert.deepEqual(await visible(a),denied);
  const replay=(await a.query('SELECT * FROM public.send_friend_request($1)',[code])).rows[0];assert.equal(replay.id,request.id);
  await assert.rejects(()=>a.query('SELECT public.respond_friend_request($1,true)',[request.id]));
  await assert.rejects(()=>c.query('SELECT public.respond_friend_request($1,true)',[request.id]));
  const declined=(await b.query('SELECT public.respond_friend_request($1,false) AS result',[request.id])).rows[0].result;
  assert.deepEqual(declined,{request_id:request.id,status:'declined',tab_id:''});assert.deepEqual(await visible(a),denied);
  assert.equal((await a.query('SELECT * FROM public.send_friend_request($1)',[code])).rows[0].id,request.id);
  const accepted=(await b.query('SELECT public.respond_friend_request($1,true) AS result',[request.id])).rows[0].result;
  assert.equal(accepted.request_id,request.id);assert.equal(accepted.status,'accepted');assert.match(accepted.tab_id,/^[0-9a-f-]{36}$/);
  assert.deepEqual(await visible(a),{method:true,avatar:true,profile:1,method_rows:1,avatar_objects:1});assert.deepEqual(await visible(c),denied);
  assert.equal((await a.query("UPDATE public.friendships SET status='blocked' WHERE id=$1 RETURNING id",[request.id])).rowCount,0);
  assert.equal((await a.query('DELETE FROM public.friendships WHERE id=$1 RETURNING id',[request.id])).rowCount,0);
  assert.equal((await admin.query("SELECT count(*)::int AS n FROM public.friendships WHERE requester_id=$1 AND addressee_id=$2 AND status='accepted'",[A,B])).rows[0].n,1);
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.tab_members WHERE tab_id=$1',[accepted.tab_id])).rows[0].n,2);
  const notification=(await a.query("SELECT related_tab_id FROM public.notifications WHERE recipient_user_id=$1 AND title='Friend Request Accepted'",[A])).rows;
  assert.deepEqual(notification,[{related_tab_id:accepted.tab_id}]);
  return {direct_insert_statuses_denied:4,rls_denies_after_insert_regrant:true,anonymous_insert_rpc_denied:true,pending_declined_private:true,recipient_accept_grants_expected_access:true,outsider_denied:true,request_replay_id_preserved:true,accepted_generic_update_delete_denied:true,accepted_notification_links_canonical_tab:true};
 }
 async function raceRequests(admin,name,opposite){
  const actors=[crypto.randomUUID(),crypto.randomUUID()];
  for(const id of actors)await admin.query('INSERT INTO auth.users(id) VALUES($1)',[id]);
  const codes=await Promise.all(actors.map(async id=>(await admin.query('SELECT friend_code FROM public.users WHERE id=$1',[id])).rows[0].friend_code));
  const sessions=await Promise.all([connect(name,actors[0]),connect(name,opposite?actors[1]:actors[0])]);
  const pids=await Promise.all(sessions.map(async c=>(await c.query('SELECT pg_backend_pid() AS id')).rows[0].id));
  assert.equal(new Set(pids).size,2,'Two real native backends required');
  // SHARE permits both absence reads but pauses INSERT. Wait on observed
  // PostgreSQL lock state rather than assuming timing from a fixed sleep.
  const barrier=await connect(name);
  await barrier.query('BEGIN; LOCK TABLE public.friendships IN SHARE MODE');
  const pending=sessions.map((c,i)=>c.query('SELECT * FROM public.send_friend_request($1)',[codes[opposite&&i===1?0:1]]));
  const outcomesPromise=Promise.allSettled(pending);
  let locks;
  try{
   const deadline=Date.now()+5000;
   do{
    locks=(await admin.query("SELECT pid,wait_event_type,wait_event FROM pg_stat_activity WHERE pid=ANY($1::int[])",[pids])).rows;
    if(locks.length===2&&locks.every(x=>x.wait_event_type==='Lock'))break;
    await new Promise(ok=>setTimeout(ok,10));
   }while(Date.now()<deadline);
   assert(locks.length===2&&locks.every(x=>x.wait_event_type==='Lock'),'Both dispatched sessions must be observed blocked');
  }finally{await barrier.query('COMMIT');}
  const outcomes=await outcomesPromise;
  const rows=(await admin.query('SELECT id,requester_id,addressee_id,status FROM public.friendships WHERE requester_id=ANY($1::uuid[]) AND addressee_id=ANY($1::uuid[])',[actors])).rows;
  console.log(JSON.stringify({race:opposite?'opposite-direction':'same-direction',backend_pids:pids,observed_waits:locks.map(x=>x.wait_event),outcomes:outcomes.map(x=>x.status==='fulfilled'?{status:x.status,id:x.value.rows[0]?.id}:{status:x.status,code:x.reason.code,message:x.reason.message}),rows}));
  assert.equal(rows.length,1,'A pair must have one pending request');
  assert.equal(rows[0].status,'pending');
  if(opposite){assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1,'Only the first direction creates a request');assert.equal(outcomes.filter(x=>x.status==='rejected'&&x.reason.message==='This person has already sent you a request').length,1);}
  else {assert(outcomes.every(x=>x.status==='fulfilled'),'Same-direction concurrent retry must succeed');assert(outcomes.every(x=>x.value.rows[0].id===rows[0].id),'Same-direction results reuse the pending ID');}
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.notifications WHERE recipient_user_id=ANY($1::uuid[])',[actors])).rows[0].n,1,'One request notification, no duplicate');
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM public.tab_members WHERE user_id=ANY($1::uuid[])',[actors])).rows[0].n,0,'No ledger membership before explicit acceptance');
  return {opposite,two_native_backends:true,one_pending_request:true,one_notification:true,no_implicit_acceptance:true};
 }
 try{
  await db.initialise();await db.start();
  const reports=[];
  for(const mode of ['upgrade','previous-upgrade','fresh','snapshot']){
   const name='friend_'+mode;await db.createDatabase(name);const admin=await connect(name);
   // Roles are cluster-wide; subsequent databases reuse them.
   await admin.query(mode==='upgrade'?setup:setup.replace(/CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;/,''));
   const pending=mode==='upgrade'?files.filter(f=>[fix,pairFix].includes(f)):mode==='previous-upgrade'?files.filter(f=>f===pairFix):[];
   const selected=files.filter(f=>!pending.includes(f));
   if(mode==='snapshot')await admin.query(fs.readFileSync(path.join(root,'supabase/schema_all.sql'),'utf8'));
   else for(const file of selected)await admin.query(read(file));
   const f=await seed(admin);const before=(await admin.query('SELECT to_jsonb(f) AS row FROM public.friendships f ORDER BY id')).rows;
   for(const file of pending)await admin.query(read(file));
   const after=(await admin.query('SELECT to_jsonb(f) AS row FROM public.friendships f ORDER BY id')).rows;assert.deepEqual(after,before,'Upgrade must preserve existing friendship history');
   const contract=await exercise(admin,name,f);
   const races=[],failures=[];
   for(const opposite of [true,false]){
    try{races.push(await raceRequests(admin,name,opposite));}catch(e){failures.push(e);}
   }
   if(failures.length)throw new AggregateError(failures,'Friend-request races failed');
   reports.push({mode,migration_files:files.length,history_preserved:true,...contract,races});
  }
  console.log(JSON.stringify({postgres:(await clients[0].query('SHOW server_version')).rows[0].server_version,reports},null,2));
 }finally{await Promise.allSettled(clients.map(c=>c.end()));await db.stop();}
}
main().catch(e=>{console.error(e);process.exitCode=1;});
