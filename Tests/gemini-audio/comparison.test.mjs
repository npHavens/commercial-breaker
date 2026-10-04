import test from 'node:test';
import assert from 'node:assert/strict';
import { summarize } from '../../Tools/compare-detection.mjs';

test('comparison distinguishes abstention, false mute and false return with denominators', () => {
  const summary = summarize([
    { variant: 'minimal', expected: 'program', actual: 'break', elapsedMs: 100, usage: { candidatesTokenCount: 10 } },
    { variant: 'minimal', expected: 'break', actual: 'program', elapsedMs: 300, usage: {} },
    { variant: 'minimal', expected: 'break', actual: 'unclear', elapsedMs: 200, usage: {} },
    { variant: 'minimal', expected: 'unclear', actual: 'unclear', elapsedMs: 400, usage: {} },
  ]);
  assert.deepEqual(summary.minimal, {
    samples: 4, medianMs: 250, minMs: 100, maxMs: 400, outputTokens: 10,
    markerAgreement: 1, markedSamples: 4, programSamples: 1, breakSamples: 2, unclearSamples: 1,
    falseMuteCandidates: 1, falseReturnCandidates: 1, abstentions: 2,
  });
  assert.equal(summary.baseline.medianMs, null);
});
