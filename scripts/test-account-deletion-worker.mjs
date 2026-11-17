import test from 'node:test';
import assert from 'node:assert/strict';
import {makeHandler,processDeletion} from '../supabase/functions/account-deletion/worker.mjs';
const requestId='00000000-0000-4000-8000-000000000001',account='00000000-0000-4000-8000-000000000002';
function fixture({fail,authDeleted=false,completed=false,objects}={}) {
  const calls=[];let pending=objects??[{bucket:'profile-avatars',path:account+'/fixture.png'}];
  const ports={requestId,
    rpc:async(name,body)=>{
      calls.push(name);
      assert.equal(body.p_request_id,requestId);
      if(fail===name) throw Error('synthetic private provider payload');
      if(name==='review_account_deletion_v1') return {request_id:requestId,account_id:account,status:completed?'completed':'processing',auth_deleted:authDeleted};
      if(name==='prepare_account_deletion_v1') return {account_id:account,status:'processing'};
      if(name==='pending_deletion_objects_v1') return pending;
      if(name==='acknowledge_deletion_object_v1') {pending=[];return true;}
      if(name==='finish_account_deletion_v1') return true;
      throw Error('Unexpected RPC');
    },
    ban:async id=>{assert.equal(id,account);calls.push('ban');if(fail==='ban')throw Error('synthetic');},
    remove:async(bucket,path)=>{calls.push('remove');assert.equal(bucket,'profile-avatars');assert.equal(path,account+'/fixture.png');if(fail==='remove')throw Error('synthetic');},
    softDelete:async id=>{assert.equal(id,account);calls.push('softDelete');if(fail==='softDelete')throw Error('synthetic');}
  };
  return {calls,ports};
}
test('review precedes ban, redaction, private cleanup, Auth soft deletion and checked completion',async()=>{
  const f=fixture();assert.deepEqual(await processDeletion(f.ports),{status:'completed'});
  assert.deepEqual(f.calls,['review_account_deletion_v1','ban','prepare_account_deletion_v1',
    'pending_deletion_objects_v1','remove','acknowledge_deletion_object_v1',
    'pending_deletion_objects_v1','softDelete','finish_account_deletion_v1']);
});
for(const fail of ['ban','prepare_account_deletion_v1','remove','acknowledge_deletion_object_v1','softDelete']) {
  test(`${fail} failure never reports or records completion`,async()=>{
    const f=fixture({fail});await assert.rejects(processDeletion(f.ports));
    assert.equal(f.calls.includes('finish_account_deletion_v1'),false);
  });
}
test('retry after lost Auth soft-delete response skips provider updates and checks database completion',async()=>{
  const f=fixture({authDeleted:true,objects:[]});
  assert.deepEqual(await processDeletion(f.ports),{status:'completed'});
  assert.equal(f.calls.includes('ban'),false);assert.equal(f.calls.includes('softDelete'),false);
  assert.equal(f.calls.at(-1),'finish_account_deletion_v1');
});
test('completed request replay does not change providers or storage',async()=>{
  const f=fixture({completed:true});await processDeletion(f.ports);
  assert.deepEqual(f.calls,['review_account_deletion_v1']);
});
test('foreign paths, proofs, traversal and malformed review cannot escape the private cleanup scope',async()=>{
  for(const object of [{bucket:'payment-proofs',path:account+'/proof.png'},
    {bucket:'profile-avatars',path:requestId+'/other.png'},
    {bucket:'profile-avatars',path:account+'/../private.png'},
    {bucket:'profile-avatars',path:account+'/folder\\private.png'}]) {
    const f=fixture({objects:[object]});await assert.rejects(processDeletion(f.ports));
    assert.equal(f.calls.includes('remove'),false);assert.equal(f.calls.includes('softDelete'),false);
  }
});
test('HTTP worker requires POST, both secrets and explicit review of a valid request ID',async()=>{
  let calls=0;
  const handler=makeHandler({secret:'synthetic-review',serviceKey:'synthetic-service',process:async()=>{calls++;return {status:'completed'};}});
  const req=(body,headers={},method='POST')=>new Request('https://example.invalid',{method,
    headers:{authorization:'Bearer synthetic-service','x-privacy-review-secret':'synthetic-review',...headers},
    body:method==='POST'?JSON.stringify(body):undefined});
  assert.equal((await handler(req({}, {},'GET'))).status,405);
  assert.equal((await handler(req({reviewed:true,request_id:requestId},{authorization:'Bearer public-client'}))).status,403);
  assert.equal((await handler(req({reviewed:true,request_id:requestId},{'x-privacy-review-secret':''}))).status,403);
  for(const body of [{request_id:requestId},{reviewed:true,request_id:'invalid'},
    {reviewed:true,request_id:requestId,account_id:account}]) assert.equal((await handler(req(body))).status,400);
  assert.equal(calls,0);
  assert.equal((await handler(req({reviewed:true,request_id:requestId}))).status,200);assert.equal(calls,1);
});
test('provider errors return a generic retry response without private data',async()=>{
  const handler=makeHandler({secret:'review',serviceKey:'service',process:async()=>{throw Error('private-path-and-secret');}});
  const response=await handler(new Request('https://example.invalid',{method:'POST',headers:{authorization:'Bearer service','x-privacy-review-secret':'review'},body:JSON.stringify({reviewed:true,request_id:requestId})}));
  assert.equal(response.status,503);assert.equal((await response.text()).includes('private-path-and-secret'),false);
});
