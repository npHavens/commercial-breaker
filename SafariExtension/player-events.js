// Runs in the page's MAIN world so an exposed player event bus is accessible.
// Passive subscriptions only: no monkey-patching, network hooks, or event payloads.
(() => {
  const previous = globalThis.commercialBreakerPlayerEvents;
  if (previous?.probeVersion === 2) return;
  // Dispose subscriptions from an older injected recorder before replacing it.
  if (typeof previous === 'function') previous('stop');
  const names = ['adstart', 'adend', 'ads-ad-started', 'adplaying', 'adended',
    'contentresumed', 'contentchanged', 'adsready', 'adtimeout',
    'adbreakstart', 'adbreakend', 'adBreakStarted', 'adBreakEnded'];
  const mediaNames = ['playing', 'pause', 'waiting', 'stalled', 'ended', 'loadstart'];
  let entries = [], cleanups = [], running = false, timer = null, poll = null, dropped = 0;
  let coverage = {};
  const attached = new Set();
  function discoverGlobals() {
    const result = { properties: [], inspected: 0, truncated: false, failed: false };
    try {
      const keys = Object.getOwnPropertyNames(globalThis);
      result.truncated = keys.length > 5000;
      for (const name of keys.slice(0, 5000)) {
        result.inspected++;
        if (!/quickplay|freewheel/i.test(name)) continue;
        if (name.length > 160 || result.properties.length >= 30) {
          result.truncated = true;
          continue;
        }
        const descriptor = Object.getOwnPropertyDescriptor(globalThis, name);
        if (!descriptor) continue;
        const type = !Object.hasOwn(descriptor, 'value') ? 'accessor'
          : descriptor.value === null ? 'null' : typeof descriptor.value;
        result.properties.push({ name, type });
      }
    } catch { result.failed = true; }
    return result;
  }
  function append(kind, fields = {}) {
    if (entries.length >= 600) { entries.shift(); dropped++; }
    entries.push({ at: new Date().toISOString(), kind, ...fields });
  }
  function observe(target, source, eventNames, subscribe, unsubscribe) {
    const subscriptions = [];
    for (const name of eventNames) {
      const listener = () => {
        if (running) append('event', { source, name });
      };
      try {
        subscribe.call(target, name, listener);
        subscriptions.push([name, listener]);
      } catch { append('subscription-failed', { source, name }); }
    }
    cleanups.push(() => {
      for (const [name, listener] of subscriptions) {
        try { unsubscribe.call(target, name, listener); } catch { /* Player may be disposed. */ }
      }
    });
    return subscriptions.length;
  }
  function discover() {
    try {
      for (const video of Array.from(document.querySelectorAll('video')).slice(0, 8)) {
        if (attached.has(video)) continue;
        if (attached.size >= 64) { coverage.sourceLimitReached = true; break; }
        attached.add(video);
        coverage.videoElements++;
        observe(video, 'video', mediaNames, video.addEventListener, video.removeEventListener);
      }
      // Never initialize a player. Only subscribe to already exposed instances.
      const videojs = globalThis.videojs;
      if (typeof videojs?.getPlayers !== 'function') return;
      coverage.videojsRegistry = true;
      for (const player of Object.values(videojs.getPlayers() || {}).slice(0, 8)) {
        if (!player || attached.has(player) || typeof player.on !== 'function' || typeof player.off !== 'function') continue;
        if (attached.size >= 64) { coverage.sourceLimitReached = true; break; }
        attached.add(player);
        const count = observe(player, 'videojs', names, player.on, player.off);
        if (count) coverage.videojsPlayers++;
        append('source-attached', { source: 'videojs', subscribedEvents: count });
      }
    } catch {
      if (!coverage.discoveryFailed) append('discovery-failed');
      coverage.discoveryFailed = true;
    }
  }
  function stop(reason) {
    if (!running) return;
    running = false;
    clearTimeout(timer); clearInterval(poll);
    timer = poll = null;
    cleanups.splice(0).forEach((cleanup) => cleanup());
    attached.clear();
    append('stop', { reason });
  }
  globalThis.commercialBreakerPlayerEvents = (command = 'status') => {
    if (location.protocol !== 'https:' || !(location.hostname === 'directv.com' || location.hostname.endsWith('.directv.com'))) {
      return JSON.stringify({ ok: false, error: 'Open DIRECTV first.' });
    }
    if (command === 'start' && !running) {
      entries = []; dropped = 0; running = true;
      coverage = { world: 'MAIN', domEvents: true, videoElements: 0, videojsRegistry: false,
        videojsPlayers: 0, discoveryFailed: false,
        globals: discoverGlobals(),
        limitation: 'Private player instances and non-DOM event buses are not observed unless exposed through the Video.js registry.' };
      append('start');
      observe(document, 'document', names,
        function (name, listener) { this.addEventListener(name, listener, true); },
        function (name, listener) { this.removeEventListener(name, listener, true); });
      observe(window, 'window', names, window.addEventListener, window.removeEventListener);
      discover();
      poll = setInterval(discover, 2000);
      timer = setTimeout(() => stop('15-minute limit'), 15 * 60 * 1000);
      const onExit = () => stop('page exit');
      window.addEventListener('pagehide', onExit);
      cleanups.push(() => window.removeEventListener('pagehide', onExit));
    } else if (command === 'stop') stop('manual');
    else if (command === 'ad' || command === 'program') {
      if (!running) return JSON.stringify({ ok: false, error: 'Start player-event recording first.' });
      append('mark', { label: command });
    }
    const result = { ok: true, running, count: entries.length, dropped, coverage };
    if (command === 'export') result.report = { version: 2, probe: 'player-events', service: 'directv',
      running, dropped, coverage, entries };
    return JSON.stringify(result);
  };
  globalThis.commercialBreakerPlayerEvents.probeVersion = 2;
})();
