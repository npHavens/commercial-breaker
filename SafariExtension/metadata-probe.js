// A one-shot, read-only probe. Do not change track modes or collect caption text.
(() => {
  const finite = (value) => Number.isFinite(value) ? value : null;
  const knownFields = new Set([
    'key', 'keySpace', 'identifier', 'value', 'data', 'type', 'text', 'info', 'owner',
    'start', 'end', 'duration', 'time', 'timestamp', 'event', 'eventType',
    'ad', 'isAd', 'adBreak', 'breakDuration', 'adBreakStart', 'adBreakEnd', 'splice_insert',
    'splice_time', 'out_of_network_indicator', 'segmentation_type_id'
  ]);
  const knownStrings = new Set([
    'org.id3', 'com.apple.streaming', 'TXXX', 'PRIV', 'ID3',
    'ad', 'ad-start', 'ad-end', 'adbreak', 'commercial', 'program',
    'CUE-OUT', 'CUE-IN', 'SCTE35', 'SCTE-35'
  ]);
  function summarize(value, depth = 0, budget = { left: 80 }, seen = new Set()) {
    if (--budget.left < 0) return { type: 'truncated' };
    if (value === null) return { type: 'null' };
    if (typeof value === 'string') {
      // Only explicitly recognized protocol/event labels leave the page.
      if (knownStrings.has(value)) return { type: 'string', value };
      const result = { type: 'string', length: value.length };
      if (value.length <= 4096 && depth < 3) {
        const trimmed = value.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            result.encoding = 'json';
            result.shape = summarize(JSON.parse(trimmed), depth + 1, budget, seen);
          } catch { result.encoding = 'invalid-json'; }
        }
        // Export only matched vocabulary, never the surrounding text or URLs.
        result.markers = [...new Set(trimmed.match(/\b(?:SCTE-?35|CUE-OUT|CUE-IN|adBreakStart|adBreakEnd|splice_insert|out_of_network_indicator|segmentation_type_id)\b/gi) || [])]
          .map((marker) => marker.toLowerCase()).slice(0, 8);
      }
      return result;
    }
    if (typeof value === 'number') return { type: 'number', finite: Number.isFinite(value) };
    if (typeof value === 'boolean') return { type: 'boolean', value };
    if (typeof value !== 'object') return { type: typeof value };
    if (ArrayBuffer.isView(value) || value instanceof ArrayBuffer) {
      return { type: 'binary', bytes: value.byteLength };
    }
    if (seen.has(value)) return { type: 'cycle' };
    if (depth >= 3) return { type: Array.isArray(value) ? 'array' : 'object', truncated: true };
    seen.add(value);
    if (Array.isArray(value)) {
      return { type: 'array', length: value.length,
        items: value.slice(0, 8).map((item) => summarize(item, depth + 1, budget, seen)) };
    }
    const fields = [];
    let inspected = 0;
    for (const name of Object.getOwnPropertyNames(value).slice(0, 24)) {
      inspected++;
      // Never invoke payload getters, or export arbitrary keys/identifiers.
      const descriptor = Object.getOwnPropertyDescriptor(value, name);
      fields.push({ name: knownFields.has(name) ? name : '[other]',
        shape: descriptor && 'value' in descriptor ?
          summarize(descriptor.value, depth + 1, budget, seen) : { type: 'accessor' } });
    }
    return { type: 'object', inspected, fields };
  }
  function cueSummary(cue) {
    const result = { start: finite(cue.startTime), end: finite(cue.endTime) };
    for (const field of ['type', 'value', 'data', 'text']) {
      try { result[field] = summarize(cue[field]); }
      catch { result[field] = { type: 'unreadable' }; }
    }
    try {
      const value = cue.value;
      const key = value && Object.getOwnPropertyDescriptor(value, 'key');
      const info = value && Object.getOwnPropertyDescriptor(value, 'info');
      if (key?.value === 'PRIV' && typeof info?.value === 'string') {
        // Inspect only the observed PRIV info field, not captions or arbitrary
        // payload strings. This is pattern redaction, not a secret detector.
        result.privInfo = info.value.slice(0, 2048)
          .replace(/https?:\/\/[^\s<>"']+/gi, '[url]')
          .replace(/\bBearer\s+[^\s,;"']+/gi, 'Bearer [redacted]')
          .replace(/\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g, '[jwt]')
          .replace(/(["'](?:token|authorization|cookie|secret|sessionid|session_id|apikey|api_key)["']\s*:\s*)["'][^"']*["']/gi, '$1"[redacted]"')
          .replace(/\b(token|authorization|cookie|secret|sessionid|session_id|apikey|api_key)\s*[=:]\s*[^\s,;&"']+/gi, '$1=[redacted]')
          .slice(0, 512);
        const data = Object.getOwnPropertyDescriptor(value, 'data')?.value;
        // The observed payload is one byte; retain only that one-byte case.
        if (ArrayBuffer.isView(data) && data.byteLength === 1) {
          result.privByte = new Uint8Array(data.buffer, data.byteOffset, 1)[0];
        } else if (data instanceof ArrayBuffer && data.byteLength === 1) {
          result.privByte = new Uint8Array(data)[0];
        }
      }
    } catch { result.privInfoUnavailable = true; }
    return result;
  }
  try {
    if (location.protocol !== 'https:' || !['directv.com', 'paramountplus.com'].some(
      (domain) => location.hostname === domain || location.hostname.endsWith(`.${domain}`))) {
      throw new Error('Open DIRECTV or Paramount+ first.');
    }
    const videos = Array.from(document.querySelectorAll('video')).slice(0, 8).map((video) => ({
      currentTime: finite(video.currentTime), paused: video.paused,
      tracks: Array.from(video.textTracks).slice(0, 16).filter((track) => track.kind === 'metadata').map((track) => ({
        mode: track.mode,
        activeCues: Array.from(track.activeCues || []).slice(0, 4).map(cueSummary)
      }))
    }));
    // Stringify before crossing Safari's native injection-result bridge.
    return JSON.stringify({ ok: true, report: { version: 2, probe: 'metadata-shape',
      service: location.hostname === 'directv.com' || location.hostname.endsWith('.directv.com') ? 'directv' : 'paramountplus',
      entries: [{ kind: 'metadata-snapshot', at: new Date().toISOString(), videos }] } });
  } catch (error) {
    return JSON.stringify({ ok: false, error: error.message || 'Metadata inspection failed.' });
  }
})();
