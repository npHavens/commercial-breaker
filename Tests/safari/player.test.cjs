const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const vm = require('node:vm');

function video(overrides = {}) {
  return {
    muted: false, volume: 0.6, paused: false, ended: false, currentTime: 123,
    getBoundingClientRect: () => ({ width: 640, height: 360, top: 0, left: 0, right: 640, bottom: 360 }),
    ...overrides
  };
}
function player(videos, hostname = 'www.paramountplus.com') {
  const context = vm.createContext({
    document: { querySelectorAll: () => videos },
    location: { protocol: 'https:', hostname },
    innerWidth: 1280, innerHeight: 720,
    getComputedStyle: (element) => ({ visibility: 'visible', display: 'block', opacity: '1', ...element.style })
  });
  for (const file of ['select-video.js', 'player.js']) {
    vm.runInContext(readFileSync(resolve(__dirname, '../../SafariExtension', file), 'utf8'), context);
  }
  return context.commercialBreakerPlayer;
}

test('inspection does not mute; toggling preserves volume, position, and playback', () => {
  const stream = video();
  const control = player([stream]);
  assert.equal(control(false).muted, false);
  assert.equal(control(true).muted, true);
  assert.equal(control(true).muted, false);
  assert.equal(stream.volume, 0.6);
  assert.equal(stream.currentTime, 123);
  assert.equal(stream.paused, false);
});

test('hidden playing preview does not displace the visible paused stream', () => {
  const preview = video({ style: { display: 'none' } });
  const stream = video({ paused: true });
  assert.equal(player([preview, stream])(true).ok, true);
  assert.equal(preview.muted, false);
  assert.equal(stream.muted, true);
  assert.equal(stream.paused, true);
});

test('a unique visible playing stream wins over paused videos', () => {
  const paused = video({ paused: true });
  const stream = video();
  assert.equal(player([paused, stream])(true).ok, true);
  assert.equal(paused.muted, false);
  assert.equal(stream.muted, true);
});

for (const paused of [false, true]) {
  test(`ambiguous ${paused ? 'paused' : 'playing'} videos fail without muting either`, () => {
    const videos = [video({ paused }), video({ paused })];
    const result = player(videos)(true);
    assert.equal(result.ok, false);
    assert.match(result.error, /More than one/);
    assert.ok(videos.every((item) => !item.muted));
  });
}

test('missing and offscreen videos report no player', () => {
  const offscreen = video({ getBoundingClientRect: () => ({ width: 640, height: 360, top: 800, left: 0, right: 640, bottom: 1160 }) });
  for (const videos of [[], [offscreen]]) {
    const result = player(videos)(true);
    assert.equal(result.ok, false);
    assert.match(result.error, /No visible video/);
  }
  assert.equal(offscreen.muted, false);
});

test('navigation to a different site cannot mute its player', () => {
  const stream = video();
  for (const hostname of ['example.com', 'paramountplus.com.example.com', 'directv.com.example.com']) {
    assert.equal(player([stream], hostname)(true).ok, false);
    assert.equal(stream.muted, false);
  }
});

test('DIRECTV manual mute preserves playback and volume', () => {
  const stream = video();
  const control = player([stream], 'stream.directv.com');
  assert.equal(control(true).muted, true);
  assert.equal(control(true).muted, false);
  assert.equal(stream.volume, 0.6);
  assert.equal(stream.currentTime, 123);
  assert.equal(stream.paused, false);
});

const legacy = (name) => `skybox${name}`;

test('player control is exposed as commercialBreakerPlayer only', () => {
  const context = vm.createContext({ document: { querySelectorAll: () => [] }, location: { protocol: 'https:', hostname: 'www.paramountplus.com' } });
  for (const file of ['select-video.js', 'player.js']) {
    vm.runInContext(readFileSync(resolve(__dirname, '../../SafariExtension', file), 'utf8'), context);
  }
  assert.equal(typeof context.commercialBreakerPlayer, 'function');
  assert.equal(context[legacy('Player')], undefined);
});
