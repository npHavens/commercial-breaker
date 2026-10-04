const { test } = require('node:test');
const assert = require('node:assert/strict');
require('../../SafariExtension/export.js');

test('export round-trips JSON through a persistent data URL with a save dialog', async () => {
  const json = JSON.stringify({ entries: [{ label: 'Ad — 50% & return' }] });
  let options;
  await globalThis.skyboxSaveRecording({ downloads: { download: async (value) => { options = value; return 1; } } }, json);
  assert.equal(decodeURIComponent(options.url.split(',')[1]), json);
  assert.equal(options.saveAs, true);
  assert.match(options.filename, /^skybox-signals-.*\.json$/);
});

test('export reports unavailable save mechanisms and empty recordings', async () => {
  await assert.rejects(globalThis.skyboxSaveRecording({}, '{"entries":[{}]}'), /cannot open/);
  await assert.rejects(globalThis.skyboxSaveRecording({}, '{"entries":[]}'), /no recording/);
});

test('absent or rejected downloads API opens a persistent tab with an exact recovery copy', async () => {
  const storage = new Map();
  globalThis.localStorage = { setItem: (key, value) => storage.set(key, value) };
  try {
    for (const downloads of [undefined, { download: async () => { throw new Error('Denied'); } }]) {
      let tab;
      const browser = {
        downloads,
        tabs: { create: async (options) => { tab = options; } },
        runtime: { getURL: (path) => `safari-web-extension://test/${path}` }
      };
      const json = JSON.stringify({ entries: [{ label: 'Ad — 50% & return' }] });
      assert.equal((await globalThis.skyboxSaveRecording(browser, json)).method, 'page');
      assert.equal(tab.url, 'safari-web-extension://test/save-recording.html');
      assert.equal(JSON.parse(storage.get('skybox.recording-export')).json, json);
    }
  } finally { delete globalThis.localStorage; }
});

test('save page creates a downloadable JSON blob and clearing does not erase a newer export', async () => {
  const vm = require('node:vm');
  const { readFileSync } = require('node:fs');
  const { resolve } = require('node:path');
  const json = JSON.stringify({ schemaVersion: 1, kind: 'airplay-playback', events: [{ event: 'playing' }], sourceTrace: { events: [{ operation: 'load' }] } });
  const storage = new Map([['skybox.recording-export', JSON.stringify({ filename: 'recording.json', json })]]);
  const nodes = new Map(['message', 'download', 'open', 'clear'].map((id) => [id, {
    hidden: true, addEventListener(event, handler) { this[event] = handler; }
  }]));
  let blob;
  vm.runInNewContext(readFileSync(resolve(__dirname, '../../SafariExtension/save-recording.js'), 'utf8'), {
    Blob,
    skyboxValidateExport: globalThis.skyboxValidateExport,
    URL: { createObjectURL(value) { blob = value; return 'blob:test'; } },
    localStorage: { getItem: (key) => storage.get(key), removeItem: (key) => storage.delete(key) },
    document: { querySelector: (selector) => nodes.get(selector.slice(1)) }
  });
  assert.equal(await blob.text(), json);
  assert.equal(nodes.get('download').download, 'recording.json');
  assert.equal(nodes.get('download').hidden, false);
  assert.equal(nodes.get('open').href, 'blob:test');
  storage.set('skybox.recording-export', 'newer export');
  nodes.get('clear').click();
  assert.equal(storage.get('skybox.recording-export'), 'newer export');
});


test('AirPlay events and audio snapshots save without an entries array', async () => {
  for (const report of [
    { schemaVersion: 1, kind: 'airplay-playback', events: [{ event: 'playing' }], sourceTrace: { events: [{ operation: 'load' }] } },
    { version: 1, probe: 'audio-access', at: '2026-10-04T19:00:00Z', supported: false }
  ]) {
    const json = JSON.stringify(report);
    let options;
    await globalThis.skyboxSaveRecording({ downloads: { download: async value => { options = value; } } }, json);
    assert.equal(decodeURIComponent(options.url.split(',')[1]), json);
  }
});

test('invalid JSON and empty exports never start a download', async () => {
  const browser = { downloads: { download: async () => assert.fail('must not download') } };
  for (const json of ['null', '{}', '[]', '{"events":[]}', '{"entries":[]}', '{"events":"playing"}', 'broken']) {
    await assert.rejects(globalThis.skyboxSaveRecording(browser, json));
  }
});
