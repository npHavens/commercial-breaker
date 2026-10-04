// Synchronous recovery avoids depending on the popup that initiated capture.
(() => {
  if (globalThis.skyboxAudioProbePending) return JSON.stringify({ outcome: 'pending' });
  return typeof globalThis.skyboxLastAudioProbeResult === 'string'
    ? globalThis.skyboxLastAudioProbeResult : JSON.stringify({ outcome: 'not-tested' });
})();
