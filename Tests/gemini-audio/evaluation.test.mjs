import test from 'node:test';
import assert from 'node:assert/strict';
import { tailOffsetFrames } from '../../Tools/evaluate-gemini-audio.mjs';
import { makeContents } from '../../Tools/gemini-request.mjs';
import { parseResult } from '../../Tools/standard-classifier.mjs';
const valid = { state_at_end:'unclear', tv_audibility:'faint', room_speech_overlap:'uncertain', transition_heard:false, evidence:'TV is obscured', confidence:0.2 };
test('unknown response is allowed; malformed or overconfident output rejected', () => {
 assert.deepEqual(parseResult(JSON.stringify(valid)), valid);
 for (const change of [{confidence:2},{state_at_end:'mute'},{transition_heard:'yes'},{evidence:null}]) {
  assert.throws(() => parseResult(JSON.stringify({...valid,...change})));
 }
 assert.throws(() => parseResult('not json'));
});
test('request contains only blind sample, fixed prompt, and audio', () => {
 const contents=makeContents('0123456789ab','Classify audio',Buffer.from('test-audio'));
 assert.equal(contents[0].parts[0].text,'Classify audio\nBlind sample ID: 0123456789ab');
 assert.equal(contents[0].parts[1].inlineData.mimeType,'audio/wav');
 assert.equal(Buffer.from(contents[0].parts[1].inlineData.data,'base64').toString(),'test-audio');
 assert.throws(() => makeContents('Commercial started','prompt',Buffer.from('x')));
});

test('tail offset preserves final eight seconds and rejects malformed metadata', () => {
 assert.equal(tailOffsetFrames({frames:1440000,sampleRate:48000},8),1056000);
 assert.equal(tailOffsetFrames({frames:1439999,sampleRate:48000},8),1055999);
 assert.throws(() => tailOffsetFrames({frames:100,sampleRate:48000},8));
 assert.throws(() => tailOffsetFrames({frames:1440000,sampleRate:NaN},8));
 assert.throws(() => tailOffsetFrames({frames:1440000,sampleRate:48000},0));
});

test('shared sports program is accepted; obsolete live football state is rejected', () => {
 for (const state of ['program','commercial','promo','unclear']) {
  assert.equal(parseResult(JSON.stringify({...valid,state_at_end:state})).state_at_end,state);
 }
 assert.throws(() => parseResult(JSON.stringify({...valid,state_at_end:'football'})));
});
