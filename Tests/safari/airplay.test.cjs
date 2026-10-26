const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/airplay-session.js'), 'utf8');
function setup(hostname = 'stream.directv.com', supported = true) {
  const created = [];
  const observers = [];
  const timers = new Map();
  const pageListeners = {};
  let timerID = 0;
  class MutationObserver {
    constructor(callback) { this.callback = callback; this.active = false; observers.push(this); }
    observe(target) { this.target = target; this.active = true; }
    disconnect() { this.active = false; }
    deliver(records) { if (this.active) this.callback(records); }
  }
  function element(tag) {
    const e = { tag, style: {}, listeners: {}, children: [], attrs: new Map(), isConnected: false,
      append(...items) { this.children.push(...items); items.forEach((x) => { x.isConnected = true; }); },
      attachShadow() { this.shadow = element('shadow'); return this.shadow; },
      setAttribute(k, v) { this.attrs.set(k, v); }, getAttribute(k) { return this.attrs.get(k) ?? null; },
      hasAttribute(k) { return this.attrs.has(k); }, removeAttribute(k) { this.attrs.delete(k); },
      addEventListener(k, fn) { this.listeners[k] = fn; }, removeEventListener(k) { delete this.listeners[k]; },
      remove() { this.isConnected = false; },
      querySelectorAll() { return this.children.filter((child) => child.tag === 'source'); },
      getBoundingClientRect: () => ({ width: 640, height: 360, left: 0, top: 0, right: 640, bottom: 360 }) };
    created.push(e); return e;
  }
  const video = element('video'); video.currentSrc = 'blob:test'; video.paused = false; video.isConnected = true; video.readyState = 4;
  video.setAttribute('disableremoteplayback', ''); video.setAttribute('x-webkit-airplay', 'deny');
  let requests = 0;
  if (supported) video.webkitShowPlaybackTargetPicker = () => { requests++; };
  const context = vm.createContext({ addEventListener(name, fn) { pageListeners[name] = fn; },
    removeEventListener(name) { delete pageListeners[name]; },
    setTimeout(fn, ms) { const id = ++timerID; timers.set(id, { fn, ms }); return id; },
    clearTimeout(id) { timers.delete(id); }, MutationObserver, location: { protocol: 'https:', hostname },
    document: { createElement: element, documentElement: element('html'), querySelectorAll: () => [video] },
    innerHeight: 720, innerWidth: 1280, getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    commercialBreakerSelectVideo: (candidates) => candidates[0].element });
  const run = () => vm.runInContext(source, context);
  return { run, video, created, context, observers, element, timers, pageListeners, fire(ms) {
    for (const [id, timer] of [...timers]) if (timer.ms === ms) { timers.delete(id); timer.fn(); }
  }, requests: () => requests };
}

for (const hostname of ['stream.directv.com', 'www.paramountplus.com', 'paramountplus.com']) {
test(`${hostname}: picker requires a page click; closing restores original attributes`, () => {
  const h = setup(hostname); assert.equal(h.run().ok, true);
  assert.equal(h.requests(), 0);
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'deny');
  const buttons = h.created.filter((e) => e.tag === 'button');
  buttons[0].listeners.click();
  assert.equal(h.requests(), 1);
  assert.equal(h.video.hasAttribute('disableremoteplayback'), false);
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'allow');
  h.run(); assert.equal(h.created.filter((e) => e.tag === 'button').length, 3);
  buttons[1].listeners.click();
  assert.equal(h.video.getAttribute('disableremoteplayback'), '');
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'deny');
  assert.equal(h.video.hasAttribute('x-webkit-wirelessvideoplaybackdisabled'), false);
  assert.equal(h.context.commercialBreakerAirPlayPanel, undefined);
});

}

test('unsupported API leaves video attributes unchanged', () => {
  const h = setup('stream.directv.com', false); h.run();
  h.created.find((e) => e.tag === 'button').listeners.click();
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'deny');
  assert.match(h.created.find((e) => e.tag === 'p').textContent, /unavailable/);
});

test('other websites are rejected before adding a panel', () => {
  for (const hostname of ['directv.com.example.com', 'paramountplus.com.example.com', 'fakeparamountplus.com']) {
    assert.equal(setup(hostname).run().ok, false);
  }
});

function start(h) {
  h.run();
  h.created.find((e) => e.tag === 'button').listeners.click();
  return h.created.find((e) => e.tag === 'textarea');
}

