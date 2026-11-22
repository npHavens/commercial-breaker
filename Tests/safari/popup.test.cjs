const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const read = (file) => readFileSync(resolve(__dirname, '../../SafariExtension', file), 'utf8');
const source = read('popup.js');
const html = read('popup.html');
const panelVersion = read('dist/airplay-session.js').match(/host\.commercialBreakerVersion = '([^']+)'/)[1];

async function setup(failure, storage = new Map(), url = 'https://www.paramountplus.com/live-tv/', pageOverrides = {}) {
  const nodes = new Map([...html.matchAll(/id="([^"]+)"/g)].map((match) => [match[1], {
    hidden: true, disabled: false, textContent: '', listeners: {}, parentElement: {},
    addEventListener(event, callback) { (this.listeners[event] ??= []).push(callback); }
  }]));

  const calls = [];
  const playerArgs = [];

  // Injected functions run against a fake page, so the popup's checks meet the real panel version.
  const page = {
    commercialBreakerPlayer: (...args) => {
      playerArgs.push(args);

      return { ok: true, muted: true, volume: 0.8, paused: true };
    },
    commercialBreakerAirPlayPanel: { isConnected: true, commercialBreakerVersion: panelVersion },
    ...pageOverrides
  };

  const context = vm.createContext({
    localStorage: { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
    URL, setTimeout, clearTimeout, document: { querySelector: (selector) => nodes.get(selector.slice(1)) },
    browser: {
      tabs: { query: async () => [{ id: 7, url }] },
      runtime: { sendMessage: async () => ({ message: 'Capture idle.' }) },
      scripting: { executeScript: async (options) => {
        calls.push(options);
        if (failure && options.files?.includes('dist/airplay-session.js')) throw new Error(failure);
        if (!options.func) return [{ result: undefined }];

        return [{ result: vm.runInNewContext(`(${options.func.toString()})(...args)`, { ...page, args: options.args ?? [] }) }];
      } }
    }
  });

  vm.runInContext(read('dist/relay-target.js'), context);
  vm.runInContext(source, context);
  await new Promise(setImmediate);

  return { nodes, calls, storage, context, playerArgs };
}

test('Paramount+ popup exposes AirPlay and wires the click to page injection', async () => {
  const { nodes, calls } = await setup();
  assert.equal(nodes.get('airplay-controls').hidden, false);
  assert.equal(nodes.get('build-status').textContent, 'v0.2.23 · Controls ready');
  await nodes.get('airplay').listeners.click[0]();
  assert.ok(calls.some((call) => call.files?.includes('dist/airplay-session.js') && call.target.tabId === 7));
  const recovery = calls.find((call) => call.files?.includes('dist/directv-airplay-recovery.js'));
  assert.deepEqual(Array.from(recovery.files), ['dist/directv-airplay-recovery.js']);
  assert.equal(recovery.world, 'MAIN');
  assert.match(nodes.get('airplay-status').textContent, /Close this popup/);
  assert.equal(nodes.get('airplay').disabled, false);
});

test('a panel from another version is reported instead of injecting the recovery', async () => {
  const oldPanel = { commercialBreakerAirPlayPanel: { isConnected: true, commercialBreakerVersion: '0.1.11' } };
  const { nodes, calls } = await setup(undefined, new Map(), undefined, oldPanel);
  await nodes.get('airplay').listeners.click[0]();
  assert.match(nodes.get('airplay-status').textContent, /close the old AirPlay panel/);
  assert.ok(!calls.some((call) => call.files?.includes('dist/directv-airplay-recovery.js')));
});

test('AirPlay injection errors are shown and the button can be retried', async () => {
  const { nodes } = await setup('Page access denied');
  await nodes.get('airplay').listeners.click[0]();
  assert.equal(nodes.get('airplay-status').textContent, 'Page access denied');
  assert.equal(nodes.get('airplay').disabled, false);
});

test('DIRECTV page status reads the player without passing it anything that could change it', async () => {
  const { nodes, playerArgs } = await setup(undefined, new Map(), 'https://stream.directv.com/watch');
  assert.equal(nodes.get('page-status').hidden, false);
  assert.equal(nodes.get('airplay-controls').hidden, false);
  assert.equal(nodes.get('status').textContent, 'Player is muted. Video is paused.');
  await nodes.get('refresh').listeners.click[0]();
  assert.deepEqual(playerArgs, [[], []]);
  assert.equal(nodes.get('refresh').disabled, false);
});

test('AirPlay failure history survives closing and reopening the popup', async () => {
  const first = await setup('Page access denied');
  await first.nodes.get('airplay').listeners.click[0]();
  const reopened = await setup(undefined, first.storage);
  assert.match(reopened.nodes.get('airplay-history').textContent, /Button clicked/);
  assert.match(reopened.nodes.get('airplay-history').textContent, /Error: Page access denied/);
});

test('the relay tab shows only Paramount setup and injects nothing into the relay page', async () => {
  const url = `http://192.168.1.10:8765/session/${'a'.repeat(43)}/`;
  const { nodes, calls } = await setup(undefined, new Map(), url);
  assert.equal(nodes.get('page-status').hidden, true);
  assert.equal(nodes.get('airplay-controls').hidden, true);
  assert.equal(nodes.get('paramount-setup-status').textContent, 'Capture idle.');
  assert.deepEqual(calls, []);
});

test('an unsupported page hides AirPlay and asks for a DIRECTV or Paramount+ video', async () => {
  const { nodes, calls } = await setup(undefined, new Map(), 'https://example.com/');
  assert.equal(nodes.get('airplay-controls').hidden, true);
  assert.match(nodes.get('status').textContent, /Open a video on paramountplus\.com or directv\.com/);
  assert.deepEqual(calls, []);
});

const legacy = (name) => `skybox${name}`;

test('popup injects the commercialBreaker names and never the legacy skybox names', async () => {
  const { nodes, calls, context } = await setup();
  await nodes.get('airplay').listeners.click[0]();
  const injected = calls.filter((call) => call.func).map((call) => call.func.toString()).join('\n');

  for (const name of ['Player', 'AirPlayPanel', 'Version']) {
    assert.ok(injected.includes(`commercialBreaker${name}`), `popup never injects commercialBreaker${name}`);
    assert.equal(injected.includes(legacy(name)), false, `popup still injects ${legacy(name)}`);
  }

  assert.equal(context[legacy('IsRelayUrl')], undefined);
});
