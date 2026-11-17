'use strict';
const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
module.exports=async(db,{actor})=>{
  await db.exec('RESET ROLE');
  const owner=randomUUID(),friend=randomUUID(),stranger=randomUUID(),peer=randomUUID();
  for(const id of [owner,friend,stranger,peer]) await db.query("INSERT INTO public.users(id,display_name) VALUES ($1,'Synthetic avatar fixture')",[id]);
  const photo=owner+'/'+randomUUID()+'.png',replacement=owner+'/'+randomUUID()+'.png',missing=owner+'/'+randomUUID()+'.png';
  const save=async value=>(await db.query('SELECT public.update_profile_v2($1,$2::jsonb) AS row',[owner,JSON.stringify({avatar_url:value})])).rows[0].row;
  const count=async()=> (await db.query("SELECT count(*)::int AS n FROM storage.objects WHERE bucket_id='profile-avatars' AND name=$1",[photo])).rows[0].n;
  await actor(owner);
  for(const path of [friend+'/'+randomUUID()+'.png',owner+'/../wrong.png',owner+'/guess.jpg']) {
    await assert.rejects(()=>db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('profile-avatars',$1)",[path]),e=>e.code==='42501');
  }
  await db.query("INSERT INTO storage.objects(bucket_id,name) VALUES ('profile-avatars',$1),('profile-avatars',$2)",[photo,replacement]);
  assert.equal((await save('avatar:'+photo)).avatar_url,'avatar:'+photo);
  assert.equal(await count(),1);
  for(const value of ['avatar:'+missing,'avatar:'+friend+'/'+randomUUID()+'.png','https://tracking.example.invalid/photo','asset:invented']) {
    await assert.rejects(()=>save(value),e=>e.code==='22023');
  }
  assert.equal((await db.query("UPDATE storage.objects SET name=name||'x' WHERE bucket_id='profile-avatars' AND name=$1 RETURNING id",[photo])).rows.length,0);
  assert.equal((await db.query("DELETE FROM storage.objects WHERE bucket_id='profile-avatars' AND name=$1 RETURNING id",[photo])).rows.length,0);
  await actor(stranger);assert.equal(await count(),0);
  await actor(friend);assert.equal(await count(),0);
  await db.exec('RESET ROLE');
  await db.query("INSERT INTO public.friendships(requester_id,addressee_id,status) VALUES ($1,$2,'accepted')",[owner,friend]);
  await actor(friend);assert.equal(await count(),1);
  assert.equal((await db.query("SELECT name FROM storage.objects WHERE bucket_id='profile-avatars' AND name=$1",[replacement])).rows.length,0);
  await db.exec('RESET ROLE');const tab=randomUUID();
  await db.query('INSERT INTO public.tabs(id,user_a,user_b) VALUES ($1,$2,$3)',[tab,owner,peer]);
  await db.query('INSERT INTO public.tab_members(tab_id,user_id) VALUES ($1,$2),($1,$3)',[tab,owner,peer]);
  await actor(peer);assert.equal(await count(),1);
  await db.exec('RESET ROLE');await db.query("UPDATE public.tabs SET status='archived' WHERE id=$1",[tab]);
  await actor(peer);assert.equal(await count(),0);
  await actor(owner);await save('avatar:'+replacement);
  await actor(friend);assert.equal(await count(),0);
  await actor(owner);await save('');assert.equal(await count(),1);
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE anon');assert.equal(await count(),0);
  await db.exec('RESET ROLE');
  console.log('PROFILE_AVATAR_CONTRACT_OK: actual Storage RLS owner insert, malformed/foreign denial, no object mutation, current-only accepted-friend/active-peer reads, archived/outsider/anon denial and upload-before-reference passed. No Storage HTTP or device tested.');
};
