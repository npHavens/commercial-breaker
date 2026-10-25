const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/popup.js'), 'utf8');
const html = readFileSync(resolve(__dirname, '../../SafariExtension/popup.html'), 'utf8');

async function setup(failure, storage = new Map(), url = 'https://www.paramountplus.com/live-tv/', diagnosticResult) {
  const nodes = new Map([...html.matchAll(/id="([^"]+)"/g)].map((match) => [match[1], {
    hidden: true, disabled: false, textContent: '', listeners: {}, parentElement: {},
    addEventListener(event, callback) { (this.listeners[event] ??= []).push(callback); }
  }]));
  const calls = [];
  const context = vm.createContext({
    localStorage: { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
    URL, setTimeout, clearTimeout, document: { querySelector: (selector) => nodes.get(selector.slice(1)) },
    browser: {
      tabs: { query: async () => [{ id: 7, url }] },
      scripting: { executeScript: async (options) => {
        calls.push(options);
        if (options.func?.toString().includes('commercialBreakerExportAirPlayPlayback')) {
          return [{ result: JSON.stringify({ kind: 'airplay-playback', events: [] }) }];
        }
        if (options.func?.toString().includes('commercialBreakerAirPlaySourceTrace')) {
          return [{ result: JSON.stringify({ running: true, events: [{ operation: 'HTMLMediaElement.load()' }] }) }];
        }
        if (options.world === 'MAIN' && options.func) {
          return [{ result: vm.runInNewContext(`(${options.func.toString()})(action)`, {
            action: options.args[0], commercialBreakerPlayerEvents: () => JSON.stringify({ ok: true,
              running: true, count: 1, coverage: { videojsPlayers: 0, videoElements: 2 } })
          }) }];
        }
        if (options.files?.includes('frame-probe.js')) {
          return [{ result: JSON.stringify({ ok: false, outcome: 'access-blocked', wireless: true }) }];
        }
        if (options.files?.includes('audio-probe.js')) {
          if (failure === 'audio-hang') return new Promise(() => {});
          return [{ result: undefined }];
        }
        if (options.func?.toString().includes('commercialBreakerLastAudioProbeResult')) {
          return [{ result: vm.runInNewContext(`(${options.func.toString()})()`, {
            commercialBreakerLastAudioProbeResult: JSON.stringify({ outcome: 'unsupported', measuredAt: '2026-09-20T23:00:00Z' })
          }) }];
        }
        if (options.files?.includes('metadata-probe.js')) {
          return [{ result: JSON.stringify({ ok: true, report: {
            probe: 'metadata-shape', entries: [{ kind: 'metadata-snapshot', videos: [] }]
          } }) }];
        }
        if (options.files?.includes('airplay-session.js')) {
          if (failure) throw new Error(failure);
          return [{ result: { ok: true } }];
        }
        if (options.func && typeof options.args?.[0] === 'string' &&
            !options.args[0].startsWith('toggle-')) {
          const result = vm.runInNewContext(`(${options.func.toString()})(action)`, {
            action: options.args[0],
            commercialBreakerDiagnostics: () => diagnosticResult ?? { ok: true, running: false, count: 0 }
          });
          return [{ result }];
        }
        return [{ result: { ok: true, running: false, count: 0, muted: false, volume: 0.8 } }];
      } }
    }
  });
  vm.runInContext(readFileSync(resolve(__dirname, '../../SafariExtension/relay-target.js'), 'utf8'), context);
  vm.runInContext(source, context);
  await new Promise(setImmediate);
  return { nodes, calls, storage };
}

test('Paramount+ popup exposes AirPlay and wires the click to page injection', async () => {
  const { nodes, calls } = await setup();
  assert.equal(nodes.get('airplay-controls').hidden, false);
  assert.equal(nodes.get('build-status').textContent, 'v0.2.21 · Controls ready');
  await nodes.get('airplay').listeners.click[0]();
  assert.ok(calls.some((call) => call.files?.includes('airplay-session.js') && call.target.tabId === 7));
  assert.match(nodes.get('airplay-status').textContent, /Close this popup/);
  assert.equal(nodes.get('airplay').disabled, false);
});

