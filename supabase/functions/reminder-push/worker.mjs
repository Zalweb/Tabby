// Shared with Node tests. Production ports use HTTPS and backend-only secrets.
const encoder = new TextEncoder();
const b64url = bytes => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
const jsonPart = value => b64url(encoder.encode(JSON.stringify(value)));

export async function mintFirebaseToken(serviceAccount, {fetcher = fetch, now = Date.now} = {}) {
  if (serviceAccount?.type === 'external_account') {
    return mintAzureFederatedToken(serviceAccount, {fetcher, now});
  }
  const seconds = Math.floor(now() / 1000);
  if (!serviceAccount.client_email || !serviceAccount.private_key) throw Error('Push credentials missing');
  const raw = serviceAccount.private_key.replace(/-----[^-]+-----|\s/g, '');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(raw), c => c.charCodeAt(0)),
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const unsigned = jsonPart({alg:'RS256',typ:'JWT'})+'.'+jsonPart({
    iss:serviceAccount.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',
    aud:'https://oauth2.googleapis.com/token',iat:seconds,exp:seconds+3600,
  });
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,encoder.encode(unsigned));
  const response = await fetcher('https://oauth2.googleapis.com/token',{
    method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:unsigned+'.'+b64url(new Uint8Array(signature))}),
    signal:AbortSignal.timeout(15000),
  });
  if (!response.ok) throw Error('Push authorization unavailable');
  const data = await response.json();
  if (typeof data.access_token !== 'string' || !data.access_token) throw Error('Push authorization invalid');
  return data.access_token;
}

async function mintAzureFederatedToken(configuration, {fetcher, now}) {
  const source = configuration.credential_source;
  const metadata = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F';
  const audience = /^\/\/iam\.googleapis\.com\/projects\/[1-9][0-9]{5,19}\/locations\/global\/workloadIdentityPools\/[a-z][a-z0-9-]{2,31}\/providers\/[a-z][a-z0-9-]{2,31}$/;
  const impersonation = /^https:\/\/iamcredentials\.googleapis\.com\/v1\/projects\/-\/serviceAccounts\/[a-z][a-z0-9-]{4,28}[a-z0-9]@[a-z][a-z0-9-]{4,28}[a-z0-9]\.iam\.gserviceaccount\.com:generateAccessToken$/;
  if (!audience.test(configuration.audience) ||
      configuration.token_url !== 'https://sts.googleapis.com/v1/token' ||
      configuration.subject_token_type !== 'urn:ietf:params:oauth:token-type:jwt' ||
      !impersonation.test(configuration.service_account_impersonation_url) ||
      source?.url !== metadata || source?.headers?.Metadata !== 'true' ||
      Object.keys(source.headers).length !== 1 ||
      source.format?.type !== 'json' || source.format?.subject_token_field_name !== 'access_token') {
    throw Error('Push federation configuration invalid');
  }
  const request = async (url, options) => {
    const response = await fetcher(url, {...options, redirect:'error', signal:AbortSignal.timeout(15000)});
    if (!response.ok) throw Error('Push federation authorization unavailable');
    try { return await response.json(); }
    catch { throw Error('Push federation response invalid'); }
  };
  const tokenString = value => typeof value === 'string' && value.length > 0 &&
    value.length <= 32768 && !/\s/.test(value);
  const subject = (await request(metadata, {headers:{Metadata:'true'}})).access_token;
  let expiry;
  try {
    const parts = subject.split('.');
    if (parts.length !== 3 || !parts.every(part => /^[A-Za-z0-9_-]+$/.test(part))) throw Error();
    const raw = parts[1].replace(/-/g,'+').replace(/_/g,'/');
    expiry = JSON.parse(atob(raw.padEnd(Math.ceil(raw.length / 4) * 4, '='))).exp;
  } catch { throw Error('Push identity token invalid'); }
  // Google verifies the signature/issuer/audience/VM condition. Local expiry
  // checks avoid forwarding a malformed or already expiring metadata token.
  if (!tokenString(subject) || !Number.isFinite(expiry) || expiry * 1000 <= now() + 60000) {
    throw Error('Push identity token expired');
  }
  const exchanged = await request(configuration.token_url, {method:'POST',
    headers:{'content-type':'application/json'}, body:JSON.stringify({
      grantType:'urn:ietf:params:oauth:grant-type:token-exchange', audience:configuration.audience,
      requestedTokenType:'urn:ietf:params:oauth:token-type:access_token',
      subjectTokenType:configuration.subject_token_type,subjectToken:subject,
      scope:'https://www.googleapis.com/auth/cloud-platform',
    })});
  if (!tokenString(exchanged.access_token) || !Number.isFinite(exchanged.expires_in) || exchanged.expires_in <= 60) {
    throw Error('Push federation token invalid');
  }
  const access = await request(configuration.service_account_impersonation_url, {method:'POST',
    headers:{'content-type':'application/json',authorization:`Bearer ${exchanged.access_token}`},
    body:JSON.stringify({scope:['https://www.googleapis.com/auth/firebase.messaging'],lifetime:'3600s'})});
  const expires = Date.parse(access.expireTime);
  if (!tokenString(access.accessToken) || !Number.isFinite(expires) || expires <= now() + 60000) {
    throw Error('Push messaging token invalid');
  }
  return access.accessToken;
}

