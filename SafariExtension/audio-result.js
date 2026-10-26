// Synchronous recovery avoids depending on the popup that initiated capture.
(() => {
  if (globalThis.commercialBreakerAudioProbePending) return JSON.stringify({ outcome: 'pending' });
  return typeof globalThis.commercialBreakerLastAudioProbeResult === 'string'
    ? globalThis.commercialBreakerLastAudioProbeResult : JSON.stringify({ outcome: 'not-tested' });
})();
