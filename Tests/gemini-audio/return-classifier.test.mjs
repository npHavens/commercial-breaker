import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseReturnResult, returnPrompt } from '../../Tools/return-classifier.mjs';
test('return decisions distinguish content absence from unusable capture', () => {
  const result = (sport_coverage, audio_usable) => parseReturnResult(JSON.stringify({ sport_coverage, audio_usable, evidence: 'heard cues' }));
  assert.equal(result(true, true).state_at_end, 'program');
  assert.equal(result(false, true).state_at_end, 'not_program');
  assert.equal(result(true, false).state_at_end, 'unusable');
  assert.equal(result(false, false).state_at_end, 'unusable');
  assert.throws(() => parseReturnResult('{"sport_coverage":"true"}'));
  assert.throws(() => returnPrompt('__proto__'));
});
