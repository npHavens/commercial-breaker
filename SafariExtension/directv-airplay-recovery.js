// DIRECTV AirPlay timeline correction. Runs in the page MAIN world.
(() => {
  if (location.origin !== 'https://stream.directv.com') return;
  if (globalThis.skyboxDirectvRecovery?.running) return;
  const events = [];
  let binding, running = true, dropped = 0, lastCorrection = -Infinity;
  const own = (object, key) => object && Object.getOwnPropertyDescriptor(object, key)?.value;
  function record(event, controller, error) {
    const video = controller?.videoElement_;
    const ranges = [], seekable = [];
    let startDate = null;
    try {
      for (let i = 0; video && i < Math.min(video.buffered.length, 8); i++) {
        ranges.push([video.buffered.start(i), video.buffered.end(i)]);
      }
      for (let i = 0; video?.seekable && i < Math.min(video.seekable.length, 8); i++) {
        seekable.push([video.seekable.start(i), video.seekable.end(i)]);
      }
      const date = video?.getStartDate?.();
      if (date && Number.isFinite(date.getTime())) startDate = date.toISOString();
    } catch { /* A disappearing video must not break player callbacks. */ }
    events.push({ at: new Date().toISOString(), event,
      wireless: video?.webkitCurrentPlaybackTargetIsWireless === true,
      time: Number.isFinite(video?.currentTime) ? video.currentTime : null,
      buffered: ranges, seekable, startDate,
      paused: video?.paused, seeking: video?.seeking, ready: video?.readyState,
      duration: Number.isFinite(video?.duration) ? video.duration : null,
      code: Number.isFinite(error?.code) ? error.code : null,
      rootCode: Number.isFinite(error?.rootError?.code) ? error.rootError.code : null });
    if (events.length > 600) { events.shift(); dropped++; }
  }
  function note(...args) { try { record(...args); } catch { /* Diagnostics are best effort. */ } }
  function locate() {
    // Observed DIRECTV React hook -> bridge -> QuickPlayPlayer. No graph-wide search.
    for (const video of document.querySelectorAll('video')) {
      let fiber = own(video, Object.keys(video).find(key => key.startsWith('__reactFiber')));
      for (let depth = 0; fiber && depth < 10; depth++, fiber = own(fiber, 'return')) {
        let hook = own(fiber, 'memoizedState');
        for (let index = 0; hook && index < 100; index++, hook = own(hook, 'next')) {
          const bridge = own(own(hook, 'memoizedState'), 'bridge');
          const controller = own(own(bridge, 'vstbPlayer'), 'playbackController');
          if (controller?.videoElement_ === video && !controller.destroyed_) return controller;
        }
      }
    }
  }
  function supported(controller) {
    return typeof controller?.subscribe === 'function' && typeof controller.unsubscribe === 'function'
      && typeof controller.bufferTimer_?.subscribe === 'function'
      && typeof controller.bufferTimer_.unsubscribe === 'function';
  }
  function attach(controller) {
    const timer = controller.bufferTimer_, video = controller.videoElement_;
    let sampleUntil = Date.now() + 45000;
    let connectedAt = video.webkitCurrentPlaybackTargetIsWireless ? Date.now() : null;
    let attempted = false, previousMismatch, result;
    function correctHandoff() {
      const now = Date.now();
      if (result && now - result.at >= 8000) {
        note(!video.seeking && video.currentTime > result.target + 2
          ? 'guarded seek: reported playback advancing' : 'guarded seek: progress not confirmed', controller);
        result = undefined;
      }
      if (attempted || connectedAt === null || now - connectedAt > 60000
          || now - lastCorrection < 60000 || !video.webkitCurrentPlaybackTargetIsWireless
          || video.paused || video.seeking || video.readyState < 3 || video.duration !== Infinity) {
        previousMismatch = undefined; return;
      }
      const buffered = [], seekable = [];
      for (const [ranges, output] of [[video.buffered, buffered], [video.seekable, seekable]]) {
        for (let i = 0; ranges && i < ranges.length; i++) {
          const start = ranges.start(i), end = ranges.end(i);
          if (Number.isFinite(start) && Number.isFinite(end) && end > start) output.push([start, end]);
        }
      }
      const time = video.currentTime;
      if (!Number.isFinite(time) || !buffered.length || !seekable.length
          || time <= Math.max(...buffered.map(r => r[1])) + 5
          || time <= Math.max(...seekable.map(r => r[1])) + 5) {
        previousMismatch = undefined; return;
      }
      let target;
      for (const b of buffered) for (const r of seekable) {
        const start = Math.max(b[0], r[0]), end = Math.min(b[1], r[1]);
        if (end - start >= 4 && (target === undefined || end - 2 > target)) target = end - 2;
      }
      if (target === undefined) { previousMismatch = undefined; return; }
      const prior = previousMismatch;
      previousMismatch = { at: now, time };
      if (!prior || now - prior.at < 900 || Math.abs(time - prior.time) > 0.25) return;
      attempted = true; lastCorrection = now;
      note(`guarded seek requested: ${time.toFixed(3)} -> ${target.toFixed(3)}`, controller);
      try { video.currentTime = target; result = { at: now, target }; }
      catch { note('guarded seek failed; native recovery remains enabled', controller); }
    }
    const onError = error => note('controller error or retune', controller, error);
    const onBufferError = error => note('native buffer timer error', controller, error);
    const handlers = new Map();
    for (const name of ['webkitcurrentplaybacktargetiswirelesschanged', 'loadedmetadata', 'emptied', 'seeking', 'seeked']) {
      const handler = () => {
        sampleUntil = Date.now() + 45000;
        if (name === 'webkitcurrentplaybacktargetiswirelesschanged') {
          connectedAt = video.webkitCurrentPlaybackTargetIsWireless ? Date.now() : null;
          attempted = false; previousMismatch = undefined; result = undefined;
        }
        note(name, controller);
      };
      handlers.set(name, handler);
      video.addEventListener(name, handler);
    }
    controller.subscribe('error', onError);
    timer.subscribe('error', onBufferError);
    note('attached: one guarded handoff seek; native recovery unchanged', controller);
    return { controller, sample() {
      if (Date.now() <= sampleUntil) note('handoff sample', controller);
      correctHandoff();
    }, detach() {
      controller.unsubscribe('error', onError);
      timer.unsubscribe('error', onBufferError);
      for (const [name, handler] of handlers) video.removeEventListener(name, handler);
      note('observer detached', controller);
    } };
  }
  let lastStatus;
  function check() {
    try {
      const controller = locate();
      if (binding && controller === binding.controller) { binding.sample(); return; }
      binding?.detach(); binding = undefined;
      if (controller && supported(controller)) {
        binding = attach(controller); lastStatus = undefined;
      } else {
        const status = controller ? 'unsupported controller; no timer changes' : 'waiting for active controller';
        if (status !== lastStatus) note(status, controller);
        lastStatus = status;
      }
    } catch { note('controller inspection failed; experiment stopping'); stop(); }
  }
  const trace = globalThis.skyboxAirPlaySourceTrace;
  const originalExport = trace?.export;
  const snapshot = () => ({ running, attached: !!binding, dropped,
    mode: 'guarded-handoff-seek', graceSeconds: 0, events: events.slice() });
  const traceExport = function (...args) {
    const report = JSON.parse(Reflect.apply(originalExport, this, args));
    report.recoveryExperiment = snapshot();
    return JSON.stringify(report);
  };
  if (typeof originalExport === 'function') trace.export = traceExport;
  const poll = setInterval(check, 1000);
  function stop() {
    if (!running) return;
    running = false;
    clearInterval(poll);
    binding?.detach(); binding = undefined;
    if (trace?.export === traceExport) trace.export = originalExport;
    document.removeEventListener('skybox-airplay-trace-stop', stop);
    globalThis.removeEventListener('pagehide', stop);
    note('experiment stopped');
  }
  globalThis.skyboxDirectvRecovery = { get running() { return running; }, stop,
    export: () => JSON.stringify(snapshot()) };
  document.addEventListener('skybox-airplay-trace-stop', stop);
  globalThis.addEventListener('pagehide', stop);
  check();
})();
