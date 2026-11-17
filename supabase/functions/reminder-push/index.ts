import {dispatchJobs, makeHandler, mintFirebaseToken} from './worker.mjs';

const env = (name: string) => Deno.env.get(name) ?? '';
async function rpc(name: string, body: unknown) {
  const url = new URL(`/rest/v1/rpc/${name}`, env('SUPABASE_URL'));
  if (url.protocol !== 'https:') throw Error('HTTPS backend required');
  const key = env('SUPABASE_SERVICE_ROLE_KEY');
  const response = await fetch(url, {method:'POST',headers:{
    apikey:key,authorization:`Bearer ${key}`,'content-type':'application/json',
  },body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  if (!response.ok) throw Error('Push queue unavailable');
  return response.json();
}

// Supabase's default gateway JWT check remains enabled. Scheduled invocation
// additionally supplies a dedicated secret; ordinary app clients cannot run it.
Deno.serve(makeHandler({
  secret:env('PUSH_WORKER_SECRET'),
  authorize:() => mintFirebaseToken(JSON.parse(
    env('FIREBASE_WORKLOAD_IDENTITY_JSON') || env('FIREBASE_SERVICE_ACCOUNT_JSON'),
  )),
  dispatch:(accessToken: string) => dispatchJobs({rpc,accessToken,projectId:env('FIREBASE_PROJECT_ID')}),
}));
