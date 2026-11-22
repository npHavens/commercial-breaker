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
    vm.runInContext(readFileSync(resolve(__dirname, '../../SafariExtension/dist', file), 'utf8'), context);
  }

  return context.commercialBreakerPlayer;
}

test('status reports the player without changing it, even when a stale popup passes an argument', () => {
  const stream = video();
  const status = player([stream]);
  assert.deepEqual({ ...status() }, { ok: true, muted: false, volume: 0.6, paused: false });
  assert.equal(status(true).muted, false);
  assert.equal(stream.muted, false);
  assert.equal(stream.volume, 0.6);
  assert.equal(stream.currentTime, 123);
  assert.equal(stream.paused, false);
});

test('hidden playing preview does not displace the visible paused stream', () => {
  const preview = video({ style: { display: 'none' } });
  const stream = video({ paused: true, muted: true });
  const result = player([preview, stream])();
  assert.equal(result.ok, true);
  assert.equal(result.muted, true);
  assert.equal(result.paused, true);
});

test('a unique visible playing stream wins over paused videos', () => {
  const paused = video({ paused: true });
  const stream = video({ muted: true });
  const result = player([paused, stream])();
  assert.equal(result.ok, true);
  assert.equal(result.muted, true);
  assert.equal(result.paused, false);
});

for (const paused of [false, true]) {
  test(`ambiguous ${paused ? 'paused' : 'playing'} videos fail without muting either`, () => {
    const videos = [video({ paused }), video({ paused })];
    const result = player(videos)();
    assert.equal(result.ok, false);
    assert.match(result.error, /More than one/);
    assert.ok(videos.every((item) => !item.muted));
  });
}

test('missing and offscreen videos report no player', () => {
  const offscreen = video({ getBoundingClientRect: () => ({ width: 640, height: 360, top: 800, left: 0, right: 640, bottom: 1160 }) });

  for (const videos of [[], [offscreen]]) {
    const result = player(videos)();
    assert.equal(result.ok, false);
    assert.match(result.error, /No visible video/);
  }

  assert.equal(offscreen.muted, false);
});

test('navigation to a different site cannot read or mute its player', () => {
  const stream = video();

  for (const hostname of ['example.com', 'paramountplus.com.example.com', 'directv.com.example.com']) {
    assert.equal(player([stream], hostname)().ok, false);
    assert.equal(stream.muted, false);
  }
});

test('DIRECTV status reports a muted player and leaves it muted', () => {
  const stream = video({ muted: true });
  const status = player([stream], 'stream.directv.com');
  assert.equal(status().muted, true);
  assert.equal(stream.muted, true);
  assert.equal(stream.volume, 0.6);
  assert.equal(stream.currentTime, 123);
  assert.equal(stream.paused, false);
});

const legacy = (name) => `skybox${name}`;

test('player control is exposed as commercialBreakerPlayer only', () => {
  const context = vm.createContext({ document: { querySelectorAll: () => [] }, location: { protocol: 'https:', hostname: 'www.paramountplus.com' } });

  for (const file of ['select-video.js', 'player.js']) {
    vm.runInContext(readFileSync(resolve(__dirname, '../../SafariExtension/dist', file), 'utf8'), context);
  }

  assert.equal(typeof context.commercialBreakerPlayer, 'function');
  assert.equal(context[legacy('Player')], undefined);
});
