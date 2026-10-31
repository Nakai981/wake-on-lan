import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lanInfo, normalizeMac, validatePc, parsePairQr, textCommand, keyCommand, scanLan } from '../src/core.mjs';
test('MAC validation and non-/24 subnet calculations match Flutter behavior', () => {
  assert.equal(normalizeMac(' a4-bb-6d-12-34-56 '), 'A4:BB:6D:12:34:56');
  for (const mac of ['FF:FF:FF:FF:FF:FF', '00:00:00:00:00:00', 'AA:BB', 'GG:BB:CC:DD:EE:FF']) assert.throws(() => normalizeMac(mac));
  const lan = lanInfo({ ip: '192.168.2.140', mask: '255.255.255.128' });
  assert.equal(lan.broadcast, '192.168.2.255'); assert.equal(lan.hosts.length, 126);
  assert.equal(lan.contains('192.168.2.127'), false); assert.equal(lan.hosts.includes(lan.ip), true);
  assert.equal(lanInfo({ ip: '10.20.30.40', mask: '255.255.0.0' }).hosts.length, 254);
  assert.throws(() => lanInfo({ ip: '1.2.3.4', mask: '255.0.255.0' }));
});
test('device validation, QR integrity and remote command limits', () => {
  const pc = { name: ' PC ', mac: 'A4:BB:6D:12:34:56', ip: '192.168.1.2', port: '9', retries: '3', timeout: '60' };
  assert.equal(validatePc(pc).port, 9); assert.equal(validatePc(pc).name, 'PC');
  assert.throws(() => validatePc({ ...pc, retries: 11 }));
  const raw = 'wakemypc://pair?v=1&ip=192.168.1.2&mac=A4:BB:6D:12:34:56&key=0123456789abcdef0123456789abcdef';
  assert.equal(parsePairQr(raw).ip, pc.ip);
  assert.throws(() => parsePairQr(raw + '&v=1')); assert.throws(() => parsePairQr(raw.replace('192.168.1.2', '127.0.0.1')));
  assert.equal(keyCommand('S', ['Win', 'Shift']), 'key:12:83'); assert.equal(keyCommand('F12'), 'key:0:123');
  assert.equal(Buffer.from(textCommand('Tiếng Việt').slice(5), 'base64').toString(), 'Tiếng Việt');
  assert.throws(() => textCommand('a'.repeat(241))); assert.throws(() => textCommand('line\nline'));
});
test('scanner limits concurrency to 12 and respects cancellation', async () => {
  let active = 0, peak = 0, updates = 0;
  const controller = new AbortController();
  await scanLan({ hosts: Array.from({ length: 200 }, (_, i) => '' + i) }, {
    signal: controller.signal,
    probe: async () => { active++; peak = Math.max(peak, active); await new Promise(r => setTimeout(r, 1)); active--; return true; },
    progress: () => { updates++; if (updates === 5) controller.abort(); }
  });
  assert.equal(peak, 12); assert.equal(updates, 5);
});
