(() => {
  if (globalThis.commercialBreakerDiagnostics) return;
  const limit = 1200;
  const duration = 15 * 60 * 1000;
  let timer = null;
  let startedAt = null;
  let entries = [];
  let dropped = 0;
  const adToken = /(^|[\s_-])(ad|ads|advert|advertisement|commercial|adbreak)([\s_-]|$)/i;
  const clip = (value) => String(value || "").slice(0, 160);
  const finiteOrNull = (value) => Number.isFinite(value) ? value : null;
  function visible(element) {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
      rect.top < innerHeight && rect.left < innerWidth && style.display !== "none" &&
      style.visibility === "visible" && Number(style.opacity) > 0;
  }
  function append(entry) {
    if (entries.length === limit) { entries.shift(); dropped++; }
    entries.push({ at: new Date().toISOString(), ...entry });
  }
  function sample() {
    // Record a bounded set of candidate attributes, never page HTML, URLs or cookies.
    const signals = [];
    const nodes = document.querySelectorAll('[class], [id], [aria-label]');
    for (const element of Array.from(nodes).slice(0, 5000)) {
      const classes = Array.from(element.classList).filter((name) => adToken.test(name));
      const id = adToken.test(element.id) ? clip(element.id) : "";
      const rawLabel = element.getAttribute('aria-label') || "";
      const label = adToken.test(rawLabel) ? clip(rawLabel) : "";
      if (classes.length || id || label) {
        signals.push({ tag: element.tagName, classes: classes.slice(0, 10), id, label, visible: visible(element) });
      }
      if (signals.length === 40) break;
    }
    const videos = Array.from(document.querySelectorAll('video')).slice(0, 8).map((video) => ({
      visible: visible(video), paused: video.paused, ended: video.ended,
      muted: video.muted, volume: finiteOrNull(video.volume), readyState: finiteOrNull(video.readyState),
      currentTime: finiteOrNull(video.currentTime),
      duration: finiteOrNull(video.duration),
      adClasses: Array.from(video.classList).filter((name) => adToken.test(name)),
      tracks: Array.from(video.textTracks).map((track) => ({
        kind: track.kind, mode: track.mode,
        activeCues: Array.from(track.activeCues || []).slice(0, 10).map((cue) => ({
          start: finiteOrNull(cue.startTime), end: finiteOrNull(cue.endTime)
        }))
      }))
    }));
    append({ kind: 'sample', videos, signals, scannedElements: Math.min(nodes.length, 5000) });
  }
  function stop(reason) {
    if (timer !== null) {
      clearInterval(timer);
      timer = null;
      append({ kind: 'stop', reason });
    }
  }
  function tick() {
    if (Date.now() - startedAt >= duration) { stop('15-minute limit'); return; }
    try { sample(); }
    catch (error) { append({ kind: 'error', message: clip(error.message) }); stop('sampling error'); }
  }
  globalThis.commercialBreakerDiagnostics = function diagnostics(command) {
    if (location.protocol !== 'https:' ||
        !["paramountplus.com", "directv.com"].some((domain) => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) {
      return { ok: false, error: 'Open DIRECTV or Paramount+ to record player signals.' };
    }
    if (command === 'start' && timer === null) {
      entries = []; dropped = 0; startedAt = Date.now();
      append({ kind: 'start' });
      timer = setInterval(tick, 1000);
      tick();
    } else if (command === 'stop') {
      stop('manual');
    } else if (command === 'ad' || command === 'program') {
      if (timer === null) return { ok: false, error: 'Start recording before marking the broadcast.' };
      append({ kind: 'mark', label: command });
      tick();
    }
    const result = { ok: true, running: timer !== null, count: entries.length, dropped };
    if (command === 'export') {
      result.report = { version: 1, service: location.hostname === "directv.com" || location.hostname.endsWith(".directv.com") ? "directv" : "paramountplus", startedAt, running: timer !== null, dropped, entries };
    }
    return result;
  };
})();
