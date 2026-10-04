const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const read = f => readFileSync(resolve(__dirname, '../../SafariExtension', f), 'utf8');
function setup({ unsupported = false, reject = false, signal = 0.25, suspended = false, noTrack = false, analysisError = false } = {}) {
  const timers = new Map(), listeners = new Map(); let next = 0, captures = 0, closed = 0, connectedGain;
  const audio = { readyState: 'live', muted: false, stopped: 0, stop() { this.stopped++; } };
  const videoTrack = { stopped: 0, stop() { this.stopped++; } };
  const stream = { getTracks: () => [audio, videoTrack], getVideoTracks: () => [videoTrack], getAudioTracks: () => noTrack ? [] : [audio] };
  const node = () => ({ connect() {}, disconnect() {} });
  class AudioContext {
    constructor() { this.state = suspended ? 'suspended' : 'running'; this.destination = {}; }
    resume() { return suspended ? new Promise(() => {}) : Promise.resolve(); }
    close() { closed++; return Promise.resolve(); }
    createMediaStreamSource() { return node(); }
    createAnalyser() { return { ...node(), getFloatTimeDomainData(buffer) { if (analysisError) throw new Error('analysis'); buffer.fill(signal); } }; }
    createGain() { const n = { ...node(), gain: { value: 1 } }; connectedGain = n; return n; }
  }
  const video = Object.freeze({ paused: false, ended: false, muted: true, volume: 0.7, webkitCurrentPlaybackTargetIsWireless: false,
    getBoundingClientRect: () => ({ width: 100, height: 100, bottom: 100, right: 100, top: 0, left: 0 }),
    captureStream: unsupported ? undefined : () => { captures++; if (reject) { const e = new Error('secret URL'); e.name = 'NotSupportedError'; throw e; } return stream; }
  });
  const context = vm.createContext({ AudioContext, Float32Array,
    document: { querySelectorAll: () => [video] }, location: { protocol: 'https:', hostname: 'stream.directv.com' },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }), innerWidth: 1000, innerHeight: 800,
    window: { addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name) },
    setTimeout: fn => { timers.set(++next, fn); return next; }, clearTimeout: id => timers.delete(id),
    setInterval: fn => { timers.set(++next, fn); return next; }, clearInterval: id => timers.delete(id)
  });
  vm.runInContext(read('select-video.js'), context);
  return { run: () => vm.runInContext(read('audio-probe.js'), context),
    recover: () => JSON.parse(vm.runInContext(read('audio-result.js'), context)),
    finish: () => [...timers.values()][0]?.(), exit: () => listeners.get('pagehide')?.(),
    stats: () => ({ captures, closed, audioStops: audio.stopped, videoStops: videoTrack.stopped, timers: timers.size, listeners: listeners.size, gain: connectedGain?.gain.value }) };
}
test('nonzero samples use a silent sink and release tracks, context and timers', async () => {
  const h = setup(); const p = h.run(); h.finish(); const r = JSON.parse(await p);
  assert.equal(r.outcome, 'nonzero-samples'); assert.equal(r.peak, 0.25); assert.equal(r.rms, 0.25);
  assert.equal(r.muted, true); assert.equal(r.wireless, false);
  const s = h.stats(); assert.equal(s.gain, 0); assert.equal(s.closed, 1); assert.ok(s.audioStops > 0 && s.videoStops > 0);
  assert.equal(s.timers + s.listeners, 0);
});
test('unsupported and rejected capture do not claim silence or leak error text', async () => {
  const a = setup({ unsupported: true }); assert.equal(JSON.parse(await a.run()).outcome, 'unsupported'); assert.equal(a.stats().captures, 0);
  const b = setup({ reject: true }); const wire = await b.run(); assert.equal(JSON.parse(wire).outcome, 'capture-failed'); assert.doesNotMatch(wire, /secret/);
});
test('silent, absent track and suspended analysis remain distinct and clean up', async () => {
  for (const [options, expected] of [[{ signal: 0 }, 'silent-or-inaccessible'], [{ noTrack: true }, 'no-audio-track'], [{ suspended: true }, 'context-not-running']]) {
    const h = setup(options); const p = h.run(); h.finish(); assert.equal(JSON.parse(await p).outcome, expected);
    assert.equal(h.stats().closed, 1); assert.equal(h.stats().timers, 0);
  }
});
test('page exit and analysis failures release all resources', async () => {
  const h = setup(); const p = h.run(); h.exit(); assert.equal(JSON.parse(await p).outcome, 'page-exit'); assert.equal(h.stats().closed, 1);
  const f = setup({ analysisError: true }); assert.equal(JSON.parse(await f.run()).outcome, 'analysis-error'); assert.equal(f.stats().timers, 0); assert.equal(f.stats().closed, 1);
});
test('concurrent injection shares one capture and a later test can run again', async () => {
  const h = setup(); const first = h.run(), second = h.run(); h.finish(); assert.equal(await first, await second); assert.equal(h.stats().captures, 1);
  const third = h.run(); h.finish(); await third; assert.equal(h.stats().captures, 2);
});

test('completed results survive the initiating popup and recovery does not recapture', async () => {
  const h = setup(); assert.equal(h.recover().outcome, 'not-tested');
  const p = h.run(); assert.equal(h.recover().outcome, 'pending'); h.finish(); await p;
  assert.equal(h.recover().outcome, 'nonzero-samples'); assert.ok(h.recover().measuredAt);
  assert.equal(h.stats().captures, 1);
});
