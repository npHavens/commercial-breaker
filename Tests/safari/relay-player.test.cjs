const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const html = readFileSync(resolve(__dirname, '../../Tools/hls_player.html'), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function setup(storage = new Map()) {
  const nodes = new Map([...html.matchAll(/id="([^"]+)"/g)].map((match) => [match[1], {
    listeners: {}, textContent: '', value: '',
    addEventListener(name, fn) { this.listeners[name] = fn; }
  }]));
  const video = nodes.get('video');
  let loads = 0, plays = 0, pickers = 0;
  let progress;
  Object.assign(video, {
    src: '', error: null, readyState: 0, paused: true, muted: false, currentTime: 25, volume: 0.8,
    getAttribute(name) { return name === 'src' ? this.src : null; },
    removeAttribute(name) { if (name === 'src') this.src = ''; },
    load() { loads++; this.error = null; },
    async play() { plays++; this.paused = false; },
    pause() { this.paused = true; },
    webkitShowPlaybackTargetPicker() { pickers++; }
  });
  const pageEvents = {};
  const document = { visibilityState: 'visible', querySelector: (selector) => nodes.get(selector.slice(1)),
    addEventListener: (name, callback) => { pageEvents[name] = callback; } };
  vm.runInNewContext(source, {
    document, window: { addEventListener: (name, callback) => { pageEvents[name] = callback; } },
    sessionStorage: { getItem: (key) => storage.get(key) ?? null, setItem: (key, value) => storage.set(key, value) },
    location: { href: 'http://192.168.1.2:8765/session/test/' }, URL,
    fetch: async () => ({ ok: true, json: async () => ['Playlist check passed.'] }),
    setTimeout: () => {}, setInterval: (callback) => { progress = callback; }
  });
  return { nodes, video, document, storage, pageEvents, counts: () => ({ loads, plays, pickers }),
    progress: () => progress(), click: (id) => nodes.get(id).listeners.click() };
}

test('relay player rejects AirPlay after decode failure or metadata-only loading', () => {
  const h = setup();
  h.video.readyState = 1;
  h.click('airplay');
  h.video.readyState = 4;
  h.video.error = { code: 3 };
  h.click('airplay');
  assert.equal(h.counts().pickers, 0);
  assert.match(h.nodes.get('status').textContent, /Establish local video and audio/);
  h.video.error = null;
  h.click('airplay');
  assert.equal(h.counts().pickers, 1);
});

test('Play uses the relay URL; a retry reloads only after a playback error', async () => {
  const h = setup();
  await h.click('play');
  assert.equal(h.video.src, 'http://192.168.1.2:8765/session/test/live.m3u8');
  await h.click('play');
  assert.deepEqual(h.counts(), { loads: 1, plays: 2, pickers: 0 });
  h.video.error = { code: 3 };
  await h.click('play');
  assert.deepEqual(h.counts(), { loads: 2, plays: 3, pickers: 0 });
});

test('mute preserves playback and Stop releases the stream', async () => {
  const h = setup();
  await h.click('play');
  h.click('mute');
  assert.equal(h.video.muted, true);
  assert.equal(h.video.paused, false);
  assert.equal(h.video.currentTime, 25);
  assert.equal(h.video.volume, 0.8);
  h.click('stop');
  assert.equal(h.video.src, '');
  assert.equal(h.video.paused, true);
  assert.equal(h.counts().loads, 2);
});

test('progress reports actual timeline/frame counts and missing audio without changing playback', async () => {
  const h = setup();
  Object.assign(h.video, {
    videoWidth: 1920, videoHeight: 1080, webkitDecodedFrameCount: 20, audioTracks: [],
    buffered: { length: 1, start: () => 20, end: () => 50 },
    seekable: { length: 1, start: () => 0, end: () => 55 },
    getVideoPlaybackQuality: () => ({ totalVideoFrames: 21, droppedVideoFrames: 1 })
  });
  await h.click('play');
  h.progress();
  assert.match(h.nodes.get('history').value, /time=25.00, buffered=20.00-50.00, seekable=0.00-55.00/);
  assert.match(h.nodes.get('history').value, /decoded=20, totalFrames=21, dropped=1, audioTracks=0/);
  h.video.currentTime = 30;
  h.video.webkitDecodedFrameCount = 170;
  h.progress();
  assert.match(h.nodes.get('history').value, /time=30.00/);
  assert.match(h.nodes.get('history').value, /decoded=170/);
  assert.equal(h.video.muted, false);
  assert.equal(h.video.volume, 0.8);
  assert.deepEqual(h.counts(), { loads: 1, plays: 1, pickers: 0 });
  h.video.paused = true;
  const previous = h.nodes.get('history').value;
  h.progress();
  assert.equal(h.nodes.get('history').value, previous);
});

test('snapshot distinguishes unavailable audio metrics from zero or disabled tracks', () => {
  const h = setup();
  h.click('check');
  assert.match(h.nodes.get('history').value, /audioTracks=unknown/);
  h.video.audioTracks = [{ enabled: false }];
  h.click('check');
  assert.match(h.nodes.get('history').value, /audioTracks=1 \(0 enabled\)/);
  h.video.audioTracks[0].enabled = true;
  h.click('check');
  assert.match(h.nodes.get('history').value, /audioTracks=1 \(1 enabled\)/);
});

test('returning to a tab logs lifecycle and target state without changing playback', async () => {
  const h = setup();
  await h.click('play');
  h.video.webkitCurrentPlaybackTargetIsWireless = true;
  const before = h.counts();
  h.document.visibilityState = 'hidden';
  h.pageEvents.visibilitychange({});
  h.pageEvents.blur({});
  h.document.visibilityState = 'visible';
  h.pageEvents.visibilitychange({});
  h.pageEvents.focus({});
  assert.match(h.nodes.get('history').value, /Page focus: visibility=visible, restored=false; wireless=true/);
  assert.deepEqual(h.counts(), before);
  assert.equal(h.video.paused, false);
  assert.equal(h.video.src, 'http://192.168.1.2:8765/session/test/live.m3u8');
});

test('history survives a reload with an explicit new page marker', () => {
  const first = setup();
  first.video.webkitCurrentPlaybackTargetIsWireless = true;
  first.pageEvents.pagehide({ persisted: false });
  const second = setup(first.storage);
  const history = second.nodes.get('history').value;
  assert.match(history, /Page pagehide:.*wireless=true/);
  assert.equal(history.match(/Page initialized/g).length, 2);
  assert.deepEqual(second.counts(), { loads: 0, plays: 0, pickers: 0 });
});