export function firebaseMessage(job) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
  for (const key of ['notification_id','user_id','binding_id','tab_id']) {
    if (!uuid.test(job[key])) throw Error('Invalid push job');
  }
  if (typeof job.token !== 'string' || job.token.length < 20) throw Error('Invalid push endpoint');
  // No `notification` field: Android must validate account/binding before display.
  return {message:{token:job.token,data:{v:'1',kind:'reminder',event:job.notification_id,
    account:job.user_id,binding:job.binding_id,tab:job.tab_id},
    android:{priority:'HIGH',ttl:'3600s'}}};
}

export function outcomeFor(response, body) {
  if (response.ok && typeof body?.name === 'string') return 'accepted';
  const codes = body?.error?.details?.map(detail => detail.errorCode) ?? [];
  if (codes.includes('UNREGISTERED')) return 'unregistered';
  if ([408,429].includes(response.status) || response.status >= 500 || [401,403].includes(response.status)) return 'retry';
  return 'permanent';
}

export async function dispatchJobs({rpc, accessToken, projectId, fetcher = fetch}) {
  if (!/^[a-z0-9][a-z0-9-]{2,99}$/.test(projectId)) throw Error('Invalid push project');
  const jobs = await rpc('claim_reminder_push_v1',{p_limit:10});
  if (!Array.isArray(jobs)) throw Error('Invalid push batch');
  const totals = {accepted:0,retry:0,unregistered:0,permanent:0};
  await Promise.all(jobs.map(async job => {
    let outcome;
    try {
      const message = firebaseMessage(job);
      const response = await fetcher(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,{
        method:'POST',headers:{authorization:`Bearer ${accessToken}`,'content-type':'application/json'},
        body:JSON.stringify(message),signal:AbortSignal.timeout(15000),
      });
      let body;
      try { body = await response.json(); } catch { body = null; }
      outcome = outcomeFor(response,body);
    } catch (error) {
      outcome = error?.message?.startsWith('Invalid push') ? 'permanent' : 'retry';
    }
    // Lease token prevents stale workers from marking a newer attempt complete.
    const finished = await rpc('finish_reminder_push_v1',{
      p_job_id:job.job_id,p_lease_id:job.lease_id,p_outcome:outcome,
    });
    if (finished === true) totals[outcome]++;
  }));
  return totals;
}

export function makeHandler({secret, authorize, dispatch}) {
  return async request => {
    if (!secret || secret.length < 32) return new Response('Unavailable',{status:503});
    if (request.method !== 'POST') return new Response('Method not allowed',{status:405});
    if (request.headers.get('x-push-worker-secret') !== secret) return new Response('Unauthorized',{status:401});
    try {
      const accessToken = await authorize();
      const result = await dispatch(accessToken);
      return Response.json(result);
    } catch {
      // Do not return provider bodies, tokens or credential details.
      return new Response('Push worker unavailable',{status:503});
    }
  };
}
