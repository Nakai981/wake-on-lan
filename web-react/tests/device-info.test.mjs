import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseNeighbor, deviceInfo } from '../server/device-info.mjs';
test('ARP selects exact IP and rejects broadcast and invalid MAC', () => {
  const output = '192.168.0.100  a4-bb-6d-12-34-56 dynamic\n192.168.0.101  28-92-00-c0-f8-ff dynamic';
  assert.equal(parseNeighbor(output, '192.168.0.100'), 'A4:BB:6D:12:34:56');
  assert.equal(parseNeighbor(output, '192.168.0.10'), null);
  assert.equal(parseNeighbor('192.168.0.2 ff-ff-ff-ff-ff-ff', '192.168.0.2'), null);
  assert.equal(parseNeighbor('192.168.0.2 dev eth0 lladdr a4:bb:6d:12:34:56 REACHABLE', '192.168.0.2'), 'A4:BB:6D:12:34:56');
});
test('metadata uses real local hostname/MAC and returns missing remote values as null', async () => {
  const local = await deviceInfo('192.168.0.2', { interfaces: { Ethernet: [{ family: 'IPv4', address: '192.168.0.2', mac: 'a4:bb:6d:12:34:56' }] }, hostname: () => 'TEST-PC' });
  assert.equal(local.name, 'TEST-PC'); assert.equal(local.mac, 'A4:BB:6D:12:34:56');
  const remote = await deviceInfo('192.168.0.3', { interfaces: {}, reverse: async () => { throw Error('No PTR'); }, execute: async () => '', platform: 'win32' });
  assert.equal(remote.name, null); assert.equal(remote.mac, null);
});
test('metadata discovers remote name and MAC without shell commands or guessing', async () => {
  const result = await deviceInfo('192.168.0.3', { interfaces: {}, reverse: async () => ['DESKTOP.local.'],
    platform: 'win32', execute: async (file, args) => { assert.equal(file, 'arp'); assert.deepEqual(args, ['-a', '192.168.0.3']); return '192.168.0.3 a4-bb-6d-12-34-56 dynamic'; } });
  assert.equal(result.name, 'DESKTOP.local'); assert.equal(result.mac, 'A4:BB:6D:12:34:56');
});
