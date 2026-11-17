import test from 'node:test';import assert from 'node:assert/strict';
import {makeHandler} from '../supabase/functions/recurring-obligations/worker.mjs';
const request=(headers={},method='POST')=>new Request('https://example.invalid',{method,headers:{authorization:'Bearer synthetic-service','x-recurrence-secret':'synthetic-secret',...headers}});
test('scheduler requires method, service authorization and separate secret before any work',async()=>{
  let called=0;const handler=makeHandler({serviceKey:'synthetic-service',secret:'synthetic-secret',rpc:async()=>{called++;return {processed:1,needs_attention:0};}});
  assert.equal((await handler(request({},'GET'))).status,405);
  assert.equal((await handler(request({authorization:'Bearer client'}))).status,403);
  assert.equal((await handler(request({'x-recurrence-secret':''}))).status,403);assert.equal(called,0);
  assert.equal((await handler(request())).status,200);assert.equal(called,1);
});
test('only a bounded named RPC is dispatched and partial failures stay explicit',async()=>{
  const handler=makeHandler({serviceKey:'synthetic-service',secret:'synthetic-secret',rpc:async(name,body)=>{
    assert.equal(name,'materialize_due_recurrences_v1');assert.deepEqual(body,{p_limit:25});return {processed:2,needs_attention:1};}});
  assert.deepEqual(await (await handler(request())).json(),{processed:2,needs_attention:1});
});
test('lost or malformed acknowledgments return no financial success claim or provider detail',async()=>{
  for(const value of [null,{processed:26,needs_attention:0},{processed:1,needs_attention:-1}]){
    const handler=makeHandler({serviceKey:'synthetic-service',secret:'synthetic-secret',rpc:async()=>value});assert.equal((await handler(request())).status,503);
  }
  const handler=makeHandler({serviceKey:'synthetic-service',secret:'synthetic-secret',rpc:async()=>{throw Error('private-body');}});
  const result=await handler(request());assert.equal(result.status,503);assert.equal((await result.text()).includes('private-body'),false);
});
