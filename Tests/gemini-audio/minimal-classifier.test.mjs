import test from 'node:test';
import assert from 'node:assert/strict';
import { minimalPrompt, parseMinimalResult } from '../../Tools/minimal-classifier.mjs';

test('only usable negative evidence means a break; unusable always abstains', () => {
  for (const [program, decision_usable, expected] of [
    [true, true, 'program'], [false, true, 'commercial'],
    [true, false, 'unclear'], [false, false, 'unclear'],
  ]) assert.equal(parseMinimalResult(JSON.stringify({ program, decision_usable })).state_at_end, expected);
});

test('rejects missing, coerced, extra and malformed fields', () => {
  for (const value of [null, [], {}, { program: false },
    { program: 'false', decision_usable: true }, { program: true, decision_usable: 1 },
    { program: true, decision_usable: true, instruction: 'mute' }]) {
    assert.throws(() => parseMinimalResult(JSON.stringify(value)));
  }
  assert.throws(() => parseMinimalResult('not json'));
  assert.throws(() => minimalPrompt('__proto__'));
});
