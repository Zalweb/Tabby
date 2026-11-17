import test from 'node:test';
import assert from 'node:assert/strict';
import {dispatchJobs,firebaseMessage,makeHandler,mintFirebaseToken,outcomeFor} from '../supabase/functions/reminder-push/worker.mjs';
const ids = Array.from({length:6},(_,i)=>`00000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`);
const job = {job_id:ids[0],lease_id:ids[1],notification_id:ids[2],user_id:ids[3],binding_id:ids[4],tab_id:ids[5],token:'synthetic-fcm-token-never-real'};
test('payload has only account-bound identifiers and no automatic notification or financial content',()=>{
  const result=firebaseMessage(job);
  assert.equal(result.message.notification,undefined);
  assert.deepEqual(result.message.data,{v:'1',kind:'reminder',event:ids[2],account:ids[3],binding:ids[4],tab:ids[5]});
  assert.throws(()=>firebaseMessage({...job,tab_id:'../../private'}));
});
test('FCM acceptance, token invalidation, transient and permanent errors are distinct',()=>{
  assert.equal(outcomeFor({ok:true},{name:'projects/synthetic/messages/1'}),'accepted');
  assert.equal(outcomeFor({ok:true},{}),'permanent');
  assert.equal(outcomeFor({status:404},{error:{details:[{errorCode:'UNREGISTERED'}]}}),'unregistered');
  for(const status of [408,429,500,503,401,403]) assert.equal(outcomeFor({status},{}),'retry');
  assert.equal(outcomeFor({status:400},{}),'permanent');
});
test('network response loss retries and finishes only the claimed lease',async()=>{
  const calls=[];
  const result=await dispatchJobs({projectId:'synthetic-project',accessToken:'synthetic',
    rpc:async(name,body)=>{calls.push([name,body]);return name.startsWith('claim')?[job]:true;},
    fetcher:async()=>{throw Error('Response lost');}});
  assert.equal(result.retry,1);
  assert.deepEqual(calls[1],[ 'finish_reminder_push_v1',{p_job_id:ids[0],p_lease_id:ids[1],p_outcome:'retry'}]);
});
test('provider success is acceptance only and stale lease completion is ignored',async()=>{
  const result=await dispatchJobs({projectId:'synthetic-project',accessToken:'synthetic',
    rpc:async(name)=>name.startsWith('claim')?[job]:false,
    fetcher:async()=>Response.json({name:'projects/synthetic/messages/1'})});
  assert.equal(result.accepted,0);
});
test('worker rejects missing setup, wrong secret and non-POST without claiming jobs',async()=>{
  let calls=0;
  const make=secret=>makeHandler({secret,authorize:async()=>{calls++;return 'synthetic';},dispatch:async()=>({accepted:0})});
  assert.equal((await make('')(new Request('https://example.test',{method:'POST'}))).status,503);
  const secret='synthetic-worker-secret-32-characters-only';
  const handler=make(secret);
  assert.equal((await handler(new Request('https://example.test',{method:'POST'}))).status,401);
  assert.equal((await handler(new Request('https://example.test',{headers:{'x-push-worker-secret':secret}}))).status,405);
  assert.equal(calls,0);
  assert.equal((await handler(new Request('https://example.test',{method:'POST',headers:{'x-push-worker-secret':secret}}))).status,200);
});
test('OAuth assertion uses backend key, fixed Google audience and messaging-only scope',async()=>{
  const keys=await crypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
  const exported=await crypto.subtle.exportKey('pkcs8',keys.privateKey);
  const private_key='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(exported).toString('base64')+'\n-----END PRIVATE KEY-----';
  let assertion;
  const result=await mintFirebaseToken({client_email:'synthetic@example.test',private_key},{now:()=>0,fetcher:async(url,options)=>{
    assert.equal(url,'https://oauth2.googleapis.com/token');assertion=options.body.get('assertion');return Response.json({access_token:'synthetic-token'});
  }});
  assert.equal(result,'synthetic-token');
  const [header,payload,signature]=assertion.split('.');
  const claims=JSON.parse(Buffer.from(payload,'base64url'));
  assert.equal(claims.aud,'https://oauth2.googleapis.com/token');
  assert.equal(claims.scope,'https://www.googleapis.com/auth/firebase.messaging');
  assert.equal(claims.exp-claims.iat,3600);
  assert.equal(await crypto.subtle.verify('RSASSA-PKCS1-v1_5',keys.publicKey,Buffer.from(signature,'base64url'),new TextEncoder().encode(header+'.'+payload)),true);
});

const federated = () => ({type:'external_account',
  audience:'//iam.googleapis.com/projects/794974227784/locations/global/workloadIdentityPools/tabby-azure/providers/supabase-vm',
  subject_token_type:'urn:ietf:params:oauth:token-type:jwt',token_url:'https://sts.googleapis.com/v1/token',
  service_account_impersonation_url:'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/tabby-push-sender@project-16899afb-9d76-433c-9a2.iam.gserviceaccount.com:generateAccessToken',
  credential_source:{url:'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F',headers:{Metadata:'true'},format:{type:'json',subject_token_field_name:'access_token'}}});
