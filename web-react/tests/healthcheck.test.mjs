import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';
import { createBridge } from '../server/server.mjs';

test('Docker healthcheck reaches local bridge with the configured HTTPS proxy Host', async t => {
  const origin = 'https://wake.home.arpa';
  const server = createBridge({ lan: { ip: '127.0.0.1', mask: '255.0.0.0' }, origin });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const error = await new Promise(resolve => execFile(process.execPath,
    [fileURLToPath(new URL('../server/healthcheck.mjs', import.meta.url))],
    { env: { ...process.env, PORT: String(server.address().port), PUBLIC_ORIGIN: origin }, timeout: 5000 },
    error => resolve(error)));
  assert.equal(error, null);
});
