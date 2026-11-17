import {timingSafeEqual} from 'node:crypto';
import {makeHandler as deletionHandler, processDeletion} from '../supabase/functions/account-deletion/worker.mjs';
import {makeHandler as pushHandler, dispatchJobs, mintFirebaseToken} from '../supabase/functions/reminder-push/worker.mjs';
import {makeHandler as recurrenceHandler} from '../supabase/functions/recurring-obligations/worker.mjs';

const secretNames = ['SUPABASE_SERVICE_ROLE_KEY', 'PRIVACY_REVIEW_SECRET', 'PUSH_WORKER_SECRET', 'RECURRENCE_WORKER_SECRET'];
const safeEqual = (actual, expected) => {
  const a = Buffer.from(actual ?? ''), b = Buffer.from(expected ?? '');
  return b.length > 0 && a.length === b.length && timingSafeEqual(a, b);
};

// No dotenv loading: production settings come from Azure Key Vault references.
export function createApplication(env = process.env, {fetcher = fetch} = {}) {
  const enabled = env.WORKERS_ENABLED === 'true';
  let base, firebase;
  if (enabled) {
    for (const name of secretNames) {
      if (typeof env[name] !== 'string' || env[name].length < 32 || env[name].startsWith('@Microsoft.KeyVault(')) {
        throw Error(`Missing or unresolved setting: ${name}`);
      }
    }
    base = new URL(env.SUPABASE_URL);
    if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash || base.pathname !== '/') {
      throw Error('SUPABASE_URL must be an HTTPS origin');
    }
    try { firebase = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON); } catch { throw Error('Invalid Firebase configuration'); }
    if (!firebase?.client_email || !firebase?.private_key || !/^[a-z0-9][a-z0-9-]{2,99}$/.test(env.FIREBASE_PROJECT_ID ?? '')) {
      throw Error('Missing Firebase configuration');
    }
  }
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY;
  async function api(path, method, body) {
    const response = await fetcher(new URL(path, base), {
      method, headers: {apikey: serviceKey, authorization: `Bearer ${serviceKey}`, 'content-type': 'application/json'},
      body: JSON.stringify(body), signal: AbortSignal.timeout(15000), redirect: 'error',
    });
    if (!response.ok) throw Error('Backend operation failed');
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }
  const rpc = (name, body) => api(`/rest/v1/rpc/${name}`, 'POST', body);
  const routes = new Map([
    ['/functions/v1/account-deletion', ['PRIVACY_REVIEW_SECRET', 'x-privacy-review-secret', deletionHandler({
      secret: env.PRIVACY_REVIEW_SECRET, serviceKey,
      process: requestId => processDeletion({requestId, rpc,
        ban: id => api(`/auth/v1/admin/users/${id}`, 'PUT', {ban_duration: '876000h'}),
        remove: (bucket, path) => api(`/storage/v1/object/${bucket}`, 'DELETE', {prefixes: [path]}),
        softDelete: id => api(`/auth/v1/admin/users/${id}`, 'DELETE', {should_soft_delete: true}),
      }),
    })]],
    ['/functions/v1/reminder-push', ['PUSH_WORKER_SECRET', 'x-push-worker-secret', pushHandler({
      secret: env.PUSH_WORKER_SECRET,
      authorize: () => mintFirebaseToken(firebase, {fetcher}),
      dispatch: accessToken => dispatchJobs({rpc, accessToken, projectId: env.FIREBASE_PROJECT_ID, fetcher}),
    })]],
    ['/functions/v1/recurring-obligations', ['RECURRENCE_WORKER_SECRET', 'x-recurrence-secret', recurrenceHandler({
      secret: env.RECURRENCE_WORKER_SECRET, serviceKey, rpc,
    })]],
  ]);
  return async request => {
    const path = new URL(request.url).pathname;
    if (path === '/healthz' || path === '/readyz') {
      if (!['GET', 'HEAD'].includes(request.method)) return new Response(null, {status: 405});
      // Configuration readiness only; never invokes a financial/service RPC.
      return Response.json({status: path === '/healthz' ? 'ok' : enabled ? 'configured' : 'disabled'}, {
        status: path === '/readyz' && !enabled ? 503 : 200,
      });
    }
    const route = routes.get(path);
    if (!route) return new Response(null, {status: 404});
    if (request.method !== 'POST') return new Response(null, {status: 405});
    if (!enabled) return new Response('Workers disabled', {status: 503});
    const [secretName, header, handler] = route;
    // Replaces the Supabase gateway boundary for ALL routes, including push.
    // Only trusted service operators can call these; user JWTs are insufficient.
    if (!safeEqual(request.headers.get('authorization'), `Bearer ${serviceKey}`) ||
        !safeEqual(request.headers.get(header), env[secretName])) return new Response(null, {status: 403});
    return handler(request);
  };
}