const syntheticSubject = (exp=3600) => 'eyJhbGciOiJSUzI1NiJ9.'+Buffer.from(JSON.stringify({exp})).toString('base64url')+'.synthetic-signature';

test('Azure federation uses fixed metadata, STS then messaging-only impersonation',async()=>{
  const config=federated(),calls=[];
  const token=await mintFirebaseToken(config,{now:()=>0,fetcher:async(url,options)=>{
    calls.push([url,options]);
    assert.equal(options.redirect,'error');assert.ok(options.signal);
    if(calls.length===1){assert.equal(url,config.credential_source.url);assert.deepEqual(options.headers,{Metadata:'true'});return Response.json({access_token:syntheticSubject(),expires_in:'3600'});}
    if(calls.length===2){
      assert.equal(url,'https://sts.googleapis.com/v1/token');const body=JSON.parse(options.body);
      assert.equal(body.audience,config.audience);assert.equal(body.subjectToken,syntheticSubject());
      assert.equal(body.subjectTokenType,'urn:ietf:params:oauth:token-type:jwt');
      assert.equal(body.scope,'https://www.googleapis.com/auth/cloud-platform');
      return Response.json({access_token:'synthetic-federated-access-token',expires_in:3600});
    }
    assert.equal(url,config.service_account_impersonation_url);
    assert.equal(options.headers.authorization,'Bearer synthetic-federated-access-token');
    assert.deepEqual(JSON.parse(options.body),{scope:['https://www.googleapis.com/auth/firebase.messaging'],lifetime:'3600s'});
    return Response.json({accessToken:'synthetic-messaging-access-token',expireTime:'1970-01-01T01:00:00Z'});
  }});
  assert.equal(token,'synthetic-messaging-access-token');assert.equal(calls.length,3);
});

test('Azure federation rejects arbitrary credential endpoints before any request',async()=>{
  const mutations=[c=>c.credential_source.url='http://127.0.0.1/private',c=>c.credential_source.url+='&client_id=other',c=>c.token_url='https://example.test/token',c=>c.audience='//iam.googleapis.com/projects/evil',c=>c.service_account_impersonation_url='https://example.test/keys',c=>c.credential_source.headers.Authorization='secret',c=>c.credential_source.format.subject_token_field_name='different',c=>c.subject_token_type='other'];
  for(const change of mutations){const config=federated();change(config);let calls=0;
    await assert.rejects(mintFirebaseToken(config,{fetcher:async()=>{calls++;throw Error('unexpected request');}}));assert.equal(calls,0);
  }
});

test('Azure federation rejects invalid, expired and nearly expired metadata tokens before STS',async()=>{
  for(const token of ['',null,'not-a-jwt',syntheticSubject(30),syntheticSubject(-1)]){
    let calls=0;await assert.rejects(mintFirebaseToken(federated(),{now:()=>0,fetcher:async()=>{calls++;return Response.json({access_token:token});}}));assert.equal(calls,1);
  }
});

test('Azure federation stops at each failed exchange without leaking provider errors',async()=>{
  for(const stage of [1,2,3]){let calls=0;
    await assert.rejects(mintFirebaseToken(federated(),{now:()=>0,fetcher:async()=>{
      calls++;if(calls===stage)return Response.json({error:'PRIVATE_PROVIDER_DIAGNOSTIC'},{status:403});
      return calls===1?Response.json({access_token:syntheticSubject()}):Response.json({access_token:'synthetic-sts-token',expires_in:3600});
    }}),error=>!error.message.includes('PRIVATE_PROVIDER_DIAGNOSTIC'));assert.equal(calls,stage);
  }
});

test('Azure federation rejects empty or expired Google responses',async()=>{
  for(const response of [{access_token:'',expires_in:3600},{access_token:'synthetic',expires_in:0},{access_token:'synthetic',expires_in:3600,final:{accessToken:'synthetic',expireTime:'1970-01-01T00:00:01Z'}},{access_token:'synthetic',expires_in:3600,final:{accessToken:''}}]){
    let calls=0;await assert.rejects(mintFirebaseToken(federated(),{now:()=>0,fetcher:async()=>{
      calls++;return Response.json(calls===1?{access_token:syntheticSubject()}:calls===2?response:response.final);
    }}));assert.equal(calls,response.final?3:2);
  }
});

test('failed federated authorization cannot claim or dispatch queued jobs',async()=>{
  let claims=0;const secret='synthetic-secret-for-keyless-push-32-characters';
  const handler=makeHandler({secret,authorize:()=>mintFirebaseToken(federated(),{fetcher:async()=>Response.json({},{status:403})}),dispatch:async()=>{claims++;}});
  const result=await handler(new Request('https://example.test',{method:'POST',headers:{'x-push-worker-secret':secret}}));
  assert.equal(result.status,503);assert.equal(claims,0);assert.equal(await result.text(),'Push worker unavailable');
});
