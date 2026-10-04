const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/diagnostics.js'), 'utf8');

function harness() {
  let now = 1000;
  const timers = new Set();
  const ad = {
    classList: ['player', 'ad-break'], id: '', tagName: 'DIV',
    getAttribute: () => 'Advertisement',
    getBoundingClientRect: () => ({ width: 100, height: 20, top: 0, left: 0, right: 100, bottom: 20 })
  };
  const context = vm.createContext({
    Date: class extends Date { static now() { return now; } },
    location: { protocol: 'https:', hostname: 'www.paramountplus.com' },
    document: { querySelectorAll: (selector) => selector === 'video' ? [] : [ad] },
    innerHeight: 720, innerWidth: 1280,
    getComputedStyle: () => ({ visibility: 'visible', display: 'block', opacity: '1' }),
    setInterval: (callback) => { timers.add(callback); return callback; },
    clearInterval: (id) => timers.delete(id)
  });
  vm.runInContext(source, context);
  return {
    context, timers, command: context.skyboxDiagnostics,
    advance(ms) { now += ms; for (const callback of [...timers]) callback(); },
    reinject() { vm.runInContext(source, context); }
  };
}

test('recording survives reinjection and captures signals alongside manual marks', () => {
  const h = harness();
  assert.equal(h.command('ad').ok, false);
  h.command('start'); h.reinject(); h.command('start');
  assert.equal(h.timers.size, 1);
  h.command('ad'); h.command('program');
  const report = h.command('export').report;
  assert.equal(report.entries.filter((e) => e.kind === 'start').length, 1);
  assert.equal(report.entries.filter((e) => e.kind === 'mark').length, 2);
  assert.equal(report.entries.find((e) => e.kind === 'sample').signals[0].label, 'Advertisement');
  h.command('stop');
  assert.equal(h.timers.size, 0);
  const count = h.command('status').count;
  h.advance(1000);
  assert.equal(h.command('status').count, count);
});

test('recording automatically stops after 15 minutes and a new run resets data', () => {
  const h = harness(); h.command('start'); h.advance(15 * 60 * 1000);
  assert.equal(h.command('status').running, false);
  assert.equal(h.command('export').report.entries.at(-1).reason, '15-minute limit');
  h.command('start');
  assert.equal(h.command('status').count, 2);
});

test('recordings are bounded even with repeated manual markers', () => {
  const h = harness(); h.command('start');
  for (let i = 0; i < 700; i++) h.command('ad');
  assert.equal(h.command('status').count, 1200);
  assert.ok(h.command('status').dropped > 0);
});

test('diagnostics refuses other sites', () => {
  const h = harness(); h.context.location.hostname = 'example.com';
  assert.equal(h.command('start').ok, false);
  assert.equal(h.timers.size, 0);
});

test('non-finite media and cue times become null without discarding finite cues', () => {
  const h = harness();
  const video = {
    classList: [], paused: false, ended: false, muted: false,
    volume: NaN, readyState: 4, currentTime: NaN, duration: Infinity,
    getBoundingClientRect: () => ({ width: 100, height: 100, top: 0, left: 0, right: 100, bottom: 100 }),
    textTracks: [{ kind: 'metadata', mode: 'hidden', activeCues: [
      { startTime: 12, endTime: Infinity }, { startTime: NaN, endTime: -Infinity },
      { startTime: 20, endTime: 25 }
    ] }]
  };
  h.context.document.querySelectorAll = (selector) => selector === 'video' ? [video] : [];
  h.command('start');
  const sample = h.command('export').report.entries.find((entry) => entry.kind === 'sample').videos[0];
  assert.equal(sample.volume, null);
  assert.equal(sample.currentTime, null);
  assert.equal(sample.duration, null);
  assert.equal(sample.tracks[0].activeCues[0].end, null);
  assert.equal(sample.tracks[0].activeCues[1].start, null);
  assert.equal(sample.tracks[0].activeCues[1].end, null);
  assert.equal(sample.tracks[0].activeCues[2].end, 25);
});

test('DIRECTV recordings include service identity and reject lookalike domains', () => {
  const h = harness();
  h.context.location.hostname = 'stream.directv.com';
  assert.equal(h.command('start').running, true);
  h.command('ad'); h.command('program'); h.command('stop');
  const report = h.command('export').report;
  assert.equal(report.service, 'directv');
  assert.equal(report.entries.filter((entry) => entry.kind === 'mark').length, 2);
  h.context.location.hostname = 'directv.com.example.com';
  assert.equal(h.command('start').ok, false);
  assert.equal(h.timers.size, 0);
});