test('site attribute resets are corrected, bounded, and stopped on close', () => {
  const h = setup('www.paramountplus.com');
  const log = start(h);
  const observer = h.observers[0];
  for (let n = 0; n < 10; n++) {
    h.video.setAttribute('disableremoteplayback', '');
    observer.deliver([{ type: 'attributes', attributeName: 'disableremoteplayback' }]);
    assert.equal(h.video.hasAttribute('disableremoteplayback'), false);
    const history = log.value;
    observer.deliver([{ type: 'attributes', attributeName: 'disableremoteplayback' }]);
    assert.equal(log.value, history, 'our own writes must not be counted as site resets');
  }
  h.video.setAttribute('x-webkit-airplay', 'deny');
  observer.deliver([{ type: 'attributes', attributeName: 'x-webkit-airplay' }]);
  assert.equal(observer.active, false);
  assert.match(log.value, /stopped reapplying/);
  h.created.filter((e) => e.tag === 'button')[1].listeners.click();
  assert.ok(h.observers.every((item) => !item.active));
  assert.deepEqual(Object.keys(h.video.listeners), []);
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'deny');
});

test('a brief wireless connection and subsequent failure both remain in history', () => {
  const h = setup(); const log = start(h);
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.video.webkitCurrentPlaybackTargetIsWireless = false;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.video.error = { code: 4, message: 'private stream URL' };
  h.video.listeners.error({});
  assert.match(log.value, /wireless=true/);
  assert.match(log.value, /wireless=false/);
  assert.match(log.value, /error=4/);
  assert.doesNotMatch(log.value, /private stream URL|blob:test/);
});

test('network alternatives suppress the blob-only warning without changing sources', () => {
  const h = setup();
  const source = h.element('source'); source.src = 'https://example.com/private.m3u8?token=secret';
  h.video.append(source);
  const log = start(h);
  assert.match(log.value, /network alternatives=1/);
  assert.doesNotMatch(log.value, /no network alternative|secret|example.com/);
  assert.equal(h.video.currentSrc, 'blob:test');
  assert.equal(h.video.children[0], source);
});

test('removed video is reported and observers stop; retry can select its replacement', () => {
  const h = setup(); const log = start(h);
  h.video.isConnected = false;
  h.observers[1].deliver([{ type: 'childList' }]);
  assert.match(log.value, /video was removed/);
  assert.ok(h.observers.every((item) => !item.active));
  const replacement = h.element('video');
  replacement.currentSrc = 'https://example.com/live.m3u8';
  replacement.webkitShowPlaybackTargetPicker = () => {};
  h.context.document.querySelectorAll = () => [replacement];
  h.created.find((e) => e.tag === 'button').listeners.click();
  assert.equal(replacement.getAttribute('x-webkit-airplay'), 'allow');
  h.created.filter((e) => e.tag === 'button')[1].listeners.click();
  assert.equal(replacement.hasAttribute('x-webkit-airplay'), false);
});

test('old connected panel produces an actionable error instead of silently using stale code', () => {
  const h = setup();
  h.context.commercialBreakerAirPlayPanel = { isConnected: true };
  assert.match(h.run().error, /Close the old page panel/);
  assert.equal(h.requests(), 0);
});

function routing(h) {
  start(h);
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  h.created.find(e => e.textContent === 'Test return route (15 seconds)').listeners.click();
}

test('route test does not fight attribute observer and detects local then wireless without another picker', () => {
  const h = setup(); routing(h);
  h.observers[0].deliver([{ type: 'attributes', attributeName: 'disableremoteplayback' }]);
  assert.equal(h.video.hasAttribute('disableremoteplayback'), true);
  h.video.webkitCurrentPlaybackTargetIsWireless = false;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.fire(5000);
  assert.equal(h.video.hasAttribute('disableremoteplayback'), false);
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.fire(10000);
  const result = JSON.parse(h.context.commercialBreakerAirPlayRouteResult);
  assert.equal(result.sawLocal, true);
  assert.equal(result.sawReturn, true);
  assert.match(result.message, /Verify TV/);
  assert.equal(h.requests(), 1);
  assert.equal(h.timers.size, 0);
});

test('staying wireless is not a successful round trip', () => {
  const h = setup(); routing(h); h.fire(5000); h.fire(10000);
  assert.match(JSON.parse(h.context.commercialBreakerAirPlayRouteResult).message, /No local playback transition/);
});

test('local playback without reconnect reports failure without opening a picker', () => {
  const h = setup(); routing(h);
  h.video.webkitCurrentPlaybackTargetIsWireless = false;
  h.fire(5000); h.fire(10000);
  assert.match(JSON.parse(h.context.commercialBreakerAirPlayRouteResult).message, /no automatic TV return/);
  assert.equal(h.requests(), 1);
});

test('closing mid-test restores attributes and cancels delayed changes', () => {
  const h = setup(); routing(h);
  h.created.find(e => e.textContent === 'Restore settings and close').listeners.click();
  assert.equal(h.timers.size, 0);
  assert.equal(h.video.getAttribute('x-webkit-airplay'), 'deny');
  assert.equal(h.video.getAttribute('disableremoteplayback'), '');
});

