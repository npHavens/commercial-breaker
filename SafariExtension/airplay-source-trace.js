// Runs in MAIN so calls made by the site's player cross these wrappers.
(() => {
  if (location.protocol !== 'https:' || !['directv.com', 'paramountplus.com'].some(
    domain => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) return;
  if (globalThis.commercialBreakerAirPlaySourceTrace?.running) return;
  const events = [], restores = [], coverage = [];
  const videos = new WeakMap(), scripts = new Map();
  let nextVideo = 0, dropped = 0, running = true;
  function caller() {
    // Never export raw stacks: script URLs can contain credentials or session IDs.
    return String(new Error().stack || '').split('\n').slice(2, 14).flatMap(line => {
      const match = line.match(/(https?:\/\/[^\s)]+?):(\d+):(\d+)\)?$/);
      if (!match) return [];
      const url = new URL(match[1]);
      const key = url.origin + url.pathname;
      if (!scripts.has(key) && scripts.size < 128) scripts.set(key, scripts.size + 1);
      return [{ script: scripts.get(key) ?? null, origin: url.origin, line: Number(match[2]), column: Number(match[3]) }];
    });
  }
  function record(element, operation) {
    try {
      const video = element instanceof HTMLVideoElement ? element :
        element instanceof HTMLSourceElement && element.parentElement instanceof HTMLVideoElement ? element.parentElement : null;
      if (!video) return;
      if (!videos.has(video)) videos.set(video, ++nextVideo);
      events.push({ at: new Date().toISOString(), operation, videoId: videos.get(video),
        time: Number.isFinite(video.currentTime) ? video.currentTime : null,
        wireless: video.webkitCurrentPlaybackTargetIsWireless === true, callers: caller() });
      if (events.length > 600) { events.shift(); dropped++; }
    } catch { /* Diagnostics must never prevent a player operation. */ }
  }
  function wrap(prototype, name, setter = false, filter = () => true) {
    const original = Object.getOwnPropertyDescriptor(prototype, name);
    const fn = setter ? original?.set : original?.value;
    if (typeof fn !== 'function' || !original.configurable) return;
    const replacement = function (...args) {
      if (running && filter(args)) record(this, `${prototype.constructor.name}.${name}${setter ? '=' : '()'}`);
      return Reflect.apply(fn, this, args);
    };
    const descriptor = { ...original, [setter ? 'set' : 'value']: replacement };
    Object.defineProperty(prototype, name, descriptor);
    coverage.push(`${prototype.constructor.name}.${name}`);
    restores.push(() => {
      const current = Object.getOwnPropertyDescriptor(prototype, name);
      if ((setter ? current?.set : current?.value) === replacement) Object.defineProperty(prototype, name, original);
    });
  }
  function stop() {
    running = false;
    clearTimeout(expiry);
    for (const restore of restores.reverse()) { try { restore(); } catch {} }
    document.removeEventListener('skybox-airplay-trace-stop', stop);
    globalThis.removeEventListener('pagehide', stop);
  }
  const expiry = setTimeout(stop, 60 * 60 * 1000);
  globalThis.commercialBreakerAirPlaySourceTrace = {
    get running() { return running; },
    export: () => JSON.stringify({ running, coverage, dropped, events,
      limitation: 'MAIN-world JavaScript calls only; cached native methods, other frames/worlds and browser-internal reloads may bypass tracing. Script IDs identify callers without exporting source URLs.' })
  };
  for (const [prototype, name, setter, filter] of [
    [HTMLMediaElement.prototype, 'load'], [HTMLMediaElement.prototype, 'src', true],
    [HTMLMediaElement.prototype, 'srcObject', true], [HTMLSourceElement.prototype, 'src', true],
    [Element.prototype, 'setAttribute', false, args => typeof args[0] === 'string' && args[0].toLowerCase() === 'src'],
    [Element.prototype, 'removeAttribute', false, args => typeof args[0] === 'string' && args[0].toLowerCase() === 'src']
  ]) {
    try { wrap(prototype, name, setter, filter); } catch { /* Coverage reports successful hooks only. */ }
  }
  document.addEventListener('skybox-airplay-trace-stop', stop);
  globalThis.addEventListener('pagehide', stop);
})();
