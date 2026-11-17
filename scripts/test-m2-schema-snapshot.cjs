'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
test('disabled M2 additive migrations match the consolidated snapshot byte for byte',()=>{
 const snapshot=fs.readFileSync(path.join(__dirname,'../supabase/schema_all.sql'),'utf8').replace(/\r\n/g,'\n');
 for(const [file,label] of [
 ['20261102000009_custom_splits.sql','custom splits'],
 ['20261102000010_recurring_obligations.sql','recurring obligations'],
 ['20261102000011_explicit_contact_claims.sql','explicit contact claiming'],
 ['20261102000012_expense_review.sql','expense review'],
 ]){
  const marker=`-- M2 ${label} (rollout disabled)\n`,source=fs.readFileSync(path.join(__dirname,'../supabase/migrations',file),'utf8').replace(/^\uFEFF/,'').replace(/\r\n/g,'\n');
  assert(snapshot.includes(marker),file);const start=snapshot.indexOf(marker)+marker.length;
  assert.equal(snapshot.slice(start,start+source.length),source,file);
 }
});
