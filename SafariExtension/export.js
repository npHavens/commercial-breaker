// Keep fallback Blob URLs in a persistent extension tab, never in the popup.
globalThis.commercialBreakerValidateExport = function validateExport(json) {
  const report = JSON.parse(json);
  const hasRecords = report && !Array.isArray(report) &&
    ((Array.isArray(report.entries) && report.entries.length > 0) ||
      (Array.isArray(report.events) && report.events.length > 0) ||
      (report.probe === 'audio-access' && typeof report.at === 'string'));
  if (!hasRecords) throw new Error("There is no recording to save");
};

globalThis.commercialBreakerSaveRecording = async function saveRecording(browser, json) {
  globalThis.commercialBreakerValidateExport(json);
  const filename = `skybox-signals-${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
  if (browser.downloads?.download) {
    try {
      await browser.downloads.download({
        url: `data:application/json;charset=utf-8,${encodeURIComponent(json)}`,
        filename, saveAs: true
      });
      return { method: 'download' };
    } catch { /* Safari may expose the API but reject its use. Offer a normal link. */ }
  }
  if (!browser.tabs?.create || !browser.runtime?.getURL) {
    throw new Error("Safari cannot open the recording save page. The JSON remains in the popup.");
  }
  // One recovery copy, overwritten only by the next export. No page or stream URLs.
  localStorage.setItem('skybox.recording-export', JSON.stringify({ filename, json }));
  await browser.tabs.create({ url: browser.runtime.getURL('save-recording.html') });
  return { method: 'page' };
};
