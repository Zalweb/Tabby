'use strict';
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
module.exports=async function(db,{A,B,C,actor}) {
  await db.exec('RESET ROLE');
  const id=randomUUID(), other=randomUUID();
  // Auth is a minimal SQL fixture; no email delivery/GoTrue service is implied.
  await db.exec(`CREATE TRIGGER fixture_auth_profile AFTER INSERT OR UPDATE OF email,phone,raw_user_meta_data
    ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()`);
  await db.query('INSERT INTO auth.users(id,email,raw_user_meta_data) VALUES ($1,$2,$3::jsonb)',
    [id,'old@example.invalid',JSON.stringify({display_name:'Signup name',phone:'09191234567',avatar_url:'asset:mascot'})]);
  await actor(id);
  const save=async (changes,expected=id)=>(await db.query('SELECT public.update_profile_v2($1,$2::jsonb) AS row',[expected,JSON.stringify(changes)])).rows[0].row;
  const row=await save({display_name:'  Saved profile  ',phone:'09201234567',avatar_url:''});
  assert.equal(row.id,id);assert.equal(row.display_name,'Saved profile');
  assert.equal(row.phone,'+639201234567');assert.equal(row.avatar_url,'');assert.equal(row.email,'old@example.invalid');
  await assert.rejects(()=>db.query('UPDATE public.users SET gcash_number=$1 WHERE id=$2',['forged',id]),e=>e.code==='42501');
  for(const change of [{id:B},{email:'proposed@example.invalid'},{gcash_number:'123'},{maya_number:'123'},{qr_code_url:'guess'},{display_name:''},{phone:'123'},{display_name:123},{avatar_url:null}]) {
    await assert.rejects(()=>save(change),e=>e.code==='22023');
  }
  await db.exec('RESET ROLE');
  await db.query('INSERT INTO public.users(id,display_name,phone) VALUES ($1,$2,$3)',[other,'Other synthetic','09191234567']);
  await actor(id);
  await assert.rejects(()=>save({display_name:'Must roll back',phone:'09191234567'}),e=>e.code==='23505');
  await db.exec('RESET ROLE');
  // A confirmed Auth email change updates only email, even if the old signup
  // phone has since been taken. A metadata refresh must not restore old edits.
  await db.query('UPDATE auth.users SET email=$1 WHERE id=$2',['confirmed@example.invalid',id]);
  await db.query("UPDATE auth.users SET raw_user_meta_data=raw_user_meta_data||'{\"display_name\":\"Stale metadata\"}'::jsonb WHERE id=$1",[id]);
  const actual=(await db.query('SELECT * FROM public.users WHERE id=$1',[id])).rows[0];
  assert.equal(actual.email,'confirmed@example.invalid');assert.equal(actual.display_name,'Saved profile');
  assert.equal(actual.phone,'+639201234567');assert.equal(actual.avatar_url,'');
  await assert.rejects(()=>db.query('UPDATE public.users SET email=$1 WHERE id=$2',['forged@example.invalid',id]),e=>e.code==='42501');
  await actor(C);const own=await save({display_name:'Only actor C'},C);assert.equal(own.id,C);
  const missing=randomUUID();await actor(missing);await assert.rejects(()=>save({display_name:'Missing'},missing),e=>e.code==='P0002');
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE anon');
  await assert.rejects(()=>save({display_name:'Anonymous'}),e=>e.code==='42501');
  await db.exec('RESET ROLE');
  assert.equal((await db.query('SELECT display_name FROM public.users WHERE id=$1',[id])).rows[0].display_name,'Saved profile');
  console.log('PROFILE_WRITE_CONTRACT_OK: authenticated owner RPC row acknowledgment, field rejection, missing/anon denial, Auth-only email and metadata preservation passed. Auth is a SQL fixture, not email delivery or full Supabase inventory.');
};
