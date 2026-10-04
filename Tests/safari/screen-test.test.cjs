const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const source = readFileSync(resolve(__dirname, '../../SafariExtension/screen-test.js'), 'utf8');
function setup(mode) {
  const nodes = new Map(['choose', 'capture', 'stop', 'message', 'preview', 'still', 'download'].map((id) => [id, {
    disabled: false, hidden: true, readyState: 4, videoWidth: 1920, videoHeight: 1080,
    addEventListener(event, fn) { this[event] = fn; }, play: async () => {}
  }]));
  let stopped = 0, request, timeout, finish;
  const track = { stop() { stopped++; }, addEventListener() {} };
  const stream = { getTracks: () => [track] };
  const window = { addEventListener(event, fn) { this[event] = fn; } };
  vm.runInNewContext(source, {
    navigator: { mediaDevices: { getDisplayMedia(options) {
      request = options;
      if (mode === 'denied') return Promise.reject(Object.assign(new Error('Denied'), { name: 'NotAllowedError' }));
      if (mode === 'pending') return new Promise((resolve) => { finish = () => resolve(stream); });
      return Promise.resolve(stream);
    } } }, window,
    setTimeout(fn) { timeout = fn; return 1; }, clearTimeout() { timeout = null; },
    document: { querySelector: (selector) => nodes.get(selector.slice(1)), createElement: () => ({
      getContext: () => ({ drawImage() {}, getImageData() {
        if (mode === 'tainted') throw new Error('Tainted');
        return { data: [0, 0, 0, 255] };
      } }), toDataURL: () => 'data:image/png;base64,dGVzdA=='
    }) }
  });
  return { nodes, window, start: () => nodes.get('choose').click(), capture: () => nodes.get('capture').click(),
    stopped: () => stopped, request: () => request, expire: () => timeout(), resolve: () => finish() };
}

test('picker runs directly on click with audio disabled; snapshot stops every track', async () => {
  const h = setup();
  const pending = h.start();
  assert.equal(h.request().audio, false);
  await pending;
  h.capture();
  assert.equal(h.stopped(), 1);
  assert.equal(h.nodes.get('still').hidden, false);
  assert.equal(h.nodes.get('preview').srcObject, null);
  assert.equal(h.nodes.get('choose').disabled, false);
});

test('readback error and timeout both stop capture', async () => {
  const failed = setup('tainted'); await failed.start(); failed.capture();
  assert.equal(failed.stopped(), 1);
  assert.match(failed.nodes.get('message').textContent, /Frame read failed/);
  const expired = setup(); await expired.start(); expired.expire();
  assert.equal(expired.stopped(), 1);
});

test('denied picker remains retryable without creating a stream', async () => {
  const h = setup('denied'); await h.start();
  assert.equal(h.stopped(), 0);
  assert.equal(h.nodes.get('choose').disabled, false);
  assert.match(h.nodes.get('message').textContent, /NotAllowedError/);
});

test('leaving the page during the picker stops a stream arriving late', async () => {
  const h = setup('pending'); const pending = h.start();
  h.window.pagehide(); h.resolve(); await pending;
  assert.equal(h.stopped(), 1);
  assert.equal(h.nodes.get('preview').srcObject, null);
});
