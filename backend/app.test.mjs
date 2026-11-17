import test from 'node:test';
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {createApplication} from './app.mjs';
import {createServer} from './server.mjs';

const account = '00000000-0000-4000-8000-000000000002';
const requestId = '00000000-0000-4000-8000-000000000001';
const {privateKey} = generateKeyPairSync('rsa', {modulusLength: 2048});
const env = {
  WORKERS_ENABLED: 'true', SUPABASE_URL: 'https://backend.example.invalid',
  SUPABASE_SERVICE_ROLE_KEY: 'synthetic-service-key-'.repeat(3),
  PRIVACY_REVIEW_SECRET: 'synthetic-review-'.repeat(3),
  PUSH_WORKER_SECRET: 'synthetic-push-'.repeat(3),
  RECURRENCE_WORKER_SECRET: 'synthetic-recurrence-'.repeat(3),
  FIREBASE_PROJECT_ID: 'synthetic-project',
  FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({client_email: 'test@example.invalid', private_key: privateKey.export({type: 'pkcs8', format: 'pem'})}),
};
const routes = [
  ['account-deletion', 'x-privacy-review-secret', 'PRIVACY_REVIEW_SECRET'],
  ['reminder-push', 'x-push-worker-secret', 'PUSH_WORKER_SECRET'],
  ['recurring-obligations', 'x-recurrence-secret', 'RECURRENCE_WORKER_SECRET'],
];
const request = (name, header, secret, bearer = env.SUPABASE_SERVICE_ROLE_KEY, body) => new Request(`https://workers.example.invalid/functions/v1/${name}`, {
  method: 'POST', headers: {authorization: `Bearer ${bearer}`, [header]: secret}, body,
});

test('default-disabled app is live but not ready and cannot dispatch', async () => {
  const app = createApplication({}, {fetcher: () => assert.fail('No backend call allowed')});
  assert.equal((await app(new Request('https://workers.example.invalid/healthz'))).status, 200);
  assert.equal((await app(new Request('https://workers.example.invalid/readyz'))).status, 503);
  for (const [name, header, key] of routes) assert.equal((await app(request(name, header, env[key]))).status, 503);
});

test('enabled startup rejects unresolved secrets and unsafe backend origins', () => {
  for (const SUPABASE_URL of ['http://backend.invalid', 'https://user:password@backend.invalid', 'https://backend.invalid/path', 'https://backend.invalid?token=private']) {
    assert.throws(() => createApplication({...env, SUPABASE_URL}));
  }
  assert.throws(() => createApplication({...env, PUSH_WORKER_SECRET: '@Microsoft.KeyVault(SecretName=unresolved)'}));
  assert.throws(() => createApplication({...env, FIREBASE_SERVICE_ACCOUNT_JSON: '{}'}));
});

test('every worker requires both service bearer and dedicated secret, including push', async () => {
  const app = createApplication(env, {fetcher: () => assert.fail('Unauthorized request reached backend')});
  for (const [name, header, key] of routes) {
    assert.equal((await app(request(name, header, env[key], 'ordinary-user-jwt'))).status, 403);
    assert.equal((await app(request(name, header, 'wrong-secret'))).status, 403);
    assert.equal((await app(request(name, header, ''))).status, 403);
    assert.equal((await app(new Request(`https://workers.example.invalid/functions/v1/${name}`))).status, 405);
  }
});

test('recurrence dispatch keeps bounded RPC and sanitized failures', async () => {
  const app = createApplication(env, {fetcher: async (url, options) => {
    assert.equal(url.href, `${env.SUPABASE_URL}/rest/v1/rpc/materialize_due_recurrences_v1`);
    assert.equal(options.headers.apikey, env.SUPABASE_SERVICE_ROLE_KEY);
    assert.equal(options.redirect, 'error');
    assert.deepEqual(JSON.parse(options.body), {p_limit: 25});
    return Response.json({processed: 1, needs_attention: 0});
  }});
  const result = await app(request(...[routes[2][0], routes[2][1], env.RECURRENCE_WORKER_SECRET]));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), {processed: 1, needs_attention: 0});
  const failing = createApplication(env, {fetcher: async () => new Response('private-provider-data', {status: 500})});
  const failure = await failing(request(routes[2][0], routes[2][1], env.RECURRENCE_WORKER_SECRET));
  assert.equal(failure.status, 503);
  assert.doesNotMatch(await failure.text(), /private-provider-data/);
});

