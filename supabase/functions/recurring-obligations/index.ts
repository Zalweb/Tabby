import {makeHandler} from './worker.mjs';
const env=(name:string)=>Deno.env.get(name)??'';
const key=env('SUPABASE_SERVICE_ROLE_KEY');
Deno.serve(makeHandler({serviceKey:key,secret:env('RECURRENCE_WORKER_SECRET'),
  rpc:async(name:string,body:unknown)=>{
    const url=new URL(`/rest/v1/rpc/${name}`,env('SUPABASE_URL'));
    if(url.protocol!=='https:')throw Error('HTTPS required');
    const response=await fetch(url,{method:'POST',headers:{apikey:key,authorization:`Bearer ${key}`,
      'content-type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
    if(!response.ok)throw Error('Batch not acknowledged');return response.json();
  }}));
