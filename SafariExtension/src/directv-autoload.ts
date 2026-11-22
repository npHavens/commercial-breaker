// Persist the DIRECTV handoff correction across full page loads. No player controls
// are invoked here; the MAIN-world script validates its own correction conditions.
(() => {
  // new URL() throws on a missing address, and the catch turns that into false.
  const supported: (url: string | undefined) => boolean = url => {
    try { return new URL(url as string).origin === 'https://stream.directv.com'; } catch { return false; }
  };

  async function attach(tabId: number, url: string | undefined) {
    if (!Number.isInteger(tabId) || !supported(url)) return;

    try {
      await browser.scripting.executeScript({ target: { tabId }, world: 'MAIN', files: ['dist/directv-airplay-recovery.js'] });
    } catch {
      // Permission may be withheld, or the tab may navigate/close before injection.
      console.warn('Commercial Breaker: DIRECTV recovery could not attach; retry using the AirPlay panel.');
    }
  }

  browser.tabs.onUpdated.addListener((tabId, change, tab) => {
    if (change.status === 'complete') void attach(tabId, tab?.url);
  });

  browser.tabs.query({ url: 'https://stream.directv.com/*' }).then(tabs => {
    for (const tab of tabs) if (tab.status === 'complete') void attach(tab.id!, tab.url);
  }).catch(() => console.warn('Commercial Breaker: could not inspect existing DIRECTV tabs.'));
})();