test('export crosses the native bridge as text even with non-finite values in an older recorder', async () => {
  const report = { entries: [{ videos: [{ tracks: [{ activeCues: [{ start: NaN, end: Infinity }] }] }] }] };
  const { nodes, calls } = await setup(undefined, new Map(), 'https://stream.directv.com/watch',
    { ok: true, running: false, count: 1, report });
  await nodes.get('export').listeners.click[0]();
  const call = calls.find((item) => item.args?.[0] === 'export');
  const wire = vm.runInNewContext(`(${call.func.toString()})('export')`, {
    commercialBreakerDiagnostics: () => ({ ok: true, report })
  });
  assert.equal(typeof wire, 'string');
  assert.equal(nodes.get('export-panel').hidden, false);
  const saved = JSON.parse(nodes.get('recording-json').value);
  assert.deepEqual(saved.entries[0].videos[0].tracks[0].activeCues[0], { start: null, end: null });
});

test('AirPlay injection errors are shown and the button can be retried', async () => {
  const { nodes } = await setup('Page access denied');
  await nodes.get('airplay').listeners.click[0]();
  assert.equal(nodes.get('airplay-status').textContent, 'Page access denied');
  assert.equal(nodes.get('airplay').disabled, false);
});

test('DIRECTV exposes recording and manual controls alongside AirPlay', async () => {
  const { nodes, calls } = await setup(undefined, new Map(), 'https://stream.directv.com/watch');
  assert.equal(nodes.get('paramount-controls').hidden, false);
  assert.equal(nodes.get('airplay-controls').hidden, false);
  await nodes.get('record').listeners.click[0]();
  assert.ok(calls.some((call) => call.files?.includes('diagnostics.js')));
  assert.ok(calls.some((call) => call.args?.[0] === 'start'));
  await nodes.get('toggle').listeners.click[0]();
  assert.ok(calls.some((call) => call.args?.[0] === true));
});

test('metadata inspection fills the save panel without starting or stopping a recording', async () => {
  const { nodes, calls } = await setup(undefined, new Map(), 'https://stream.directv.com/watch');
  calls.length = 0;
  await nodes.get('inspect-metadata').listeners.click[0]();
  assert.equal(nodes.get('export-panel').hidden, false);
  assert.equal(JSON.parse(nodes.get('recording-json').value).probe, 'metadata-shape');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].files[0], 'metadata-probe.js');
  assert.equal(nodes.get('inspect-metadata').disabled, false);
});

test('frame access failure is visible and exportable without changing playback', async () => {
  const { nodes, calls } = await setup(undefined, new Map(), 'https://stream.directv.com/watch');
  calls.length = 0;
  await nodes.get('test-frame').listeners.click[0]();
  assert.match(nodes.get('frame-status').textContent, /blocked pixel readback/);
  assert.equal(nodes.get('frame-preview').hidden, true);
  assert.equal(JSON.parse(nodes.get('recording-json').value).entries[0].outcome, 'access-blocked');
  assert.equal(calls.length, 2);
  assert.equal(nodes.get('test-frame').disabled, false);
});

test('event test requests MAIN world and reports inaccessible player coverage', async () => {
  const { nodes, calls } = await setup(undefined, new Map(), 'https://stream.directv.com/watch');
  calls.length = 0;
  await nodes.get('event-start').listeners.click[0]();
  assert.equal(calls.length, 2);
  assert.ok(calls.every((call) => call.world === 'MAIN'));
  assert.equal(calls[1].args[0], 'start');
  assert.match(nodes.get('event-status').textContent, /0 exposed Video.js players/);
  assert.match(nodes.get('event-status').textContent, /internal player events may be inaccessible/);
});

