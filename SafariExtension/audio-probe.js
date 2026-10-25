// Capture a separate stream; never reroute the original media element through Web Audio.
(async () => {
  if (globalThis.commercialBreakerAudioProbePending) return globalThis.commercialBreakerAudioProbePending;
  const run = async () => {
    let stream, context, source, analyser, sink, interval, deadline, onExit;
    let samples = 0, peak = 0, sumSquares = 0, blocks = 0;
    const state = {};
    try {
      if (location.protocol !== 'https:' || !['directv.com', 'paramountplus.com'].some(
        domain => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) {
        return JSON.stringify({ outcome: 'wrong-site' });
      }
      const candidates = Array.from(document.querySelectorAll('video'), element => {
        const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
        return { element, playing: !element.paused && !element.ended,
          visible: rect.width > 0 && rect.height > 0 && rect.bottom > 0 && rect.right > 0 &&
            rect.top < innerHeight && rect.left < innerWidth && style.display !== 'none' &&
            style.visibility === 'visible' && Number(style.opacity) > 0 };
      });
      const video = globalThis.commercialBreakerSelectVideo(candidates);
      Object.assign(state, { muted: video.muted, paused: video.paused,
        wireless: typeof video.webkitCurrentPlaybackTargetIsWireless === 'boolean'
          ? video.webkitCurrentPlaybackTargetIsWireless : null });
      if (typeof video.captureStream !== 'function') return JSON.stringify({ ...state, outcome: 'unsupported' });
      const AudioContextClass = globalThis.AudioContext || globalThis.webkitAudioContext;
      if (!AudioContextClass) return JSON.stringify({ ...state, outcome: 'unsupported-analysis' });
      stream = video.captureStream();
      // Video tracks are unnecessary; stopping these capture tracks does not stop playback.
      stream.getVideoTracks().forEach(track => track.stop());
      context = new AudioContextClass();
      const buffer = new Float32Array(2048);
      const outcome = await new Promise(resolve => {
        const finish = result => resolve(result);
        onExit = () => finish('page-exit');
        window.addEventListener('pagehide', onExit);
        const inspect = () => {
          try {
            const tracks = stream.getAudioTracks();
            state.audioTracks = tracks.length;
            state.liveAudioTracks = tracks.filter(t => t.readyState === 'live').length;
            state.unmutedAudioTracks = tracks.filter(t => t.readyState === 'live' && !t.muted).length;
            state.contextState = context.state;
            if (!tracks.length || context.state !== 'running') return;
            if (!source) {
              source = context.createMediaStreamSource(stream);
              analyser = context.createAnalyser(); analyser.fftSize = buffer.length;
              sink = context.createGain(); sink.gain.value = 0;
              source.connect(analyser); analyser.connect(sink); sink.connect(context.destination);
            }
            analyser.getFloatTimeDomainData(buffer);
            blocks++;
            for (const value of buffer) {
              if (!Number.isFinite(value)) continue;
              peak = Math.max(peak, Math.abs(value)); sumSquares += value * value; samples++;
            }
          } catch { finish('analysis-error'); }
        };
        deadline = setTimeout(() => {
          inspect();
          finish(!state.audioTracks ? 'no-audio-track' : context.state !== 'running' ? 'context-not-running'
            : peak > 0 ? 'nonzero-samples' : 'silent-or-inaccessible');
        }, 3000);
        interval = setInterval(inspect, 100);
        // Do not await resume: autoplay policy can leave its promise pending indefinitely.
        context.resume().catch(() => finish('context-not-running'));
        inspect();
      });
      return JSON.stringify({ ...state, outcome, blocks, samples, peak,
        rms: samples ? Math.sqrt(sumSquares / samples) : null });
    } catch (error) {
      return JSON.stringify({ ...state, outcome: stream ? 'analysis-error' : 'capture-failed',
        errorName: error.name || 'Error' });
    } finally {
      clearInterval(interval); clearTimeout(deadline);
      if (onExit) window.removeEventListener('pagehide', onExit);
      for (const node of [source, analyser, sink]) { try { node?.disconnect(); } catch {} }
      for (const track of stream?.getTracks() || []) { try { track.stop(); } catch {} }
      if (context) { try { context.close().catch(() => {}); } catch {} }
    }
  };
  globalThis.commercialBreakerAudioProbePending = run().then(result => {
    globalThis.commercialBreakerLastAudioProbeResult = JSON.stringify({ ...JSON.parse(result), measuredAt: new Date().toISOString() });
    return globalThis.commercialBreakerLastAudioProbeResult;
  });
  try { return await globalThis.commercialBreakerAudioProbePending; }
  finally { delete globalThis.commercialBreakerAudioProbePending; }
})();
