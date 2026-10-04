const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const read = (file) => readFileSync(resolve(__dirname, '../../SafariExtension', file), 'utf8');

function run({ black = false, blocked = false, readyState = 4, hostname = 'stream.directv.com', ambiguous = false } = {}) {
  let draws = 0;
  const video = Object.freeze({ paused: false, ended: false, readyState, currentTime: 150,
    videoWidth: 1920, videoHeight: 1080, webkitCurrentPlaybackTargetIsWireless: true,
    getBoundingClientRect: () => ({ width: 100, height: 100, top: 0, left: 0, bottom: 100, right: 100 }) });
  const context = vm.createContext({
    location: { protocol: 'https:', hostname }, innerWidth: 1000, innerHeight: 800,
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    document: {
      querySelectorAll: () => ambiguous ? [video, video] : [video],
      createElement: () => ({
        getContext: () => ({
          drawImage() { draws++; },
          getImageData() {
            if (blocked) { const error = new Error('Tainted'); error.name = 'SecurityError'; throw error; }
            return { data: black ? [0, 0, 0, 255, 0, 0, 0, 255] : [0, 120, 0, 255, 255, 255, 255, 255] };
          }
        }), toDataURL: () => 'data:image/png;base64,dGVzdA=='
      })
    }
  });
  vm.runInContext(read('select-video.js'), context);
  const wire = vm.runInContext(read('frame-probe.js'), context);
  assert.equal(typeof wire, 'string');
  return { result: JSON.parse(wire), draws };
}

test('readable pixels produce a local preview and report AirPlay without changing video', () => {
  const { result, draws } = run();
  assert.equal(result.outcome, 'pixels-readable');
  assert.equal(result.wireless, true);
  assert.equal(draws, 1);
  assert.match(result.preview, /^data:image\/png/);
});

test('black frames and security errors are distinct from successful video access', () => {
  assert.equal(run({ black: true }).result.outcome, 'near-black');
  const { result } = run({ blocked: true });
  assert.equal(result.outcome, 'access-blocked');
  assert.equal(result.preview, undefined);
});

test('missing frame, ambiguous player and unsupported site never draw a frame', () => {
  for (const options of [{ readyState: 1 }, { ambiguous: true }, { hostname: 'directv.com.example.com' }]) {
    assert.equal(run(options).draws, 0);
  }
  assert.equal(run({ readyState: 1 }).result.outcome, 'no-frame');
});
