const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const read = (file) => readFileSync(resolve(__dirname, '../../SafariExtension', file), 'utf8');
const relayUrl = `http://192.168.1.10:8765/session/${'a'.repeat(43)}/`;

test('relay URL recognition excludes public hosts, arbitrary LAN pages and credentials', () => {
  const context = vm.createContext({ URL });
  vm.runInContext(read('relay-target.js'), context);
  assert.equal(context.skyboxIsRelayUrl(relayUrl), true);
  for (const url of [relayUrl.replace('192.168.1.10', 'example.com'),
    relayUrl.replace('192.168.1.10', '127.0.0.1'), relayUrl.replace('/session/', '/other/'),
    relayUrl.replace('http://', 'http://user:password@'), relayUrl + '?url=elsewhere']) {
    assert.equal(context.skyboxIsRelayUrl(url), false);
  }
});

test('extension controls the existing page controller without constructing a second one', () => {
  let state = { enabled: false, state: 'unknown', message: 'off', muted: false };
  const video = { muted: false, paused: false };
  const nodes = {
    'meta[name="skybox-relay"]': { content: '1' },
    '#skybox-commercial-state': { get textContent() { return JSON.stringify(state); } },
    '#video': video,
    '#skybox-auto-toggle': { click() { state.enabled = !state.enabled; } },
    '#mute': { click() { state.enabled = false; video.muted = !video.muted; } }
  };
  const context = vm.createContext({ URL, location: { href: relayUrl },
    document: { querySelector: (selector) => nodes[selector] } });
  vm.runInContext(read('relay-target.js'), context);
  vm.runInContext(read('relay-controls.js'), context);
  assert.equal(context.skyboxRelayControl('toggle-auto').enabled, true);
  vm.runInContext(read('relay-controls.js'), context);
  assert.equal(context.skyboxRelayControl('status').enabled, true);
  const result = context.skyboxRelayControl('toggle-mute');
  assert.equal(result.enabled, false);
  assert.equal(result.muted, true);
  delete nodes['meta[name="skybox-relay"]'];
  assert.equal(context.skyboxRelayControl('toggle-auto').ok, false);
});
