import http from 'node:http';
import {pathToFileURL} from 'node:url';
import {createApplication} from './app.mjs';

const knownPaths = new Set(['/healthz', '/readyz', '/functions/v1/account-deletion', '/functions/v1/reminder-push', '/functions/v1/recurring-obligations']);
export function createServer({env = process.env, fetcher = fetch, logger = console.log} = {}) {
  const application = createApplication(env, {fetcher});
  const server = http.createServer(async (req, res) => {
    const started = Date.now();
    let route = 'unknown', status = 500;
    try {
      const url = new URL(req.url, 'http://localhost');
      route = knownPaths.has(url.pathname) ? url.pathname : 'unknown';
      let size = 0;
      const chunks = [];
      // Bound buffering even with chunked input; no body/header/query logging.
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 2048) {
          status = 413;
          res.writeHead(status, {'connection': 'close'}).end();
          return;
        }
        chunks.push(chunk);
      }
      const request = new Request(url, {method: req.method, headers: req.headers,
        ...(!['GET', 'HEAD'].includes(req.method) ? {body: Buffer.concat(chunks)} : {}),
      });
      const result = await application(request);
      status = result.status;
      res.writeHead(status, {...Object.fromEntries(result.headers), 'cache-control': 'no-store', 'x-content-type-options': 'nosniff'});
      res.end(req.method === 'HEAD' ? undefined : Buffer.from(await result.arrayBuffer()));
    } catch {
      if (!res.headersSent) res.writeHead(500, {'content-type': 'text/plain'}).end('Worker unavailable');
      else res.end();
    } finally {
      logger(JSON.stringify({event: 'request', route, status, duration_ms: Date.now() - started}));
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.maxHeadersCount = 40;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  let server;
  try {
    server = createServer();
    const port = Number(process.env.PORT || 8080);
    if (!Number.isInteger(port) || port < 1 || port > 65535) throw Error();
    server.listen(port, '0.0.0.0', () => console.log(JSON.stringify({event: 'listening'})));
  } catch {
    // Configuration errors must not print secret values or provider payloads.
    console.error('Worker startup failed: verify runtime configuration');
    process.exit(1);
  }
  process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}
