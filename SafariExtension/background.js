// Credentials are scoped to one explicitly armed tab and live only in memory.
const capture = globalThis.commercialBreakerParamountCapture;
let session = null;
let message = 'Start the extension helper, then capture the playing Paramount tab.';
let expiryTimer;
function clearSession() {
  clearTimeout(expiryTimer);
  session = null;
}
function active(details) {
  return session && !session.sending && details.tabId === session.tabId && Date.now() < session.expires;
}
async function sendIfReady() {
  const current = session;
  if (!current || current.sending || !current.playlist || !current.token) return;
  current.sending = true;
  message = 'Checking the playlist and key with the local relay…';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 45000);
  try {
    const response = await fetch('http://127.0.0.1:8766/session', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${current.code}` },
      body: JSON.stringify({ playlist: current.playlist, token: current.token }),
      signal: controller.signal, credentials: 'omit', redirect: 'error', cache: 'no-store'
    });
    const data = await response.json();
    if (session !== current) return;
    if (!response.ok) {
      message = response.status === 403 ? 'Pairing failed. Use the current helper code and capture again.' :
        response.status === 409 ? 'Helper already has a session or is busy. Check its window before retrying.' :
        'Relay validation failed. Capture again after reloading Paramount.';
      return;
    }
    if (!globalThis.commercialBreakerIsRelayUrl(data.url)) throw new Error('Invalid relay response');
    await browser.tabs.create({ url: data.url });
    message = 'Relay opened. Pause the original Paramount player, then Play → Choose AirPlay in the relay. Leave its automatic mute off when using the native app.';
  } catch {
    if (session === current) message = 'Could not open the relay. Check that the extension helper is running and Safari allows local access.';
  } finally {
    clearTimeout(timer);
    if (session === current) clearSession();
    current.token = current.code = current.playlist = null;
    current.keys.clear();
  }
}
browser.webRequest.onSendHeaders.addListener(details => {
  if (!active(details) || !capture.key(details.url)) return;
  const token = capture.token(details.requestHeaders);
  if (token && session.keys.size < 20) session.keys.set(details.requestId, token);
}, { urls: ['https://cbsi.live.ott.irdeto.com/*'] }, ['requestHeaders']);
browser.webRequest.onCompleted.addListener(details => {
  if (!active(details)) return;
  if (details.statusCode === 200 && capture.playlist(details.url)) session.playlist = details.url;
  if (capture.key(details.url)) {
    const token = session.keys.get(details.requestId);
    session.keys.delete(details.requestId);
    if (details.statusCode === 200 && token) session.token = token;
  }
  message = session.playlist ? 'Playlist captured; waiting for an authorized key request. Reload Paramount if needed.' :
    'Waiting for Paramount playback requests. Reload the Paramount tab and resume playback.';
  void sendIfReady();
}, { urls: ['https://dai.google.com/*', 'https://cbsi.live.ott.irdeto.com/*'] });
browser.webRequest.onErrorOccurred.addListener(details => {
  if (session?.tabId === details.tabId) session.keys.delete(details.requestId);
}, { urls: ['https://cbsi.live.ott.irdeto.com/*'] });
browser.tabs.onRemoved.addListener(tabId => {
  if (session?.tabId === tabId && !session.sending) { clearSession(); message = 'Capture canceled: Paramount tab closed.'; }
});
browser.tabs.onUpdated.addListener((tabId, change) => {
  if (session?.tabId !== tabId || !change.url || session.sending) return;
  if (!capture.paramount(change.url)) { clearSession(); message = 'Capture canceled: tab left Paramount.'; }
  else { session.playlist = session.token = null; session.keys.clear(); }
});
browser.runtime.onMessage.addListener(async (request, sender) => {
  if (sender.id !== browser.runtime.id || sender.tab) return;
  if (request?.type === 'paramount-status') return { message, capturing: Boolean(session) };
  if (request?.type !== 'paramount-capture') return;
  if (session?.sending) return { message: 'Relay setup is already running.' };
  const tab = await browser.tabs.get(request.tabId);
  if (!capture.paramount(tab.url)) return { message: 'Open the playing Paramount tab first.' };
  if (!/^[A-Za-z0-9_-]{32}$/.test(request.code || '')) return { message: 'Paste the pairing code from the extension helper window.' };
  clearSession();
  session = { tabId: tab.id, code: request.code, expires: Date.now() + 120000, keys: new Map() };
  message = 'Capture armed for two minutes. Reload this Paramount tab and resume playback; the relay will open automatically.';
  expiryTimer = setTimeout(() => {
    if (session && !session.sending) { clearSession(); message = 'Capture expired. Try again and reload Paramount to trigger a fresh key request.'; }
  }, 120000);
  return { message, capturing: true };
});
