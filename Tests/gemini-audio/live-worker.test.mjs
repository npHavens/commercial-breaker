import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyFailure, parseRequest, createWorker, createLineReader, MAX_LINE_BYTES } from '../../Tools/gemini-live-worker.mjs';

function wav() {
  const b = Buffer.alloc(256044);
  b.write('RIFF'); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(16000, 24); b.writeUInt32LE(32000, 28); b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(b.length - 44, 40);
  b.writeInt16LE(1, b.length - 2); // Nonzero decision region; quiet audio must reach the provider.
  return b;
}
const line = (id = 'abcdef012345', audio = wav()) => JSON.stringify({ id, audio: audio.toString('base64') });
const result = { state_at_end: 'program', tv_audibility: 'faint', room_speech_overlap: 'uncertain', transition_heard: false, evidence: 'Score commentary.', confidence: 0.7 };
const response = { candidates: [{ finishReason: 'STOP' }], text: JSON.stringify(result), usageMetadata: { totalTokenCount: 120, secret: 'not forwarded' } };

test('crowd trial uses minimal output and preserves distinct break/return behavior', async () => {
  for (const returnDetection of [false, true]) {
    for (const [program, decision_usable, standard, returning] of [
      [true, true, 'program', 'program'], [false, true, 'commercial', 'not_program'],
      [false, false, 'unclear', 'unusable'], [true, false, 'unclear', 'unusable'],
    ]) {
      const output = [];
      const worker = createWorker({ crowdDetection: true, returnDetection, prompt: 'test', emit: value => output.push(value),
        generateContent: async args => {
          assert.deepEqual(args.config.responseSchema.required, ['program', 'decision_usable']);
          return { candidates: [{ finishReason: 'STOP' }], text: JSON.stringify({ program, decision_usable }) };
        } });
      await worker.accept(line());
      assert.equal(output[0].result.state_at_end, returnDetection ? returning : standard);
    }
  }
});

test('crowd trial rejects malformed booleans without emitting a prediction', async () => {
  const output = [];
  await createWorker({ crowdDetection: true, prompt: '', emit: value => output.push(value),
    generateContent: async () => ({ candidates: [{ finishReason: 'STOP' }],
      text: JSON.stringify({ program: 'true', decision_usable: true }) }) }).accept(line());
  assert.deepEqual(output, [{ id: 'abcdef012345', error: 'invalid-response' }]);
});

test('validates exact eight-second mono PCM16 WAV and rejects misleading headers', () => {
  assert.equal(parseRequest(line()).audio.length, 256044);
  for (const offset of [0, 4, 8, 16, 20, 22, 24, 28, 32, 34, 36, 40]) {
    const audio = wav(); audio[offset] ^= 1;
    assert.throws(() => parseRequest(line('abcdef012345', audio)));
  }
  assert.throws(() => parseRequest(line('patient-name')));
  assert.throws(() => parseRequest('{}'));
  assert.throws(() => parseRequest(line('abcdef012345', wav().subarray(0, 200))));
});

test('request uses Flash at its lowest thinking level and forwards only validated output', async () => {
  const output = [];
  const worker = createWorker({ prompt: 'classify', emit: r => output.push(r), generateContent: async args => {
    assert.equal(args.model, 'gemini-3.8-flash');
    assert.deepEqual(args.config.thinkingConfig, { thinkingLevel: 'LOW' });
    assert.equal(args.contents[0].parts[1].inlineData.mimeType, 'audio/wav');
    return response;
  } });
  await worker.accept(line());
  assert.deepEqual(output[0].result, result);
  assert.deepEqual(output[0].usage, { totalTokenCount: 120 });
  assert.ok(output[0].elapsedMs >= 0);
});

test('does not queue concurrent requests or retry failures; provider errors are sanitized', async () => {
  const output = []; let reject; let calls = 0;
  const worker = createWorker({ prompt: '', emit: r => output.push(r), generateContent: () => {
    calls++; return new Promise((_, fail) => { reject = fail; });
  } });
  const pending = worker.accept(line());
  await worker.accept(line('000000000002'));
  assert.deepEqual(output[0], { id: '000000000002', error: 'busy' });
  reject(new Error('secret bearer token and audio'));
  await pending;
  assert.equal(calls, 1);
  assert.deepEqual(output[1], { id: 'abcdef012345', error: 'request-failed' });
});

