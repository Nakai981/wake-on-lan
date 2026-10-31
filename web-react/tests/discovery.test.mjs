import { test } from 'node:test';
import assert from 'node:assert/strict';
import { selectLan, tcpEvidence, discoverHost, pingHost } from '../server/network.mjs';

test('LAN selection prefers real Wi-Fi over the first Hyper-V adapter and honors LAN_IP', () => {
  const interfaces = {
    'vEthernet (Default Switch)': [{ family: 'IPv4', address: '192.168.208.1', netmask: '255.255.240.0', internal: false }],
    'Wi-Fi': [{ family: 'IPv4', address: '192.168.0.105', netmask: '255.255.255.0', internal: false }]
  };
  assert.equal(selectLan(undefined, interfaces).ip, '192.168.0.105');
  assert.equal(selectLan('192.168.208.1', interfaces).ip, '192.168.208.1');
  assert.throws(() => selectLan('1.2.3.4', interfaces));
});
test('Agent-only PC is reachable; refused TCP is discovery evidence, not an open service', async () => {
  assert.equal((await tcpEvidence('192.168.0.2', async (_, port) => port === 47991 ? 'open' : 'silent')).reachable, true);
  assert.deepEqual(await tcpEvidence('192.168.0.2', async () => 'refused'), { reachable: false, responds: true });
  const result = await discoverHost('192.168.0.2', { tcp: async () => ({ reachable: false, responds: true }), ping: () => assert.fail('No ping needed') });
  assert.deepEqual(result, { found: true, via: 'tcp-refused' });
});
test('discovery falls back to ICMP when all scanned TCP ports are filtered', async () => {
  assert.deepEqual(await discoverHost('192.168.0.2', { tcp: async () => ({ reachable: false, responds: false }), ping: async () => true }), { found: true, via: 'icmp' });
  assert.equal((await discoverHost('192.168.0.2', { tcp: async () => ({ reachable: false, responds: false }), ping: async () => false })).found, false);
});
test('ping does not mistake Windows Destination Host Unreachable for a live device', async () => {
  const run = output => (_file, _args, _options, callback) => callback(null, output);
  assert.equal(await pingHost('192.168.0.2', { run: run('Reply from 192.168.0.1: Destination host unreachable.') }), false);
  assert.equal(await pingHost('192.168.0.2', { run: run('Reply from 192.168.0.2: bytes=32 time<1ms TTL=128') }), true);
});