test('replacement player makes route test inconclusive and clears timers', () => {
  const h = setup(); routing(h);
  h.video.isConnected = false;
  h.observers[1].deliver([{ type: 'childList' }]);
  assert.equal(h.timers.size, 0);
  assert.match(JSON.parse(h.context.commercialBreakerAirPlayRouteResult).message, /Inconclusive/);
});

test('page exit cancels the routing timers and restores enabled remote playback', () => {
  const h = setup(); routing(h);
  h.pageListeners.pagehide();
  assert.equal(h.timers.size, 0);
  assert.equal(h.video.hasAttribute('disableremoteplayback'), false);
  assert.match(JSON.parse(h.context.commercialBreakerAirPlayRouteResult).message, /Page left/);
});

test('DIRECTV resets presentation tracks before picker and on every TV return, then restores on close', () => {
  const h = setup();
  const captions = { kind: 'captions', mode: 'showing' };
  const subtitles = { kind: 'subtitles', mode: 'hidden' };
  const metadata = { kind: 'metadata', mode: 'hidden' };
  h.video.textTracks = [captions, subtitles, metadata];
  h.video.webkitClosedCaptionsVisible = true;
  h.video.webkitShowPlaybackTargetPicker = () => {
    assert.equal(captions.mode, 'disabled');
    assert.equal(h.video.webkitClosedCaptionsVisible, false);
  };
  start(h);
  assert.equal(subtitles.mode, 'disabled');
  assert.equal(metadata.mode, 'hidden');
  for (let i = 0; i < 2; i++) {
    captions.mode = 'showing';
    h.video.webkitClosedCaptionsVisible = true;
    h.video.webkitCurrentPlaybackTargetIsWireless = true;
    h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
    assert.equal(captions.mode, 'disabled');
    assert.equal(h.video.webkitClosedCaptionsVisible, false);
  }
  h.created.find(e => e.textContent === 'Restore settings and close').listeners.click();
  assert.equal(captions.mode, 'showing');
  assert.equal(subtitles.mode, 'hidden');
  assert.equal(h.video.webkitClosedCaptionsVisible, true);
});

test('caption control failures do not prevent picker and Paramount tracks remain unchanged', () => {
  const h = setup();
  h.video.textTracks = [{ kind: 'captions', get mode() { return 'showing'; }, set mode(_) { throw Error('unsupported'); } }];
  start(h);
  assert.equal(h.requests(), 1);
  const p = setup('www.paramountplus.com');
  p.video.textTracks = [{ kind: 'captions', mode: 'showing' }];
  start(p);
  assert.equal(p.video.textTracks[0].mode, 'showing');
});

test('playback export correlates stalls and wireless changes without URLs, cues or invalid numbers', () => {
  const h = setup();
  h.video.currentSrc = 'https://private.example/stream?token=secret';
  h.video.currentTime = Infinity;
  h.video.textTracks = [{ kind: 'captions', mode: 'disabled', label: 'private label', cues: ['private words'] }];
  start(h);
  h.video.listeners.waiting({});
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.video.listeners.timeupdate({});
  const json = h.context.commercialBreakerExportAirPlayPlayback();
  const report = JSON.parse(json);
  assert.ok(report.events.some(e => e.event.startsWith('waiting')));
  assert.ok(report.events.some(e => e.video?.wireless));
  assert.ok(report.events.some(e => e.event === 'progress'));
  assert.equal(report.events.at(-1).video.time, null);
  assert.doesNotMatch(json, /private|secret|Infinity/);
  for (let i = 0; i < 1300; i++) h.video.listeners.stalled({});
  assert.equal(JSON.parse(h.context.commercialBreakerExportAirPlayPlayback()).events.length, 1200);
  h.created.find(e => e.textContent === 'Restore settings and close').listeners.click();
  assert.deepEqual(Object.keys(h.video.listeners), []);
  assert.equal(typeof h.context.commercialBreakerExportAirPlayPlayback(), 'string');
});

const legacy = (name) => `skybox${name}`;

test('page bridge globals use the commercialBreaker names and leave no legacy skybox names', () => {
  const h = setup(); routing(h);
  assert.equal(typeof h.context.commercialBreakerAirPlayPanel, 'object');
  assert.equal(h.context.commercialBreakerAirPlayPanel.commercialBreakerVersion, '0.1.11');
  assert.equal(h.context.commercialBreakerAirPlayPanel[legacy('Version')], undefined);
  assert.equal(typeof h.context.commercialBreakerExportAirPlayPlayback, 'function');
  h.video.webkitCurrentPlaybackTargetIsWireless = false;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.fire(5000);
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  h.video.listeners.webkitcurrentplaybacktargetiswirelesschanged({});
  h.fire(10000);
  assert.equal(typeof h.context.commercialBreakerAirPlayRouteResult, 'string');
  for (const name of ['AirPlayPanel', 'ExportAirPlayPlayback', 'AirPlayRouteResult']) {
    assert.equal(h.context[legacy(name)], undefined);
  }
});
