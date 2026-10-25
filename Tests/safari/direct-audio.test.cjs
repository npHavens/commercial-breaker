const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const read = name => fs.readFileSync(path.join(__dirname, '../../SafariExtension', name), 'utf8');
function setup({ value = 0.2, blocked = false, suspend = false } = {}) {
  const elements = [], timers = new Map(), events = new Map(); let id = 0, creates = 0, closes = 0, disconnects = 0;
  const node = () => ({ connect() {}, disconnect() { disconnects++; } });
  const video = Object.freeze({ paused: false, ended: false, muted: false, webkitCurrentPlaybackTargetIsWireless: false,
    getBoundingClientRect: () => ({ width: 100, height: 100, top: 0, left: 0, bottom: 100, right: 100 }) });
  class Context {
    constructor() { this.state = suspend ? 'suspended' : 'running'; this.destination = {}; }
    resume() { return suspend ? new Promise(() => {}) : Promise.resolve(); }
    close() { closes++; return Promise.resolve(); }
    createAnalyser() { return { ...node(), fftSize: 2048, getFloatTimeDomainData(a) { a.fill(value); } }; }
    createMediaElementSource() { creates++; if (blocked) throw new Error('blocked'); return node(); }
  }
  const document = {
    querySelectorAll: () => [video], getElementById: id => elements.find(e => e.id === id),
    documentElement: { append() {} }, createElement(tag) {
      const e = { tag, style: {}, handlers: {}, append() {}, addEventListener(n, f) { this.handlers[n] = f; } };
      elements.push(e); return e;
    }
  };
  const context = vm.createContext({ document, AudioContext: Context, Float32Array,
    location: { protocol: 'https:', hostname: 'stream.directv.com' }, innerHeight: 1000, innerWidth: 1000,
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    window: { addEventListener: (n, f) => events.set(n, f) },
    setTimeout: f => { timers.set(++id, f); return id; }, clearTimeout: i => timers.delete(i),
    setInterval: f => { timers.set(++id, f); return id; }, clearInterval: i => timers.delete(i)
  });
  vm.runInContext(read('select-video.js'), context); vm.runInContext(read('direct-audio.js'), context);
  return { context, elements, click: () => elements.find(e => e.textContent === 'Start direct audio test').handlers.click(),
    deadline: () => [...timers.values()].at(-1)(), exit: () => events.get('pagehide')(),
    stats: () => ({ creates, closes, disconnects, timers: timers.size }),
    result: () => JSON.parse(context.commercialBreakerLastAudioProbeResult), reinject: () => vm.runInContext(read('direct-audio.js'), context) };
}
test('requires a page click and preserves the audible graph after measurement', async () => {
  const h = setup(); assert.equal(h.stats().creates, 0); await h.click(); h.deadline();
  assert.equal(h.result().outcome, 'nonzero-samples'); assert.equal(h.stats().closes, 0);
  assert.equal(h.stats().disconnects, 0); assert.equal(h.stats().timers, 0);
  await h.click(); h.deadline(); assert.equal(h.stats().creates, 1);
  h.exit(); assert.equal(h.stats().closes, 1); assert.equal(h.stats().disconnects, 2);
});
test('silence is inconclusive and a rejected binding closes unused context', async () => {
  const h = setup({ value: 0 }); await h.click(); h.deadline(); assert.equal(h.result().outcome, 'silent-or-inaccessible');
  const f = setup({ blocked: true }); await f.click(); assert.equal(f.result().outcome, 'analysis-error'); assert.equal(f.stats().closes, 1); assert.equal(f.stats().timers, 0);
});
test('suspended resume times out without binding or leaking a context', () => {
  const h = setup({ suspend: true }); h.click(); h.deadline();
  assert.equal(h.result().outcome, 'context-not-running'); assert.equal(h.stats().creates, 0); assert.equal(h.stats().closes, 1);
});

const legacy = (name) => `skybox${name}`;

test('direct audio result and video selector use the commercialBreaker names only', async () => {
  const h = setup(); await h.click(); h.deadline();
  assert.equal(typeof h.context.commercialBreakerSelectVideo, 'function');
  assert.equal(typeof h.context.commercialBreakerLastAudioProbeResult, 'string');
  for (const name of ['SelectVideo', 'LastAudioProbeResult']) assert.equal(h.context[legacy(name)], undefined);
});