(() => {
  const service = [
    { domain: 'directv.com', name: 'DIRECTV' },
    { domain: 'paramountplus.com', name: 'Paramount+' }
  ].find(({ domain }) => location.hostname === domain || location.hostname.endsWith(`.${domain}`));
  if (location.protocol !== 'https:' || !service) {
    return { ok: false, error: 'Open a DIRECTV or Paramount+ player first.' };
  }
  if (globalThis.commercialBreakerAirPlayPanel?.isConnected) {
    return globalThis.commercialBreakerAirPlayPanel.commercialBreakerVersion === '0.1.11' ? { ok: true } :
      { ok: false, error: 'Close the old page panel with Restore settings and close, then try again.' };
  }
  const host = document.createElement('div');
  globalThis.commercialBreakerAirPlayPanel = host;
  host.commercialBreakerVersion = '0.1.11';
  host.style.cssText = 'position:fixed;top:20px;right:20px;z-index:2147483647;';
  const root = host.attachShadow({ mode: 'closed' });
  const panel = document.createElement('section');
  panel.style.cssText = 'width:300px;padding:16px;background:#18202d;color:white;border:1px solid #8693a6;border-radius:12px;font:14px/1.5 system-ui;box-shadow:0 4px 20px #0008;';
  const title = document.createElement('strong');
  title.textContent = `Commercial Breaker · ${service.name} AirPlay · v0.1.11`;
  const status = document.createElement('p');
  status.setAttribute('role', 'status');
  status.textContent = 'Turn off Mac Screen Mirroring first. Then click Try AirPlay here.';
  const button = document.createElement('button');
  button.textContent = 'Try AirPlay';
  const close = document.createElement('button');
  close.textContent = 'Restore settings and close';
  const routeButton = document.createElement('button');
  routeButton.textContent = 'Test return route (15 seconds)';
  for (const control of [button, close, routeButton]) {
    control.style.cssText = 'display:block;width:100%;padding:9px;margin-top:8px;font:inherit;cursor:pointer;';
  }
  const history = document.createElement('textarea');
  history.readOnly = true;
  history.rows = 8;
  history.setAttribute('aria-label', 'AirPlay connection history');
  history.style.cssText = 'width:100%;box-sizing:border-box;margin-top:10px;font:12px/1.4 monospace;';
  const entries = [];
  const playbackEvents = [];
  // Return a string so Safari never serializes nested media numbers natively.
  globalThis.commercialBreakerExportAirPlayPlayback = () => JSON.stringify({
    schemaVersion: 1, kind: 'airplay-playback', exportedAt: new Date().toISOString(),
    service: service.name, events: playbackEvents
  });
  function snapshot(video) {
    if (!video) return null;
    const finite = value => Number.isFinite(value) ? value : null;
    let bufferedEnd = null;
    try { if (video.buffered?.length) bufferedEnd = finite(video.buffered.end(video.buffered.length - 1)); } catch {}
    return {
      sourceKind: sourceKind(video.currentSrc), wireless: Boolean(video.webkitCurrentPlaybackTargetIsWireless),
      paused: Boolean(video.paused), ready: finite(video.readyState), network: finite(video.networkState),
      time: finite(video.currentTime), bufferedEnd, error: video.error?.code || 0,
      captionsVisible: typeof video.webkitClosedCaptionsVisible === 'boolean' ? video.webkitClosedCaptionsVisible : null,
      tracks: Array.from(video.textTracks || []).slice(0, 16).map(t => ({ kind: t.kind, mode: t.mode }))
    };
  }
  function recordPlayback(event, video) {
    playbackEvents.push({ at: new Date().toISOString(), event, video: snapshot(video) });
    if (playbackEvents.length > 1200) playbackEvents.shift();
  }
  function report(message) {
    recordPlayback(message.replace(/https?:\/\/\S+/gi, '[url]'), selectedVideo);
    status.textContent = message;
    entries.push(`${new Date().toLocaleTimeString()} · ${message}`);
    if (entries.length > 40) entries.shift();
    history.value = entries.join('\n');
    history.scrollTop = history.scrollHeight;
  }
  function sourceKind(value) {
    if (!value) return 'none';
    if (value.startsWith('blob:')) return 'blob';
    if (/^https?:/i.test(value)) return 'network';
    return 'other';
  }
  function describe(video) {
    const alternatives = Array.from(video.querySelectorAll('source'))
      .filter((source) => sourceKind(source.src) === 'network').length;
    return `source=${sourceKind(video.currentSrc)}, network alternatives=${alternatives}, ` +
      `wireless=${Boolean(video.webkitCurrentPlaybackTargetIsWireless)}, ` +
      `paused=${video.paused}, ready=${video.readyState}, error=${video.error?.code || 0}`;
  }
  function enable(video) {
    // Write only changed attributes so our observer cannot trigger itself indefinitely.
    let changed = false;
    for (const name of ['disableremoteplayback', 'x-webkit-wirelessvideoplaybackdisabled']) {
      if (video.hasAttribute(name)) { video.removeAttribute(name); changed = true; }
    }
    if (video.getAttribute('x-webkit-airplay') !== 'allow') {
      video.setAttribute('x-webkit-airplay', 'allow'); changed = true;
    }
    return changed;
  }
  // DIRECTV can restore captions on each AirPlay connection despite its UI
  // showing Off. Reset only presentation tracks; metadata drives diagnostics.
  const captionOriginals = new Map();
  function disableCaptions(video, reason) {
    if (service.name !== 'DIRECTV') return;
    let saved = captionOriginals.get(video);
    if (!saved) {
      saved = { tracks: new Map(), visible: undefined };
      captionOriginals.set(video, saved);
    }
    let count = 0;
    let failed = false;
    for (const track of Array.from(video.textTracks || [])) {
      if (track.kind !== 'captions' && track.kind !== 'subtitles') continue;
      try {
        if (!saved.tracks.has(track)) saved.tracks.set(track, track.mode);
        track.mode = 'disabled';
        count++;
      } catch { failed = true; }
    }
    try {
      if (typeof video.webkitClosedCaptionsVisible === 'boolean') {
        if (saved.visible === undefined) saved.visible = video.webkitClosedCaptionsVisible;
        video.webkitClosedCaptionsVisible = false;
      }
    } catch { failed = true; }
    report(`Captions off requested (${reason}; ${count} text tracks${failed ? '; some controls unavailable' : ''}). Verify on TV.`);
  }
  const originals = new Map();
  const attributes = ['disableremoteplayback', 'x-webkit-wirelessvideoplaybackdisabled', 'x-webkit-airplay'];
  const listeners = new Map();
  let selectedVideo;
  let route;
  function endRoute(message) {
    if (!route) return;
    const current = route;
    route = undefined;
    for (const timer of current.timers) clearTimeout(timer);
    current.video.removeEventListener('webkitcurrentplaybacktargetiswirelesschanged', current.handler);
    if (current.original === null) current.video.removeAttribute('disableremoteplayback');
    else current.video.setAttribute('disableremoteplayback', current.original);
    routeButton.disabled = false;
    button.disabled = false;
    report(message);
    globalThis.commercialBreakerAirPlayRouteResult = JSON.stringify({
      measuredAt: new Date().toISOString(), message,
      sawLocal: current.sawLocal, sawReturn: current.sawReturn,
      wireless: current.video.webkitCurrentPlaybackTargetIsWireless === true,
      history: entries.slice()
    });
  }
  routeButton.addEventListener('click', () => {
    if (route) return;
    const video = selectedVideo;
    if (!video?.isConnected || video.webkitCurrentPlaybackTargetIsWireless !== true) {
      report('First use Try AirPlay to select the TV and wait for connected playback.');
      return;
    }
    const current = {
      video, original: video.getAttribute('disableremoteplayback'),
      timers: [], phase: 'disable', sawLocal: false, sawReturn: false
    };
    current.handler = () => {
      if (route !== current) return;
      const wireless = video.webkitCurrentPlaybackTargetIsWireless === true;
      if (current.phase === 'disable' && !wireless) current.sawLocal = true;
      if (current.phase === 'enable' && current.sawLocal && wireless) current.sawReturn = true;
      report(`Route test (${current.phase}): ${describe(video)}`);
    };
    route = current;
    routeButton.disabled = true;
    button.disabled = true;
    video.addEventListener('webkitcurrentplaybacktargetiswirelesschanged', current.handler);
    try {
      // Diagnostic only: allowing remote playback again is not a device-selection API.
      video.setAttribute('disableremoteplayback', '');
      report('Remote playback disabled for 5 seconds. Sound may move to the Mac. No picker will open automatically.');
      current.timers.push(setTimeout(() => {
        if (route !== current) return;
        if (!video.isConnected) { endRoute('Inconclusive: player was replaced during the test.'); return; }
        if (!video.webkitCurrentPlaybackTargetIsWireless) current.sawLocal = true;
        current.phase = 'enable';
        video.removeAttribute('disableremoteplayback');
        report(`Remote playback allowed again; waiting 10 seconds for automatic return: ${describe(video)}`);
        current.timers.push(setTimeout(() => {
          if (route !== current) return;
          if (!video.isConnected) { endRoute('Inconclusive: player was replaced during the test.'); return; }
          const returned = current.sawLocal && current.sawReturn && video.webkitCurrentPlaybackTargetIsWireless === true;
          endRoute(returned ? 'Local → wireless route events observed without opening the picker. Verify TV picture and sound.' :
            current.sawLocal ? 'Returned to local playback, but no automatic TV return was confirmed. Use Try AirPlay to reconnect.' :
              'No local playback transition observed. Disabling remote playback did not establish a round trip.');
        }, 10000));
      }, 5000));
    } catch (error) { endRoute(`Route test failed: ${error.message}`); }
  });
  button.addEventListener('click', () => {
    try {
      const candidates = Array.from(document.querySelectorAll('video'), (element) => {
        const rect = element.getBoundingClientRect();
        const style = getComputedStyle(element);
        return { element, playing: !element.paused && !element.ended,
          visible: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
            rect.top < innerHeight && rect.left < innerWidth && style.display !== 'none' &&
            style.visibility === 'visible' && Number(style.opacity) > 0 };
      });
      const video = globalThis.commercialBreakerSelectVideo(candidates);
      selectedVideo = video;
      if (typeof video.webkitShowPlaybackTargetPicker !== 'function') {
        throw new Error('Safari’s AirPlay picker is unavailable on this video.');
      }
      if (!originals.has(video)) {
        originals.set(video, attributes.map((name) => [name, video.getAttribute(name)]));
        const handlers = new Map();
        for (const name of ['webkitcurrentplaybacktargetiswirelesschanged',
          'webkitplaybacktargetavailabilitychanged', 'emptied', 'loadedmetadata', 'error',
          'loadstart', 'waiting', 'stalled', 'playing', 'pause', 'seeking', 'seeked', 'ended', 'canplay']) {
          const handler = (event) => {
            if ((name === 'webkitcurrentplaybacktargetiswirelesschanged' || name === 'loadedmetadata') &&
                video.webkitCurrentPlaybackTargetIsWireless === true) {
              disableCaptions(video, 'AirPlay connected');
            }
            report(`${name}${event.availability ? `: ${event.availability}` : ''}: ${describe(video)}`);
          };
          video.addEventListener(name, handler);
          handlers.set(name, handler);
        }
        let lastProgress = 0;
        const progress = () => {
          if (Date.now() - lastProgress < 5000) return;
          lastProgress = Date.now();
          recordPlayback('progress', video);
        };
        video.addEventListener('timeupdate', progress);
        handlers.set('timeupdate', progress);
        const trackHandlers = new Map();
        for (const event of ['change', 'addtrack', 'removetrack']) {
          const handler = () => recordPlayback(`textTracks:${event}`, video);
          video.textTracks?.addEventListener?.(event, handler);
          trackHandlers.set(event, handler);
        }
        let resets = 0;
        const observer = new MutationObserver((records) => {
          if (route?.video === video) return; // Do not undo the routing experiment.
          if (records.some((record) => attributes.includes(record.attributeName))) {
            const disabled = video.hasAttribute('disableremoteplayback') ||
              video.hasAttribute('x-webkit-wirelessvideoplaybackdisabled') ||
              video.getAttribute('x-webkit-airplay') !== 'allow';
            if (disabled) {
              if (++resets <= 10) {
                enable(video);
                report(`Player reset AirPlay settings; reapplied (${resets}/10).`);
              } else {
                observer.disconnect();
                report('Player repeatedly rejects AirPlay settings; stopped reapplying.');
              }
            }
          }
          if (records.some((record) => record.type === 'childList' || record.attributeName === 'src')) {
            report(`Player source changed: ${describe(video)}`);
          }
        });
        observer.observe(video, { attributes: true, attributeFilter: [...attributes, 'src'], childList: true, subtree: true });
        const removalObserver = new MutationObserver(() => {
          if (!video.isConnected) {
            if (route?.video === video) endRoute('Inconclusive: player was replaced during the test.');
            observer.disconnect();
            removalObserver.disconnect();
            for (const [name, handler] of handlers) video.removeEventListener(name, handler);
            for (const [name, handler] of trackHandlers) video.textTracks?.removeEventListener?.(name, handler);
            report('Selected video was removed by the site. Start playback, then click Try AirPlay again.');
          }
        });
        removalObserver.observe(document.documentElement, { childList: true, subtree: true });
        listeners.set(video, { handlers, trackHandlers, observer, removalObserver });
      }
      const wasDisabled = video.hasAttribute('disableremoteplayback') ||
        video.hasAttribute('x-webkit-wirelessvideoplaybackdisabled') ||
        video.getAttribute('x-webkit-airplay') === 'deny';
      enable(video);
      disableCaptions(video, 'before picker');
      report(`${wasDisabled ? 'Removed disabling attributes. ' : ''}Picker requested: ${describe(video)}`);
      if (sourceKind(video.currentSrc) === 'blob' &&
          !Array.from(video.querySelectorAll('source')).some((source) => sourceKind(source.src) === 'network')) {
        report('Blob source with no network alternative exposed in this video. AirPlay may need a source supplied by the service.');
      }
      // Synchronous call from a real page click preserves Safari's user gesture.
      video.webkitShowPlaybackTargetPicker();
    } catch (error) {
      report(error.message || 'Could not request AirPlay.');
    }
  });
  const onPageHide = () => endRoute('Page left; routing test canceled and settings restored.');
  globalThis.addEventListener('pagehide', onPageHide);
  close.addEventListener('click', () => {
    endRoute('Routing test canceled; settings restored.');
    globalThis.removeEventListener('pagehide', onPageHide);
    for (const [video, values] of originals) {
      const { handlers, trackHandlers, observer, removalObserver } = listeners.get(video);
      observer.disconnect();
      removalObserver.disconnect();
      for (const [name, handler] of handlers) video.removeEventListener(name, handler);
      for (const [name, handler] of trackHandlers) video.textTracks?.removeEventListener?.(name, handler);
      for (const [name, value] of values) {
        if (value === null) video.removeAttribute(name);
        else video.setAttribute(name, value);
      }
    }
    for (const [video, saved] of captionOriginals) {
      for (const [track, mode] of saved.tracks) {
        try { track.mode = mode; } catch { /* Removed tracks may reject writes. */ }
      }
      if (saved.visible !== undefined) {
        try { video.webkitClosedCaptionsVisible = saved.visible; } catch { /* Best-effort restore. */ }
      }
    }
    captionOriginals.clear();
    document.dispatchEvent?.(new Event('commercial-breaker-airplay-trace-stop'));
    host.remove();
    delete globalThis.commercialBreakerAirPlayPanel;
  });
  panel.append(title, status, button, routeButton, history, close);
  root.append(panel);
  document.documentElement.append(host);
  return { ok: true };
})();
