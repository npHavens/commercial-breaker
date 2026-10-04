// A page click supplies the user gesture required to start Web Audio in Safari.
(() => {
  if (location.protocol !== 'https:' || location.hostname !== 'stream.directv.com') return;
  const existing = document.getElementById('skybox-direct-audio');
  if (existing) { existing.hidden = false; return; }
  const panel = document.createElement('aside');
  panel.id = 'skybox-direct-audio';
  panel.style.cssText = 'position:fixed;top:16px;right:16px;z-index:2147483647;background:#fff;color:#111;padding:16px;width:300px;border:2px solid #168;border-radius:8px;font:14px system-ui;';
  const text = document.createElement('p');
  text.textContent = 'Skybox direct audio test. Keep playback local. If audio becomes silent, refresh this tab to restore the original audio route.';
  const button = document.createElement('button'); button.textContent = 'Start direct audio test';
  const hide = document.createElement('button'); hide.textContent = 'Hide panel';
  panel.append(text, button, hide); document.documentElement.append(panel);
  let route, timer, interval, finish, exited = false;
  const save = (outcome, fields = {}) => {
    const report = { outcome, method: 'media-element-source', measuredAt: new Date().toISOString(), ...fields };
    globalThis.skyboxLastAudioProbeResult = JSON.stringify(report);
    const labels = {
      'nonzero-samples': 'Nonzero audio samples measured.',
      'silent-or-inaccessible': 'Only silence measured. Audio may be blocked; this is not a commercial classification.',
      'context-not-running': 'Web Audio could not start.',
      'analysis-error': 'Audio test failed.',
      'unsupported-analysis': 'Web Audio is unavailable.',
      'page-exit': 'Test stopped on page exit.'
    };
    text.textContent = `${labels[outcome] || outcome} ${fields.errorName || ''} If sound stopped, refresh DIRECTV. The result is available through Show last audio result.`;
  };
  button.addEventListener('click', async () => {
    button.disabled = true;
    finish = undefined;
    text.textContent = 'Starting Web Audio…';
    let context;
    try {
      const candidates = Array.from(document.querySelectorAll('video'), element => {
        const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
        return { element, playing: !element.paused && !element.ended,
          visible: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
            rect.top < innerHeight && rect.left < innerWidth && style.display !== 'none' &&
            style.visibility === 'visible' && Number(style.opacity) > 0 };
      });
      const video = globalThis.skyboxSelectVideo(candidates);
      if (video.webkitCurrentPlaybackTargetIsWireless) throw new Error('Disconnect AirPlay before this test.');
      const Context = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!Context) { save('unsupported-analysis'); return; }
      if (route && route.video !== video) throw new Error('The player changed. Refresh before testing again.');
      context = route?.context || new Context();
      // Arm a deadline before resume: Safari can leave that promise pending.
      let settled = false;
      let peak = 0, sumSquares = 0, samples = 0;
      finish = outcome => {
        if (settled) return;
        settled = true; clearTimeout(timer); clearInterval(interval);
        save(outcome, { peak, rms: samples ? Math.sqrt(sumSquares / samples) : null, samples,
          muted: video.muted, paused: video.paused, wireless: false, contextState: context.state });
        button.disabled = false;
        // An unbound context can be closed. A bound one must remain to carry playback.
        if (!route) context.close().catch(() => {});
      };
      timer = setTimeout(() => finish('context-not-running'), 5000);
      await context.resume();
      if (settled || exited) return;
      if (context.state !== 'running') { finish('context-not-running'); return; }
      if (!route) {
        const analyser = context.createAnalyser(); analyser.fftSize = 2048;
        const source = context.createMediaElementSource(video);
        // Retain the route even on later failure: an element cannot safely be rebound.
        route = { video, context, source, analyser };
        source.connect(analyser); analyser.connect(context.destination);
      }
      const buffer = new Float32Array(route.analyser.fftSize);
      const sample = () => {
        try {
          route.analyser.getFloatTimeDomainData(buffer);
          for (const value of buffer) {
            if (!Number.isFinite(value)) continue;
            peak = Math.max(peak, Math.abs(value)); sumSquares += value * value; samples++;
          }
        } catch { finish('analysis-error'); }
      };
      clearTimeout(timer);
      text.textContent = 'Measuring audio for 3 seconds…';
      interval = setInterval(sample, 100);
      timer = setTimeout(() => { sample(); finish(context.state !== 'running' ? 'context-not-running'
        : peak > 0 ? 'nonzero-samples' : 'silent-or-inaccessible'); }, 3000);
    } catch (error) {
      if (finish) finish('analysis-error');
      else save('analysis-error', { errorName: error.name });
      button.disabled = false;
    }
  });
  // Hiding does not disconnect the graph: doing so would stop the player's audio.
  hide.addEventListener('click', () => { panel.hidden = true; });
  window.addEventListener('pagehide', () => {
    exited = true; finish?.('page-exit'); clearTimeout(timer); clearInterval(interval);
    if (route) {
      route.source.disconnect(); route.analyser.disconnect(); route.context.close().catch(() => {});
    }
  }, { once: true });
})();
