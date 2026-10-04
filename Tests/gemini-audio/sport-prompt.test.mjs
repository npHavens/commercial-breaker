import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sportPrompt } from '../../Tools/sport-prompt.mjs';

test('sport selection changes editorial criteria but preserves shared rules', () => {
  const shared = 'Shared commercial rules';
  const football = sportPrompt(shared, 'football');
  const ufc = sportPrompt(shared, 'ufc');
  assert.match(football, /Selected sport: American football/);
  assert.match(football, /Halftime editorial discussion is program/);
  assert.match(ufc, /Selected sport: UFC\/MMA/);
  assert.match(ufc, /between-fight editorial coverage/);
  assert.ok(football.endsWith(shared) && ufc.endsWith(shared));
  for (const invalid of ['basketball', '', 'constructor', '__proto__']) {
    assert.throws(() => sportPrompt(shared, invalid), /Invalid sport/);
  }
});