test('AirPlay failure history survives closing and reopening the popup', async () => {
  const first = await setup('Page access denied');
  await first.nodes.get('airplay').listeners.click[0]();
  const reopened = await setup(undefined, first.storage);
  assert.match(reopened.nodes.get('airplay-history').textContent, /Button clicked/);
  assert.match(reopened.nodes.get('airplay-history').textContent, /Error: Page access denied/);
});

test('relay tab exposes its controls and sends automatic-mode commands to the existing player', async () => {
  const url = `http://192.168.1.10:8765/session/${'a'.repeat(43)}/`;
  const { nodes, calls } = await setup(undefined, new Map(), url);
  assert.equal(nodes.get('relay-controls').hidden, false);
  assert.equal(nodes.get('paramount-controls').hidden, true);
  assert.equal(nodes.get('airplay-controls').hidden, true);
  await nodes.get('relay-auto').listeners.click[0]();
  assert.ok(calls.some((call) => call.files?.includes('relay-controls.js')));
  assert.ok(calls.some((call) => call.args?.[0] === 'toggle-auto'));
  assert.ok(!calls.some((call) => call.files?.includes('diagnostics.js')));
});

test('audio test reports unsupported capture and exports measurements without toggling mute', async () => {
  const storage = new Map();
  const { nodes, calls } = await setup(undefined, storage, 'https://stream.directv.com/player');
  calls.length = 0;
  await nodes.get('test-audio').listeners.click[0]();
  assert.match(nodes.get('audio-status').textContent, /does not expose/);
  assert.equal(nodes.get('test-audio').disabled, false);
  assert.equal(JSON.parse(nodes.get('recording-json').value).probe, 'audio-access');
  assert.deepEqual(calls.filter(c => c.files).map(c => Array.from(c.files)), [['select-video.js'], ['audio-probe.js']]);
  assert.equal(calls.filter(c => c.func).length, 1);
  const reopened = await setup(undefined, storage, 'https://stream.directv.com/player');
  assert.match(reopened.nodes.get('audio-status').textContent, /Previous attempt:.*does not expose/);
});

test('audio bridge timeout restores the button and reports uncertainty', async () => {
  const { nodes } = await setup('audio-hang', new Map(), 'https://stream.directv.com/player');
  await nodes.get('test-audio').listeners.click[0]();
  assert.match(nodes.get('audio-status').textContent, /No response.*still unknown/);
  assert.equal(nodes.get('test-audio').disabled, false);
});

test('last audio result is retrieved without starting another probe', async () => {
  const { nodes, calls } = await setup(); calls.length = 0;
  await nodes.get('read-audio').listeners.click[0]();
  assert.equal(calls.length, 1);
  assert.equal(typeof calls[0].func, 'function');
  assert.match(nodes.get('audio-status').textContent, /does not expose.*Measured at/);
});


test('AirPlay export merges MAIN source trace with isolated playback events', async () => {
  const { nodes, calls } = await setup();
  await nodes.get('airplay-export').listeners.click[0]();
  const report = JSON.parse(nodes.get('recording-json').value);
  assert.equal(report.kind, 'airplay-playback');
  assert.equal(report.sourceTrace.events[0].operation, 'HTMLMediaElement.load()');
  assert.ok(calls.some(c => c.world === 'MAIN' && c.func?.toString().includes('commercialBreakerAirPlaySourceTrace')));
});

const legacy = (name) => `skybox${name}`;

test('popup injects the commercialBreaker names and never the legacy skybox names', async () => {
  const { nodes, calls } = await setup();
  await nodes.get('airplay-export').listeners.click[0]();
  const injected = calls.filter((call) => call.func).map((call) => call.func.toString()).join('\n');
  for (const name of ['ExportAirPlayPlayback', 'AirPlaySourceTrace']) {
    assert.ok(injected.includes(`commercialBreaker${name}`));
    assert.equal(injected.includes(legacy(name)), false);
  }
});