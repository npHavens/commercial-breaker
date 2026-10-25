const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(require('node:path').join(__dirname, '../../SafariExtension/directv-airplay-recovery.js'), 'utf8');
function fixture({ wireless = true, timeout = 10 } = {}) {
  let id = 0, now = 0, errors = 0, buffered = false, poll;
  const jobs = new Map(), listeners = new Map(), subscriptions = new Map();
  const setTimeout = (fn, delay) => { jobs.set(++id, { fn, at: now + delay }); return id; };
  const clearTimeout = id => jobs.delete(id);
  const video = { currentTime: 50, buffered: { length: 1, start: () => 1, end: () => 20 },
    webkitCurrentPlaybackTargetIsWireless: wireless,
    addEventListener: (n, f) => listeners.set(n, f), removeEventListener: n => listeners.delete(n) };
  const timerSubscriptions = new Map();
  const timer = { videoElement_: video, timeoutSeconds_: timeout,
    videoBufferedOrEnded_: () => buffered,
    subscribe: (n, f) => timerSubscriptions.set(n, f), unsubscribe: n => timerSubscriptions.delete(n),
    onTimeout_: () => {
      // createBufferTimeoutError: matches the verified native callback shape.
      if (!timer.videoBufferedOrEnded_()) { errors++; timerSubscriptions.get('error')?.({ code: 1502 }); }
    },
    scheduleTimer_(delay) { clearTimeout(this.timeout_); this.timeout_ = setTimeout(() => {
      this.timeout_ = setTimeout(this.onTimeout_, 10000);
    }, delay * 1000); }
  };
  const controller = { videoElement_: video, bufferTimer_: timer,
    subscribe: (n, f) => subscriptions.set(n, f), unsubscribe: n => subscriptions.delete(n) };
  const state = { bridge: { vstbPlayer: { playbackController: controller } } };
  video.__reactFiberTest = { memoizedState: { memoizedState: state } };
  const trace = { export: () => JSON.stringify({ events: [], marker: 'preserved' }) };
  const context = { Date: class extends Date { static now() { return now; } }, location: { origin: 'https://stream.directv.com' }, document: {
    querySelectorAll: () => [video], addEventListener() {}, removeEventListener() {} },
    addEventListener() {}, removeEventListener() {}, setTimeout, clearTimeout,
    setInterval: fn => { poll = fn; return ++id; }, clearInterval() {}, commercialBreakerAirPlaySourceTrace: trace };
  const original = timer.onTimeout_;
  vm.runInNewContext(source, context);
  function advance(ms) { const end = now + ms; for (;;) {
    const next = [...jobs].filter(([, j]) => j.at <= end).sort((a, b) => a[1].at - b[1].at)[0];
    if (!next) break; jobs.delete(next[0]); now = next[1].at; next[1].fn();
  } now = end; }
  return { video, timer, context, trace, original, advance, controller,
    poll: () => poll(), removeController: () => { state.bridge.vstbPlayer.playbackController = undefined; },
    emitError: e => subscriptions.get('error')?.(e),
    get errors() { return errors; }, get subscriptions() { return subscriptions.size + timerSubscriptions.size; },
    buffer: value => { buffered = value; },
    disconnect: () => { video.webkitCurrentPlaybackTargetIsWireless = false; listeners.get('webkitcurrentplaybacktargetiswirelesschanged')?.(); } };
}
test('observation preserves native timeout callback and 10s recovery', () => {
  const f = fixture(); assert.equal(f.timer.onTimeout_, f.original);
  f.timer.scheduleTimer_(0); f.advance(10000); assert.equal(f.errors, 1);
  const report = JSON.parse(f.trace.export());
  assert.equal(report.recoveryExperiment.mode, 'guarded-handoff-seek');
  assert.equal(report.recoveryExperiment.graceSeconds, 0);
  assert.equal(report.recoveryExperiment.events.at(-1).code, 1502);
});
test('disconnect and stop never reschedule or cancel the native timer', () => {
  const f = fixture(); f.timer.scheduleTimer_(0); f.advance(5000);
  const pending = f.timer.timeout_; f.disconnect(); f.context.commercialBreakerDirectvRecovery.stop();
  assert.equal(f.timer.timeout_, pending); assert.equal(f.subscriptions, 0);
  f.advance(5000); assert.equal(f.errors, 1);
  assert.equal(JSON.parse(f.trace.export()).recoveryExperiment, undefined);
});
test('controller replacement detaches observers; reinjection does not stack them', () => {
  const f = fixture(); vm.runInNewContext(source, f.context); assert.equal(f.subscriptions, 2);
  f.controller.destroyed_ = true; f.removeController(); f.poll();
  assert.equal(f.subscriptions, 0); assert.equal(f.timer.onTimeout_, f.original);
});
test('samples and error diagnostics are bounded and exclude arbitrary payloads', () => {
  const f = fixture(); f.emitError({code:1562,rootError:{code:1502,url:'secret'},message:'secret'});
  let report = f.context.commercialBreakerDirectvRecovery.export(); assert.equal(report.includes('secret'), false);
  assert.equal(JSON.parse(report).events.at(-1).rootCode, 1502);
  for(let i=0;i<650;i++)f.poll();
  report = JSON.parse(f.context.commercialBreakerDirectvRecovery.export());
  assert.equal(report.events.length,600); assert.ok(report.dropped>0);
  assert.equal(report.events.at(-1).event,'handoff sample');
  f.advance(3600000); assert.equal(f.context.commercialBreakerDirectvRecovery.running,true);
  f.context.commercialBreakerDirectvRecovery.stop(); assert.equal(f.context.commercialBreakerDirectvRecovery.running,false);
});

function mismatch(f) {
  Object.assign(f.video, { paused: false, seeking: false, readyState: 4, duration: Infinity,
    currentTime: 150, buffered: { length:1,start:()=>80,end:()=>110 },
    seekable:{length:1,start:()=>0,end:()=>105} });
}
test('stable handoff mismatch seeks once inside both ranges without changing native recovery', () => {
  const f=fixture(); mismatch(f); f.poll(); assert.equal(f.video.currentTime,150);
  f.advance(1000);f.poll();assert.equal(f.video.currentTime,103);
  f.video.currentTime=150;f.advance(1000);f.poll();assert.equal(f.video.currentTime,150);
  assert.equal(f.timer.onTimeout_,f.original);
});
test('paused, seeking, local, VOD and nonoverlapping ranges are never corrected', () => {
  for(const change of [{paused:true},{seeking:true},{webkitCurrentPlaybackTargetIsWireless:false},
    {duration:300},{seekable:{length:1,start:()=>0,end:()=>70}}]) {
    const f=fixture();mismatch(f);Object.assign(f.video,change);f.poll();f.advance(1000);f.poll();
    assert.equal(f.video.currentTime,150);
  }
});
test('advancing time and expired handoff windows do not seek', () => {
  const f=fixture();mismatch(f);f.poll();f.video.currentTime=151;f.advance(1000);f.poll();
  assert.equal(f.video.currentTime,151);
  f.advance(61000);f.poll();assert.equal(f.video.currentTime,151);
});

const legacy = (name) => `skybox${name}`;

test('recovery controller is exposed as commercialBreakerDirectvRecovery only', () => {
  const f = fixture();
  assert.equal(typeof f.context.commercialBreakerDirectvRecovery.export, 'function');
  assert.equal(f.context[legacy('DirectvRecovery')], undefined);
});