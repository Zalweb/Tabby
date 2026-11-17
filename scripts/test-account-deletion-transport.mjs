import test from 'node:test';
import assert from 'node:assert/strict';

test('Deno entry point uses checked service RPCs, private Storage removal and Auth soft deletion over HTTPS',async()=>{
  const originalDeno=globalThis.Deno,originalFetch=globalThis.fetch;
  const account='00000000-0000-4000-8000-000000000002',requestId='00000000-0000-4000-8000-000000000001';
  let handler,removed=false;
  const requests=[];
  globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://backend.example.invalid',
    SUPABASE_SERVICE_ROLE_KEY:'synthetic-service',PRIVACY_REVIEW_SECRET:'synthetic-review'})[name]},serve:fn=>{handler=fn;}};
  globalThis.fetch=async(url,options)=>{
    assert.equal(url.origin,'https://backend.example.invalid');
    assert.equal(options.headers.apikey,'synthetic-service');
    assert.equal(options.headers.authorization,'Bearer synthetic-service');
    const body=JSON.parse(options.body);requests.push([url.pathname,options.method,body]);
    const name=url.pathname.split('/').at(-1);
    if(name==='review_account_deletion_v1')return Response.json({request_id:requestId,account_id:account,status:'requested',auth_deleted:false});
    if(name==='prepare_account_deletion_v1')return Response.json({account_id:account,status:'processing'});
    if(name==='pending_deletion_objects_v1')return Response.json(removed?[]:[{bucket:'payment-methods',path:account+'/private.png'}]);
    if(name==='acknowledge_deletion_object_v1'){removed=true;return Response.json(true);}
    if(name==='finish_account_deletion_v1')return Response.json(true);
    if(url.pathname===`/auth/v1/admin/users/${account}`){
      if(options.method==='PUT')assert.deepEqual(body,{ban_duration:'876000h'});
      else {assert.equal(options.method,'DELETE');assert.deepEqual(body,{should_soft_delete:true});}
      return Response.json({});
    }
    assert.equal(url.pathname,'/storage/v1/object/payment-methods');
    assert.equal(options.method,'DELETE');assert.deepEqual(body,{prefixes:[account+'/private.png']});
    return Response.json([]);
  };
  try {
    await import('../supabase/functions/account-deletion/index.ts');
    const result=await handler(new Request('https://worker.example.invalid',{method:'POST',headers:{
      authorization:'Bearer synthetic-service','x-privacy-review-secret':'synthetic-review'},
      body:JSON.stringify({reviewed:true,request_id:requestId})}));
    assert.equal(result.status,200);assert.deepEqual(await result.json(),{status:'completed'});
    assert.equal(requests.length,9);
  } finally {globalThis.Deno=originalDeno;globalThis.fetch=originalFetch;}
});
