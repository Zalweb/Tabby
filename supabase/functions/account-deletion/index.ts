import {makeHandler,processDeletion} from './worker.mjs';
const env=(name:string)=>Deno.env.get(name)??'';
const key=env('SUPABASE_SERVICE_ROLE_KEY');
async function api(path:string,method:string,body:unknown) {
  const url=new URL(path,env('SUPABASE_URL'));
  if(url.protocol!=='https:') throw Error('HTTPS required');
  const response=await fetch(url,{method,headers:{apikey:key,authorization:`Bearer ${key}`,
    'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  if(!response.ok) throw Error('Backend operation failed');
  const text=await response.text();return text?JSON.parse(text):null;
}
const rpc=(name:string,body:unknown)=>api(`/rest/v1/rpc/${name}`,'POST',body);
// Default gateway JWT verification remains enabled. Service authorization and
// a separate operator review secret are both required; no automatic cron.
Deno.serve(makeHandler({secret:env('PRIVACY_REVIEW_SECRET'),serviceKey:key,
  process:(requestId:string)=>processDeletion({requestId,rpc,
    ban:(id:string)=>api(`/auth/v1/admin/users/${id}`,'PUT',{ban_duration:'876000h'}),
    remove:(bucket:string,path:string)=>api(`/storage/v1/object/${bucket}`,'DELETE',{prefixes:[path]}),
    softDelete:(id:string)=>api(`/auth/v1/admin/users/${id}`,'DELETE',{should_soft_delete:true}),
  })}));
