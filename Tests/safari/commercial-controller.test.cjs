const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../Tools/commercial-controller.js'), 'utf8');
const flush = () => new Promise(setImmediate);

function setup(initialMuted = false) {
  let clock = 100000;
  let classification = 'ad';
  let customFetch;
  let requests = 0;
  let result;
  const intervals = new Map(), timeouts = new Map();
  let nextId = 0;
  const listeners = new Map();
  const video = {
    muted: initialMuted, volume: 0.7, currentTime: 10, paused: false, readyState: 4,
    getStartDate: () => new Date(0),
    addEventListener(name, handler) { listeners.set(name, handler); },
    removeEventListener(name) { listeners.delete(name); }
  };
  const context = vm.createContext({
    AbortController, Date: class extends Date { static now() { return clock; } },
    setTimeout: (fn) => { const id = ++nextId; timeouts.set(id, fn); return id; },
    clearTimeout: (id) => timeouts.delete(id),
    setInterval: (fn) => { const id = ++nextId; intervals.set(id, fn); return id; },
    clearInterval: (id) => intervals.delete(id),
    fetch: async (...args) => {
      requests++;
      if (customFetch) return customFetch(...args);
      return { ok: true, json: async () => ({ state: classification, startMs: 0, endMs: 60000,
        sampledAtMs: clock, hasTimeline: true }) };
    }
  });
  vm.runInContext(source, context);
  const controller = context.skyboxCreateCommercialController(video, (value) => { result = value; });
  return { controller, video, listeners, intervals, timeouts,
    state: () => result, requests: () => requests, advance: (ms = 1000) => { clock += ms; },
    classify: (value) => { classification = value; }, fetch: (fn) => { customFetch = fn; } };
}

test('automatic mode is opt-in and mutes only through the marked break', async () => {
  const h = setup();
  await h.controller.tick();
  assert.equal(h.requests(), 0);
  h.controller.toggle(); await flush();
  assert.equal(h.video.muted, true);
  assert.equal(h.state().ownsMute, true);
  h.listeners.get('volumechange')();
  assert.equal(h.state().enabled, true, 'our asynchronous volume event is not a manual override');
  h.classify('program'); h.advance(); await h.controller.tick();
  assert.equal(h.video.muted, false);
  assert.equal(h.state().state, 'program');
  assert.equal(h.video.currentTime, 10);
  assert.equal(h.video.volume, 0.7);
  assert.equal(h.video.paused, false);
});

test('pre-existing manual mute is never claimed or removed', async () => {
  const h = setup(true);
  h.controller.toggle(); await flush();
  assert.equal(h.state().ownsMute, false);
  h.classify('program'); h.advance(); await h.controller.tick();
  h.controller.stop();
  assert.equal(h.video.muted, true);
});

test('manual unmute takes precedence and turns off automation', async () => {
  const h = setup(); h.controller.toggle(); await flush();
  h.controller.manualToggle();
  assert.equal(h.video.muted, false);
  assert.equal(h.state().enabled, false);
  h.advance(); await h.controller.tick();
  assert.equal(h.video.muted, false);
});

test('native volume changes disable automation and release its mute', async () => {
  const h = setup(); h.controller.toggle(); await flush();
  h.video.volume = 0.4;
  h.listeners.get('volumechange')();
  assert.equal(h.state().enabled, false);
  assert.equal(h.video.muted, false);
  assert.equal(h.video.volume, 0.4);
});

test('missing clock, unknown classification and request failures release an owned mute', async () => {
  for (const failure of ['clock', 'unknown', 'network', 'stale']) {
    const h = setup(); h.controller.toggle(); await flush();
    if (failure === 'clock') h.video.getStartDate = () => new Date(NaN);
    if (failure === 'unknown') h.classify('unknown');
    if (failure === 'network') h.fetch(async () => { throw new Error('failed'); });
    if (failure === 'stale') h.fetch(async () => ({ ok: true, json: async () => ({
      state: 'ad', startMs: 0, endMs: 60000, sampledAtMs: 0, hasTimeline: true
    }) }));
    h.advance(); await h.controller.tick();
    assert.equal(h.video.muted, false, failure);
    assert.equal(h.state().state, 'unknown', failure);
  }
});

test('late ad response cannot re-mute after seeking or disabling automation', async () => {
  for (const action of ['seek', 'disable']) {
    const h = setup();
    let deliver;
    h.fetch(() => new Promise((resolve) => { deliver = resolve; }));
    h.controller.toggle();
    if (action === 'seek') h.listeners.get('seeking')();
    else h.controller.stop();
    deliver({ ok: true, json: async () => ({ state: 'ad', startMs: 0, endMs: 60000,
      sampledAtMs: 100000, hasTimeline: true }) });
    await flush();
    assert.equal(h.video.muted, false, action);
  }
});

test('leaving a break releases mute even while the next request is pending', async () => {
  const h = setup(); h.controller.toggle(); await flush();
  let deliver;
  h.fetch(() => new Promise((resolve) => { deliver = resolve; }));
  h.advance();
  const pending = h.controller.tick();
  h.video.currentTime = 60;
  h.advance(); await h.controller.tick();
  assert.equal(h.video.muted, false);
  deliver({ ok: true, json: async () => ({ state: 'ad', startMs: 0, endMs: 60000,
    sampledAtMs: 102000, hasTimeline: true }) });
  await pending;
  assert.equal(h.video.muted, false);
});

test('disposing releases automatic mute and removes all listeners and timers', async () => {
  const h = setup(); h.controller.toggle(); await flush();
  h.controller.dispose();
  assert.equal(h.video.muted, false);
  assert.equal(h.listeners.size, 0);
  assert.equal(h.intervals.size, 0);
  assert.equal(h.timeouts.size, 0);
});
