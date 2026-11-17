'use strict';
const assert=require('node:assert/strict');
module.exports=async function(db,{A,B,C,actor}) {
  await db.exec('RESET ROLE');
  // Trigger grammar/uniqueness runs as the fixture owner. Availability RPCs
  // below run as real authenticated/anon roles. Full profile RLS is not covered
  // by this deliberately limited financial migration inventory.
  const cases=[['09171234567','+639171234567'],['+63 917 123 4567','+639171234567'],['639171234567','+639171234567'],['9171234567','+639171234567'],
    ['+1 917 123 4567',null],['08171234567',null],['0917abc1234567',null],['++639171234567',null],['091712345678',null]];
  for(const [input,expected] of cases)assert.equal((await db.query('SELECT public.normalize_ph_mobile_v1($1) AS phone',[input])).rows[0].phone,expected);
  await db.query('UPDATE public.users SET phone=$1 WHERE id=$2',['09171234567',A]);
  await db.exec('RESET ROLE');assert.equal((await db.query('SELECT phone FROM public.users WHERE id=$1',[A])).rows[0].phone,'+639171234567');
  await assert.rejects(()=>db.query('UPDATE public.users SET phone=$1 WHERE id=$2',['639171234567',B]),e=>e.code==='23505');
  await assert.rejects(()=>db.query('UPDATE public.users SET phone=$1 WHERE id=$2',['+1 917 123 4567',B]),e=>e.code==='22023');
  await actor(B);assert.equal((await db.query('SELECT public.is_phone_available($1,$2) AS free',['+639171234567',A])).rows[0].free,false);
  await actor(A);assert.equal((await db.query('SELECT public.is_phone_available($1,$2) AS free',['639171234567',A])).rows[0].free,true);
  await db.exec('RESET ROLE');await db.query("SELECT set_config('request.jwt.claim.sub','',false)");await db.exec('SET ROLE anon');
  assert.equal((await db.query('SELECT public.is_phone_available($1,$2) AS free',['09171234567',A])).rows[0].free,false);
  assert.equal((await db.query('SELECT public.is_phone_available($1) AS free',['08171234567'])).rows[0].free,false);
  await db.exec('RESET ROLE');
  // Existing same-number variants are not rewritten/merged by the migration.
  await db.exec('ALTER TABLE public.users DISABLE TRIGGER canonical_profile_phone');
  await db.query('UPDATE public.users SET phone=$1 WHERE id=$2',['09171234567',C]);
  await db.exec('ALTER TABLE public.users ENABLE TRIGGER canonical_profile_phone');
  await db.query('UPDATE public.users SET display_name=$1 WHERE id=$2',['Synthetic legacy owner',C]);
  await assert.rejects(()=>db.query('UPDATE public.users SET phone=$1 WHERE id=$2',['+63 917 123 4567',C]),e=>e.code==='23505');
  await db.exec('RESET ROLE');await db.query('UPDATE public.users SET phone=NULL WHERE id=$1',[C]);
  console.log('PROFILE_PHONE_CONTRACT_OK: accepted formats canonicalize identically, wrong prefixes/characters fail, duplicates deny and arbitrary caller exclusion cannot bypass uniqueness; historical collisions retained for review.');
};
