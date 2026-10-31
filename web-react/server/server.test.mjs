import { test } from 'node:test';
import assert from 'node:assert/strict';
import dgram from 'node:dgram';
import net from 'node:net';
import http from 'node:http';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { createBridge, magicPacket, lanAddress } from './server.mjs';

const lan = { ip: '127.0.0.1', mask: '255.0.0.0' };
async function setup(t) {
  const server = createBridge({ lan });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const origin = `http://localhost:${server.address().port}`;
  const call = (route, body = {}, extra = {}) => fetch(`${origin}/api/${route}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...extra },
    body: JSON.stringify(body) });
  return { origin, call };
}
test('packet format and LAN boundaries', () => {
  const packet = magicPacket('A4:BB:6D:12:34:56');
  assert.equal(packet.length, 102);
  assert.deepEqual([...packet.subarray(0, 6)], [255, 255, 255, 255, 255, 255]);
  for (let i = 6; i < 102; i += 6) assert.equal(packet.subarray(i, i + 6).toString('hex'), 'a4bb6d123456');
  assert.throws(() => magicPacket('FF:FF:FF:FF:FF:FF'));
  assert.equal(lanAddress('192.168.1.8', { ip: '192.168.1.2', mask: '255.255.255.0' }), true);
  assert.equal(lanAddress('192.168.2.8', { ip: '192.168.1.2', mask: '255.255.255.0' }), false);
});
test('API rejects cross-origin, foreign Host, non-JSON and out-of-LAN targets', async t => {
  const { call, origin } = await setup(t);
  assert.deepEqual(await (await call('network')).json(), lan);
  assert.equal((await call('network', {}, { Origin: 'https://foreign.example' })).status, 403);
  const foreignStatus = await new Promise((resolve, reject) => {
    const req = http.request(origin, { headers: { Host: 'foreign.example' } }, res => {
      res.resume(); resolve(res.statusCode);
    });
    req.on('error', reject); req.end();
  });
  assert.equal(foreignStatus, 403);
  assert.equal((await call('reachable', { ip: '8.8.8.8' })).status, 400);
  assert.equal((await call('discover', { ip: '8.8.8.8' })).status, 400);
  assert.equal((await call('device-info', { ip: '8.8.8.8' })).status, 400);
  assert.deepEqual(await (await call('discover', { ip: lan.ip })).json(), { found: true, via: 'bridge' });
  assert.equal((await fetch(`${origin}/api/wake`)).status, 405);
  assert.equal((await call('wake', { mac: 'A4:BB:6D:12:34:56', broadcast: '127.0.0.1', port: 9, retries: 100 })).status, 400);
});
test('wake endpoint sends real UDP packet to LAN target', async t => {
  const { call } = await setup(t);
  const receiver = dgram.createSocket('udp4');
  receiver.bind(0, '127.0.0.1');
  await once(receiver, 'listening');
  t.after(() => receiver.close());
  const received = once(receiver, 'message');
  const res = await call('wake', { mac: 'A4:BB:6D:12:34:56', broadcast: '127.0.0.1', port: receiver.address().port, retries: 1 });
  assert.equal(res.status, 200);
  const receipt = await res.json();
  assert.equal(receipt.sent, true);
  assert.equal(receipt.packetBytes, 102);
  assert.equal(receipt.packetHex, magicPacket('A4:BB:6D:12:34:56').toString('hex').toUpperCase());
  assert.deepEqual(receipt.target, { address: '127.0.0.1', port: receiver.address().port });
  assert.equal(receipt.attempts.length, 1);
  assert.equal(receipt.attempts[0].bytes, 102);
  assert.equal(receipt.source.address, '127.0.0.1');
  const [packet] = await received;
  assert.deepEqual(packet, magicPacket('A4:BB:6D:12:34:56'));
});
test('WebSocket relays challenge and signed request without handling pairing secrets', async t => {
  const agent = net.createServer(socket => {
    socket.write('WMP1 challenge\n');
    socket.on('data', data => socket.write(data));
  });
  agent.listen(47991, '127.0.0.1');
  await once(agent, 'listening');
  t.after(() => new Promise(resolve => agent.close(resolve)));
  const { origin } = await setup(t);
  const ws = new WebSocket(origin.replace('http:', 'ws:') + '/api/agent?ip=127.0.0.1', { origin });
  t.after(() => ws.terminate());
  const hello = once(ws, 'message');
  await once(ws, 'open');
  assert.equal(String((await hello)[0]), 'WMP1 challenge\n');
  const reply = once(ws, 'message');
  ws.send('status nonce signature\n');
  assert.equal(String((await reply)[0]), 'status nonce signature\n');
  ws.close();
  await once(ws, 'close');
});