test('reviewed deletion preserves exact Auth soft delete and private Storage transport', async () => {
  const calls = [];
  let removed = false;
  const app = createApplication(env, {fetcher: async (url, options) => {
    assert.equal(url.origin, env.SUPABASE_URL);
    assert.equal(options.headers.authorization, `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`);
    const body = JSON.parse(options.body);
    calls.push([url.pathname, options.method, body]);
    const rpc = url.pathname.split('/').at(-1);
    if (rpc === 'review_account_deletion_v1') return Response.json({request_id: requestId, account_id: account, status: 'requested', auth_deleted: false});
    if (rpc === 'prepare_account_deletion_v1') return Response.json({account_id: account, status: 'processing'});
    if (rpc === 'pending_deletion_objects_v1') return Response.json(removed ? [] : [{bucket: 'payment-methods', path: `${account}/private.png`}]);
    if (rpc === 'acknowledge_deletion_object_v1') { removed = true; return Response.json(true); }
    if (rpc === 'finish_account_deletion_v1') return Response.json(true);
    return Response.json({});
  }});
  const result = await app(request(routes[0][0], routes[0][1], env.PRIVACY_REVIEW_SECRET, env.SUPABASE_SERVICE_ROLE_KEY, JSON.stringify({reviewed: true, request_id: requestId})));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), {status: 'completed'});
  assert.ok(calls.some(([path, method, body]) => path === `/auth/v1/admin/users/${account}` && method === 'DELETE' && body.should_soft_delete === true));
  assert.ok(calls.some(([path, method, body]) => path === '/storage/v1/object/payment-methods' && method === 'DELETE' && body.prefixes[0] === `${account}/private.png`));
  assert.equal(calls.length, 9);
});

test('push mints provider authorization and dispatches bounded queue without exposing tokens', async () => {
  const paths = [];
  const app = createApplication(env, {fetcher: async (url, options) => {
    paths.push(String(url));
    if (String(url) === 'https://oauth2.googleapis.com/token') {
      assert.equal(options.body.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      return Response.json({access_token: 'synthetic-provider-token'});
    }
    assert.equal(url.pathname, '/rest/v1/rpc/claim_reminder_push_v1');
    assert.deepEqual(JSON.parse(options.body), {p_limit: 10});
    return Response.json([]);
  }});
  const result = await app(request(routes[1][0], routes[1][1], env.PUSH_WORKER_SECRET));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), {accepted: 0, retry: 0, unregistered: 0, permanent: 0});
  assert.equal(paths.length, 2);
});

test('native HTTP bridge bounds bodies and never logs credentials, body or query', async () => {
  const logs = [];
  const server = createServer({env, logger: line => logs.push(line), fetcher: () => assert.fail('No backend call allowed')});
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    const response = await fetch(`${origin}/healthz?secret=private-query`, {headers: {'x-private': 'private-header'}});
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(`${origin}/unknown-private-path`)).status, 404);
    assert.equal((await fetch(`${origin}/functions/v1/account-deletion`, {method: 'POST', body: 'private-body'.repeat(300)})).status, 413);
    assert.equal((await fetch(`${origin}/functions/v1/reminder-push`, {method: 'POST', headers: {authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`}})).status, 403);
    assert.doesNotMatch(logs.join('\n'), /private-query|private-header|private-body|unknown-private-path|synthetic-service/);
    assert.deepEqual(logs.map(line => JSON.parse(line).status), [200, 404, 413, 403]);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
