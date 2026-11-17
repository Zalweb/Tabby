const endpoint = new URL(process.argv[2]);
if (endpoint.protocol !== 'https:' || endpoint.username || endpoint.password || endpoint.search || endpoint.hash || endpoint.pathname !== '/') throw Error('Expected HTTPS origin without credentials');
const expectDisabled = process.argv.includes('--expect-disabled');
for (const [path, method, status] of [
  ['/healthz', 'GET', 200], ['/readyz', 'GET', expectDisabled ? 503 : 200],
  ...['account-deletion', 'reminder-push', 'recurring-obligations'].map(name => [`/functions/v1/${name}`, 'POST', expectDisabled ? 503 : 403]),
]) {
  const result = await fetch(new URL(path, endpoint), {method, redirect: 'error', signal: AbortSignal.timeout(30000)});
  if (result.status !== status) throw Error(`Probe ${path}: expected ${status}, received ${result.status}`);
  console.log(`${method} ${path}: ${result.status}`);
}
// Never invokes authenticated processing or logs response/provider bodies.
