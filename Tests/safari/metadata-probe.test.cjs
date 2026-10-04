const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/metadata-probe.js'), 'utf8');

function probe(tracks, hostname = 'stream.directv.com') {
  const wire = vm.runInNewContext(source, {
    location: { protocol: 'https:', hostname },
    document: { querySelectorAll: () => [{ currentTime: 40, paused: false, textTracks: tracks }] }
  });
  assert.equal(typeof wire, 'string');
  return JSON.parse(wire);
}

test('metadata snapshot redacts arbitrary strings, keys and numbers and never reads captions', () => {
  let captionRead = false;
  const metadata = { kind: 'metadata', mode: 'hidden', activeCues: [{
    startTime: 12, endTime: Infinity, type: 'org.id3',
    value: { key: 'TXXX', value: 'https://private.example/token=secret', sessionToken: 'secret', timestamp: 123456 },
    text: 'private metadata text'
  }] };
  const captions = { kind: 'captions', get activeCues() { captionRead = true; throw new Error('caption read'); } };
  const result = probe([metadata, captions]);
  assert.equal(result.ok, true);
  const text = JSON.stringify(result);
  for (const secret of ['private.example', 'secret', 'sessionToken', 'private metadata text', '123456']) {
    assert.equal(text.includes(secret), false);
  }
  assert.equal(captionRead, false);
  assert.equal(metadata.mode, 'hidden');
  const cue = result.report.entries[0].videos[0].tracks[0].activeCues[0];
  assert.equal(cue.end, null);
  assert.equal(cue.type.value, 'org.id3');
  assert.equal(cue.value.fields[0].shape.value, 'TXXX');
});

test('cyclic payloads and payload getters are bounded without invoking accessors', () => {
  const value = { event: 'CUE-OUT', isAd: true };
  value.value = value;
  Object.defineProperty(value, 'data', { get() { throw new Error('must not run'); } });
  const result = probe([{ kind: 'metadata', activeCues: [{ value }] }]);
  assert.equal(result.ok, true);
  const text = JSON.stringify(result);
  assert.match(text, /cycle/);
  assert.match(text, /accessor/);
  assert.match(text, /CUE-OUT/);
});

test('unreadable native cue property does not discard the rest of the snapshot', () => {
  const cue = { startTime: 1, endTime: NaN, get data() { throw new Error('unavailable'); } };
  const result = probe([{ kind: 'metadata', activeCues: [cue] }]);
  assert.equal(result.report.entries[0].videos[0].tracks[0].activeCues[0].data.type, 'unreadable');
});

test('lookalike sites cannot be inspected', () => {
  assert.equal(probe([], 'directv.com.example.com').ok, false);
});

test('JSON inside an ID3 info field is inspected without exporting secret values', () => {
  const info = JSON.stringify({ event: 'CUE-OUT', isAd: true, token: 'private-token', url: 'https://private.example' });
  const result = probe([{ kind: 'metadata', activeCues: [{ value: { key: 'PRIV', info } }] }]);
  const text = JSON.stringify(result);
  assert.match(text, /"encoding":"json"/);
  assert.match(text, /CUE-OUT/);
  assert.match(text, /isAd/);
  assert.equal(text.includes('private-token'), false);
  assert.equal(text.includes('private.example'), false);
});

test('PRIV preview retains a bounded diagnostic value and redacts common credentials', () => {
  const info = 'owner=dtv;event=break; token=abc; https://example.com/secret Bearer abc.def.xyz';
  const result = probe([{ kind: 'metadata', activeCues: [{ value: {
    key: 'PRIV', info
  } }] }]);
  const cue = result.report.entries[0].videos[0].tracks[0].activeCues[0];
  assert.match(cue.privInfo, /owner=dtv;event=break/);
  assert.equal(cue.privInfo.includes('abc'), false);
  assert.equal(cue.privInfo.includes('example.com'), false);
  const large = probe([{ kind: 'metadata', activeCues: [{ value: { key: 'PRIV', info: 'x'.repeat(3000) } }] }]);
  assert.equal(large.report.entries[0].videos[0].tracks[0].activeCues[0].privInfo.length, 512);
});
