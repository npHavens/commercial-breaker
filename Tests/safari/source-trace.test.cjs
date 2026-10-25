const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const source = readFileSync('SafariExtension/airplay-source-trace.js', 'utf8');
function setup() {
  const listeners = new Map();
  class Element { setAttribute(name, value) { this[name + 'Attribute'] = value; return 17; } removeAttribute() {} }
  class HTMLMediaElement extends Element {
    load() { if (this.failure) throw this.failure; this.loads = (this.loads || 0) + 1; return 42; }
    set src(value) { this.stored = value; } get src() { return this.stored; }
    set srcObject(value) { this.object = value; }
  }
  class HTMLVideoElement extends HTMLMediaElement {}
  class HTMLSourceElement extends Element { set src(value) { this.stored = value; } }
  const original = HTMLMediaElement.prototype.load;
  const context = vm.createContext({ Element, HTMLMediaElement, HTMLVideoElement, HTMLSourceElement, URL,
    location: { protocol: 'https:', hostname: 'stream.directv.com' },
    document: { addEventListener: (n, f) => listeners.set(n, f), removeEventListener: n => listeners.delete(n) },
    addEventListener: (n, f) => listeners.set(n, f), removeEventListener: n => listeners.delete(n),
    setTimeout: () => 1, clearTimeout() {} });
  vm.runInContext(source, context);
  return { context, original, HTMLMediaElement, HTMLVideoElement, listeners,
    read: () => JSON.parse(context.commercialBreakerAirPlaySourceTrace.export()) };
}
test('trace preserves receivers, values, return values and thrown errors without exporting sources', () => {
  const h = setup(), video = new h.HTMLVideoElement(); h.context.video = video;
  vm.runInContext("video.src = 'https://private.example/token'; video.load(); video.setAttribute('src', 'secret')", h.context,
    { filename: 'https://stream.directv.com/private-session/player.js?token=secret' });
  assert.equal(video.src, 'https://private.example/token'); assert.equal(video.loads, 1);
  assert.equal(video.load(), 42); assert.equal(video.setAttribute('src', 'value'), 17);
  const failure = new Error('private'); video.failure = failure;
  assert.throws(() => video.load(), e => e === failure);
  const report = h.read(); assert.equal(report.events.length, 6);
  assert.ok(report.events[0].callers.some(c => c.origin === 'https://stream.directv.com'));
  assert.doesNotMatch(JSON.stringify(report), /secret|private-session|private.example/);
  h.listeners.get('skybox-airplay-trace-stop')();
  assert.equal(h.HTMLMediaElement.prototype.load, h.original);
  assert.equal(h.read().running, false); assert.equal(h.listeners.size, 0);
});
test('ring is bounded, reinjection does not stack hooks, cleanup preserves later replacements', () => {
  const h = setup(), video = new h.HTMLVideoElement();
  const hook = h.HTMLMediaElement.prototype.load; vm.runInContext(source, h.context);
  assert.equal(h.HTMLMediaElement.prototype.load, hook);
  for (let i = 0; i < 650; i++) video.load();
  assert.equal(h.read().events.length, 600); assert.equal(h.read().dropped, 50);
  const later = () => 'later'; h.HTMLMediaElement.prototype.load = later;
  h.listeners.get('pagehide')(); assert.equal(h.HTMLMediaElement.prototype.load, later);
});

const legacy = (name) => `skybox${name}`;

test('source trace is exposed as commercialBreakerAirPlaySourceTrace only', () => {
  const h = setup();
  assert.equal(typeof h.context.commercialBreakerAirPlaySourceTrace.export, 'function');
  assert.equal(h.context[legacy('AirPlaySourceTrace')], undefined);
});