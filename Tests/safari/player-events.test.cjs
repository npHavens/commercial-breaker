const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/player-events.js'), 'utf8');
function emitter() {
  const listeners = new Map();
  return {
    listeners,
    addEventListener(name, fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    removeEventListener(name, fn) { listeners.get(name)?.delete(fn); },
    emit(name) { for (const fn of listeners.get(name) || []) fn({ detail: { secret: 'never capture' } }); },
    count() { return [...listeners.values()].reduce((sum, group) => sum + group.size, 0); }
  };
}
function setup(exposed = true) {
  const video = emitter(), player = emitter(), document = emitter(), window = emitter();
  player.on = player.addEventListener; player.off = player.removeEventListener;
  document.querySelectorAll = () => [video];
  let expire, poll;
  const context = vm.createContext({ document, window,
    location: { protocol: 'https:', hostname: 'stream.directv.com' },
    videojs: exposed ? { getPlayers: () => ({ active: player }) } : undefined,
    setTimeout(fn) { expire = fn; return 1; }, clearTimeout() {},
    setInterval(fn) { poll = fn; return 2; }, clearInterval() {}
  });
  vm.runInContext(source, context);
  return { video, player, document, window, context,
    command: (action) => JSON.parse(context.commercialBreakerPlayerEvents(action)),
    reinject: () => vm.runInContext(source, context), expire: () => expire(), poll: () => poll() };
}

test('exposed player ad transitions and manual markers are recorded without payloads', () => {
  const h = setup(); h.command('start'); h.command('ad'); h.player.emit('adstart');
  h.player.emit('adend'); h.command('program'); h.command('stop');
  const report = h.command('export').report;
  assert.equal(report.coverage.videojsPlayers, 1);
  assert.deepEqual(report.entries.filter((e) => e.kind === 'event').map((e) => e.name), ['adstart', 'adend']);
  assert.equal(report.entries.filter((e) => e.kind === 'mark').length, 2);
  assert.equal(JSON.stringify(report).includes('secret'), false);
  assert.equal(h.player.count() + h.video.count() + h.document.count() + h.window.count(), 0);
});

test('reinjection and repeated start/poll do not duplicate subscriptions', () => {
  const h = setup(); h.command('start'); h.reinject(); h.command('start'); h.poll();
  h.player.emit('adstart');
  assert.equal(h.command('export').report.entries.filter((e) => e.name === 'adstart').length, 1);
  h.expire(); assert.equal(h.command('status').running, false);
  assert.equal(h.player.count(), 0);
});

test('absent player registry is reported as limited coverage, not absence of ads', () => {
  const h = setup(false); const result = h.command('start');
  assert.equal(result.coverage.videojsPlayers, 0);
  assert.equal(result.coverage.videojsRegistry, false);
  assert.match(result.coverage.limitation, /Private player/);
  h.document.emit('adbreakstart');
  assert.equal(h.command('export').report.entries.at(-1).name, 'adbreakstart');
});

test('event buffer is bounded and page exit stops listeners', () => {
  const h = setup(); h.command('start');
  for (let i = 0; i < 700; i++) h.player.emit('adstart');
  const result = h.command('status');
  assert.equal(result.count, 600); assert.ok(result.dropped > 0);
  h.window.emit('pagehide'); assert.equal(h.command('status').running, false);
  assert.equal(h.player.count(), 0);
});

test('lookalike domains cannot start subscriptions', () => {
  const h = setup(); h.context.location.hostname = 'directv.com.example.com';
  assert.equal(h.command('start').ok, false); assert.equal(h.player.count(), 0);
});

test('global discovery reports only names/types without invoking getters or inspecting values', () => {
  const h = setup(false);
  vm.runInContext(`
    Object.defineProperty(globalThis, 'QuickplayAccessor', { get() { throw new Error('getter invoked'); } });
    globalThis.freewheelManager = { token: 'private-token', get nested() { throw new Error('nested getter'); } };
    globalThis.QUICKPLAYFactory = function () { throw new Error('must not call'); };
    globalThis.freewheelNull = null;
    globalThis.unrelated = 'private-value';
  `, h.context);
  const report = h.command('start').coverage.globals;
  assert.equal(report.failed, false);
  assert.deepEqual(report.properties, [
    { name: 'QuickplayAccessor', type: 'accessor' },
    { name: 'freewheelManager', type: 'object' },
    { name: 'QUICKPLAYFactory', type: 'function' },
    { name: 'freewheelNull', type: 'null' }
  ]);
  assert.doesNotMatch(JSON.stringify(h.command('export')), /private-token|private-value/);
});

test('global discovery bounds scan size, output count and name length', () => {
  const h = setup(false);
  vm.runInContext(`
    globalThis['quickplay' + 'x'.repeat(200)] = {};
    for (let i = 0; i < 5100; i++) globalThis['freewheel' + i] = {};
  `, h.context);
  const report = h.command('start').coverage.globals;
  assert.equal(report.inspected, 5000);
  assert.equal(report.properties.length, 30);
  assert.equal(report.truncated, true);
  assert.ok(report.properties.every(p => p.name.length <= 160));
});

test('global discovery reports no matches and rescans on a new recording', () => {
  const h = setup(false);
  assert.deepEqual(h.command('start').coverage.globals.properties, []);
  h.command('stop');
  h.context.quickplayNew = {};
  assert.deepEqual(h.command('start').coverage.globals.properties, [{ name: 'quickplayNew', type: 'object' }]);
});

test('failed descriptor inspection is reported as incomplete discovery', () => {
  const h = setup(false);
  vm.runInContext(`
    globalThis.quickplayManager = {};
    Object.getOwnPropertyDescriptor = () => { throw new Error('unavailable'); };
  `, h.context);
  const result = h.command('start');
  assert.equal(result.coverage.globals.failed, true);
  assert.equal(result.running, true);
});

test('replacing an older recorder disposes its subscriptions', () => {
  const h = setup();
  h.command('start');
  delete h.context.commercialBreakerPlayerEvents.probeVersion;
  h.reinject();
  assert.equal(h.player.count() + h.video.count() + h.document.count() + h.window.count(), 0);
  h.command('start'); h.player.emit('adstart');
  assert.equal(h.command('export').report.entries.filter(e => e.name === 'adstart').length, 1);
});

const legacy = (name) => `skybox${name}`;

test('player event recorder is exposed as commercialBreakerPlayerEvents only', () => {
  const h = setup();
  assert.equal(typeof h.context.commercialBreakerPlayerEvents, 'function');
  assert.equal(h.context[legacy('PlayerEvents')], undefined);
});
