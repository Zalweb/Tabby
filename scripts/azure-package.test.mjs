import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import net from 'node:net';
import {fileURLToPath} from 'node:url';
import {readFile} from 'node:fs/promises';

test('staged deployment starts independently with its declared command and no runtime credentials', {timeout: 15000}, async () => {
  const cwd = fileURLToPath(new URL('../.dart_tool/azure-workers/package/', import.meta.url));
  const manifest = JSON.parse(await readFile(new URL('../.dart_tool/azure-workers/package/package.json', import.meta.url), 'utf8'));
  const reservation = net.createServer();
  await new Promise(resolve => reservation.listen(0, '127.0.0.1', resolve));
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const [command, ...args] = manifest.scripts.start.split(' ');
  assert.equal(command, 'node');
  const child = spawn(process.execPath, args, {cwd, windowsHide: true,
    env: {SystemRoot: process.env.SystemRoot, PATH: process.env.PATH, PORT: String(port), WORKERS_ENABLED: 'false'},
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exited = new Promise(resolve => child.once('exit', resolve));
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(Error('Staged server failed to start')), 8000);
      child.once('error', error => {clearTimeout(timeout); reject(error);});
      child.once('exit', () => {clearTimeout(timeout); reject(Error('Staged server exited before startup'));});
      child.stdout.on('data', chunk => {
        if (chunk.toString().includes('"event":"listening"')) { clearTimeout(timeout); resolve(); }
      });
    });
    const origin = `http://127.0.0.1:${port}`;
    assert.equal((await fetch(`${origin}/healthz`)).status, 200);
    assert.equal((await fetch(`${origin}/readyz`)).status, 503);
    for (const name of ['account-deletion', 'reminder-push', 'recurring-obligations']) {
      assert.equal((await fetch(`${origin}/functions/v1/${name}`, {method: 'POST'})).status, 503);
    }
  } finally {
    child.kill();
    await exited;
  }
});