test('timeout aborts request and shutdown suppresses late results', async () => {
  const output = [];
  const worker = createWorker({ timeoutMs: 5, prompt: '', emit: r => output.push(r), generateContent: args =>
    new Promise((_, reject) => args.config.abortSignal.addEventListener('abort', () => reject(new Error('aborted')))) });
  await worker.accept(line());
  assert.equal(output[0].error, 'timeout');
  let finish; let signal;
  const closing = createWorker({ prompt: '', emit: r => output.push(r), generateContent: args => {
    signal = args.config.abortSignal; return new Promise(resolve => { finish = resolve; });
  } });
  const pending = closing.accept(line());
  closing.close(); assert.equal(signal.aborted, true);
  finish(response); await pending;
  assert.equal(output.length, 1);
});

test('rejects incomplete and malformed provider responses', async () => {
  for (const [value, error] of [[{ candidates: [{ finishReason: 'MAX_TOKENS' }] }, 'incomplete-response'],
    [{ candidates: [{ finishReason: 'STOP' }], text: '{}' }, 'invalid-response']]) {
    const output = [];
    await createWorker({ prompt: '', emit: r => output.push(r), generateContent: async () => value }).accept(line());
    assert.equal(output[0].error, error);
  }
});

test('framing recovers after oversized lines and handles fragmented input', () => {
  const lines = []; let invalid = 0;
  const read = createLineReader(s => lines.push(s), () => invalid++);
  read(Buffer.from('hel')); read(Buffer.from('lo\nnext\n'));
  read(Buffer.alloc(MAX_LINE_BYTES, 65)); read(Buffer.from('overflow'));
  read(Buffer.from('\nlast\n'));
  assert.deepEqual(lines, ['hello', 'next', 'last']); assert.equal(invalid, 1);
});

test('temporary transport/service errors recover; auth and unknown errors stop, without leaking payloads', () => {
  for (const status of [408,429,500,503]) assert.deepEqual(classifyFailure({status,message:'secret'}), {error:'temporary-failure',httpStatus:status});
  for (const status of [400,401,403]) assert.deepEqual(classifyFailure({status}), {error:'request-failed',httpStatus:status});
  assert.deepEqual(classifyFailure({cause:{code:'ECONNRESET',message:'secret'}}), {error:'temporary-failure'});
  assert.deepEqual(classifyFailure(new Error('secret')), {error:'request-failed'});
});

test('Mac return mode requests binary content with independent audio usability', async () => {
  for (const [sport_coverage, audio_usable, expected] of [[true, true, 'program'], [false, true, 'not_program'], [true, false, 'unusable']]) {
    const output = [];
    const worker = createWorker({ returnDetection: true, prompt: 'return', emit: r => output.push(r),
      generateContent: async args => {
        assert.equal(args.config.responseSchema.properties.sport_coverage.type, 'BOOLEAN');
        assert.equal(args.config.responseSchema.properties.state_at_end, undefined);
        return { candidates: [{ finishReason: 'STOP' }], text: JSON.stringify({ sport_coverage, audio_usable, evidence: 'cues' }) };
      } });
    await worker.accept(line()); assert.equal(output[0].result.state_at_end, expected);
  }
});

test('digital silence in the decision region abstains locally in both modes, then accepts fresh audio', async () => {
  for (const returnDetection of [false, true]) {
    let calls = 0;
    const output = [];
    const worker = createWorker({ returnDetection, prompt: '', emit: value => output.push(value),
      generateContent: async () => {
        calls++;
        return returnDetection ? { candidates: [{ finishReason: 'STOP' }],
          text: JSON.stringify({ sport_coverage: true, audio_usable: true, evidence: 'test' }) } : response;
      } });
    const audio = wav(); audio.fill(0, 44);
    await worker.accept(line('000000000001', audio));
    audio.writeInt16LE(1000, 44); // Earlier context cannot override a silent final five seconds.
    await worker.accept(line('000000000002', audio));
    assert.equal(calls, 0);
    for (const record of output) {
      assert.equal(record.result.state_at_end, 'unusable');
      assert.equal(record.source, 'local-digital-silence');
      assert.deepEqual(record.usage, {});
    }
    await worker.accept(line());
    assert.equal(calls, 1);
    assert.equal(output[2].result.state_at_end, 'program');
  }
});
