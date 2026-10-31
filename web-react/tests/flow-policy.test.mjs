import { test } from 'node:test';
import assert from 'node:assert/strict';
import { scheduleStateCheck, startupWaitMs, validPowerAuthorization, wakeObservationPhase } from '../src/flow-policy.mjs';

test('power state check waits 20 seconds and cancelled checks do not run', t => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 1000 });
  let checks = 0;
  scheduleStateCheck(Date.now(), () => checks++);
  t.mock.timers.tick(19999); assert.equal(checks, 0);
  t.mock.timers.tick(1); assert.equal(checks, 1);
  const skipped = scheduleStateCheck(Date.now(), () => checks++);
  clearTimeout(skipped); t.mock.timers.tick(20000); assert.equal(checks, 1);
});
test('power requires fresh QR authorization for exactly this PC and this command', () => {
  const pc = { id: 'pc1', ip: '192.168.0.2', mac: 'A4:BB:6D:12:34:56' };
  const proof = { ...pc, command: 'sleep', at: 1000 };
  assert.equal(validPowerAuthorization(null, pc, 'sleep', 1001), false);
  assert.equal(validPowerAuthorization(proof, pc, 'sleep', 1001), true);
  assert.equal(validPowerAuthorization(proof, pc, 'shutdown', 1001), false);
  assert.equal(validPowerAuthorization(proof, { ...pc, mac: '28:92:00:C0:F8:FF' }, 'sleep', 1001), false);
  assert.equal(validPowerAuthorization(proof, pc, 'sleep', 121001), false);
});
test('Wake response switches online immediately; silence stays booting until the grace deadline', () => {
  assert.equal(startupWaitMs(10), 10000); assert.equal(startupWaitMs(30), 30000);
  assert.equal(startupWaitMs(undefined), 20000); assert.equal(startupWaitMs(2), 20000);
  assert.equal(wakeObservationPhase(true, 20000, 0), 'online');
  assert.equal(wakeObservationPhase(true, 20000, 3000), 'online');
  assert.equal(wakeObservationPhase(false, 20000, 0), 'booting');
  assert.equal(wakeObservationPhase(false, 20000, 19999), 'booting');
  assert.equal(wakeObservationPhase(false, 20000, 20000), 'unknown');
  assert.equal(wakeObservationPhase(true, 20000, 30000), 'online');
});
