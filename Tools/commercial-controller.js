// Runs on the relay page so closing the extension popup does not stop monitoring.
globalThis.commercialBreakerCreateCommercialController = function createCommercialController(video, publish) {
  let enabled = false;
  let ownsMute = false;
  let state = 'unknown';
  let message = 'Automatic commercial mute is off.';
  let generation = 0;
  let pending = null;
  let lastRequest = -Infinity;
  let lastDecision = null;
  let lastMuted = video.muted;
  let lastVolume = video.volume;

  function status() {
    return { enabled, state, message, muted: video.muted, ownsMute,
      paused: video.paused, wireless: Boolean(video.webkitCurrentPlaybackTargetIsWireless) };
  }
  function notify() { publish(status()); }
  function setMuted(value) {
    lastMuted = value;
    lastVolume = video.volume;
    video.muted = value;
  }
  function release() {
    if (ownsMute && video.muted) setMuted(false);
    ownsMute = false;
  }
  function unknown(reason) {
    release();
    state = 'unknown';
    message = reason;
    lastDecision = null;
    notify();
  }
  function playbackDate() {
    if (video.paused || video.seeking || video.ended || video.error || video.readyState < 2) return null;
    try {
      const start = video.getStartDate?.().getTime();
      return Number.isFinite(start) && Number.isFinite(video.currentTime) ? start + video.currentTime * 1000 : null;
    } catch { return null; }
  }
  function covered(decision, position) {
    return position !== null && Number.isFinite(decision?.startMs) && Number.isFinite(decision?.endMs) &&
      decision.startMs <= position && position < decision.endMs;
  }
  function stop(restore = true, reason = 'Automatic commercial mute is off.') {
    enabled = false;
    generation++;
    pending?.abort();
    if (restore) release();
    else ownsMute = false;
    lastDecision = null;
    state = 'unknown';
    message = reason;
    notify();
  }
  async function tick() {
    if (!enabled) return;
    const position = playbackDate();
    if (position === null) {
      unknown('Waiting for a valid playback clock.');
      return;
    }
    if (lastDecision && (!covered(lastDecision, position) || Date.now() - lastDecision.receivedAt > 5000)) {
      unknown('Refreshing commercial timing.');
    }
    if (pending || Date.now() - lastRequest < 900) return;
    const currentGeneration = generation;
    const abort = new AbortController();
    pending = abort;
    lastRequest = Date.now();
    const deadline = setTimeout(() => abort.abort(), 3000);
    try {
      const response = await fetch(`commercial-state?playhead_ms=${encodeURIComponent(position)}`, {
        cache: 'no-store', signal: abort.signal
      });
      if (!response.ok) throw new Error();
      const decision = await response.json();
      if (!enabled || generation !== currentGeneration) return;
      const age = Date.now() - decision.sampledAtMs;
      if (!Number.isFinite(decision.sampledAtMs) || age < 0 || age > 15000 ||
          !covered(decision, playbackDate()) || !['ad', 'program'].includes(decision.state)) {
        unknown(decision.hasTimeline === false ? 'No dated commercial timeline is available.' : 'Commercial timing is unknown.');
        return;
      }
      lastDecision = { ...decision, receivedAt: Date.now() };
      state = decision.state;
      if (state === 'ad') {
        if (!video.muted) { ownsMute = true; setMuted(true); }
        message = ownsMute ? 'Commercial detected · muted automatically.' : 'Commercial detected · already muted.';
      } else {
        release();
        message = video.muted ? 'Program · your manual mute is preserved.' : 'Program · sound on.';
      }
      notify();
    } catch {
      if (enabled && generation === currentGeneration) unknown('Commercial timing unavailable; automatic mute released.');
    } finally {
      clearTimeout(deadline);
      if (pending === abort) pending = null;
    }
  }
  function toggle() {
    if (enabled) stop();
    else {
      enabled = true;
      generation++;
      lastRequest = -Infinity;
      message = 'Checking commercial timing…';
      notify();
      void tick();
    }
  }
  function manualToggle() {
    const desired = !video.muted;
    stop(false, 'Manual mute control · automatic mode is off.');
    setMuted(desired);
    notify();
  }
  function volumeChanged() {
    const externalChange = video.muted !== lastMuted || video.volume !== lastVolume;
    lastMuted = video.muted;
    lastVolume = video.volume;
    if (enabled && externalChange) stop(true, 'Manual audio change · automatic mode is off.');
    notify();
  }
  function resetTiming() {
    generation++;
    pending?.abort();
    lastRequest = -Infinity;
    if (enabled) unknown('Waiting for playback timing.');
  }
  const interval = setInterval(() => { void tick(); }, 1000);
  const onTime = () => { void tick(); };
  video.addEventListener('timeupdate', onTime);
  video.addEventListener('volumechange', volumeChanged);
  for (const event of ['seeking', 'pause', 'emptied', 'error']) video.addEventListener(event, resetTiming);
  notify();
  return {
    status, toggle, manualToggle, tick,
    stop: () => stop(),
    dispose() {
      stop();
      clearInterval(interval);
      video.removeEventListener('timeupdate', onTime);
      video.removeEventListener('volumechange', volumeChanged);
      for (const event of ['seeking', 'pause', 'emptied', 'error']) video.removeEventListener(event, resetTiming);
    }
  };
};

if (typeof document !== 'undefined') {
  const output = document.querySelector('#commercial-breaker-commercial-state');
  const button = document.querySelector('#commercial-breaker-auto-toggle');
  const history = document.querySelector('#commercial-breaker-auto-history');
  const transitions = [];
  let previous = '';
  globalThis.commercialBreakerCommercial = globalThis.commercialBreakerCreateCommercialController(document.querySelector('#video'), (state) => {
    output.textContent = JSON.stringify(state);
    document.querySelector('#commercial-breaker-auto-status').textContent = state.message;
    button.textContent = state.enabled ? 'Disable automatic mute' : 'Enable automatic mute';
    const signature = JSON.stringify([state.enabled, state.state, state.message, state.muted]);
    if (signature !== previous) {
      previous = signature;
      transitions.push(`${new Date().toLocaleTimeString()} · ${state.message} muted=${state.muted}`);
      if (transitions.length > 30) transitions.shift();
      history.value = transitions.join('\n');
      history.scrollTop = history.scrollHeight;
    }
  });
  button.addEventListener('click', () => globalThis.commercialBreakerCommercial.toggle());
}
