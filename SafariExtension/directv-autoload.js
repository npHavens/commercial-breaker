// Persist the DIRECTV handoff correction across full page loads. No player controls
// are invoked here; the MAIN-world script validates its own correction conditions.
(() => {
  const supported = url => {
    try { return new URL(url).origin === 'https://stream.directv.com'; } catch { return false; }
  };
  async function attach(tabId, url) {
    if (!Number.isInteger(tabId) || !supported(url)) return;
    try {
      await browser.scripting.executeScript({ target: { tabId }, world: 'MAIN',
        files: ['airplay-source-trace.js', 'directv-airplay-recovery.js'] });
    } catch {
      // Permission may be withheld, or the tab may navigate/close before injection.
      console.warn('Commercial Breaker: DIRECTV recovery could not attach; retry using the AirPlay panel.');
    }
  }
  browser.tabs.onUpdated.addListener((tabId, change, tab) => {
    if (change.status === 'complete') void attach(tabId, tab?.url);
  });
  browser.tabs.query({ url: 'https://stream.directv.com/*' }).then(tabs => {
    for (const tab of tabs) if (tab.status === 'complete') void attach(tab.id, tab.url);
  }).catch(() => console.warn('Commercial Breaker: could not inspect existing DIRECTV tabs.'));
})();
