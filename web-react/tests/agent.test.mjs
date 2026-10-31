import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';
import { once } from 'node:events';
import { agentRequest } from '../src/api.mjs';

test('React Agent client authenticates HMAC replies and rejects forged acknowledgements', async t => {
  const server = new WebSocketServer({ port: 0, host: '127.0.0.1' });
  await once(server, 'listening'); t.after(() => new Promise(resolve => server.close(resolve)));
  const code = '0123456789abcdef0123456789abcdef', challenge = 'a'.repeat(64);
  const sign = value => createHmac('sha256', Buffer.from(code, 'hex')).update(value).digest('hex');
  let forged = false;
  server.on('connection', ws => {
    // Split the greeting to exercise TCP-to-WebSocket frame boundaries.
    ws.send('WMP1 '); ws.send(challenge + '\n');
    ws.on('message', data => {
      const [command, nonce, signature] = data.toString().trim().split(' ');
      assert.equal(signature, sign(`request\n${challenge}\n${nonce}\n${command}`));
      ws.send('online ' + (forged ? '0'.repeat(64) : sign(`response\n${challenge}\n${nonce}\n${command}\nonline`)) + '\n');
    });
  });
  const options = { base: `http://127.0.0.1:${server.address().port}`, WebSocketImpl: WebSocket };
  assert.equal(await agentRequest('127.0.0.1', code, 'status', options), 'online');
  forged = true;
  await assert.rejects(agentRequest('127.0.0.1', code, 'status', options), /Không xác thực/);
});
