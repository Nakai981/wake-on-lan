import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MouseTransport } from '../src/mouse.mjs';
test('mouse transport bounds deltas, preserves click order, and releases before disposal', async () => {
  const sent = [];
  const mouse = new MouseTransport(async cmd => { sent.push(cmd.split(':').slice(2).join(':')); return 'input_ok'; }, () => assert.fail('unexpected input error'));
  mouse.add('move', 400, 2); mouse.add('move', 400, 2); mouse.add('left'); mouse.add('wheel', 9999);
  await new Promise(r => setTimeout(r, 40));
  assert.deepEqual(sent, ['move:512:4', 'left', 'wheel:1200']);
  mouse.dispose(); await new Promise(r => setTimeout(r, 40));
  assert.equal(sent.at(-1), 'up');
});
test('mouse transport clears unsent actions on failure and asks Agent to release', async () => {
  const sent = []; let errors = 0;
  const mouse = new MouseTransport(async cmd => { sent.push(cmd); return 'input_failed'; }, () => errors++);
  mouse.add('left'); mouse.add('move', 12, 14);
  await new Promise(r => setTimeout(r, 40));
  assert.equal(errors, 1); assert.equal(sent.length, 2); assert.ok(sent.at(-1).endsWith(':up'));
  mouse.dispose();
});
