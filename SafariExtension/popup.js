async function activeTarget(domains = ["paramountplus.com", "directv.com"]) {
  if (typeof domains === "string") domains = [domains];
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  const url = new URL(tab?.url || "about:blank");

  if (url.protocol !== "https:" ||
      !domains.some((domain) => url.hostname === domain || url.hostname.endsWith(`.${domain}`))) {
    throw new Error(`Open a video on ${domains.join(" or ")}, then open Commercial Breaker again.`);
  }

  return { tabId: tab.id };
}

const status = document.querySelector("#status");
const refresh = document.querySelector("#refresh");

async function update() {
  refresh.disabled = true;

  try {
    const target = await activeTarget();
    await browser.scripting.executeScript({ target, files: ["dist/select-video.js", "dist/player.js"] });

    const results = await browser.scripting.executeScript({
      target,
      func: () => globalThis.commercialBreakerPlayer()
    });

    const state = results[0]?.result;
    if (!state?.ok) throw new Error(state?.error || "The player did not respond.");

    status.textContent = state.muted ? "Player is muted." :
      state.volume === 0 ? "Player volume is zero. Raise it in the streaming player." : "Player is unmuted.";

    if (state.paused) status.textContent += " Video is paused.";
  } catch (error) {
    status.textContent = error.message || "Allow Commercial Breaker access to this page, then try again.";
  } finally {
    refresh.disabled = false;
  }
}

refresh.addEventListener("click", () => update());

const airplayButton = document.querySelector("#airplay");
const airplayMessage = document.querySelector("#airplay-status");
const airplayHistory = document.querySelector("#airplay-history");
const historyKey = "commercial-breaker.airplay-attempt";
let airplaySteps = [];

try {
  const saved = JSON.parse(localStorage.getItem(historyKey) || "[]");
  if (Array.isArray(saved)) airplaySteps = saved.filter((step) => typeof step === "string").slice(-12);
} catch { /* Diagnostics must not block controls when storage is unavailable. */ }

function renderAirplayHistory() {
  airplayHistory.textContent = airplaySteps.join("\n");
}

function recordAirplayStep(text) {
  airplaySteps.push(`${new Date().toLocaleTimeString()} · ${text}`);
  airplaySteps = airplaySteps.slice(-12);
  renderAirplayHistory();

  try { localStorage.setItem(historyKey, JSON.stringify(airplaySteps)); }
  catch { airplayMessage.textContent += " (History cannot be saved.)"; }
}

renderAirplayHistory();

airplayButton.addEventListener("click", async () => {
  airplayButton.disabled = true;
  airplaySteps = [];
  airplayMessage.textContent = "Adding the AirPlay button to this page…";
  recordAirplayStep("Button clicked; checking active tab.");

  try {
    const target = await activeTarget(["directv.com", "paramountplus.com"]);
    recordAirplayStep("Supported tab found; loading player selection.");
    await browser.scripting.executeScript({ target, files: ["dist/select-video.js"] });
    recordAirplayStep("Player selection loaded; adding page panel.");
    await browser.scripting.executeScript({ target, files: ["dist/airplay-session.js"] });

    const results = await browser.scripting.executeScript({ target, func: () => ({
      ok: globalThis.commercialBreakerAirPlayPanel?.isConnected && globalThis.commercialBreakerAirPlayPanel.commercialBreakerVersion === '0.1.12',
      error: 'Refresh the player page or close the old AirPlay panel, then retry.'
    }) });

    if (!results[0]?.result?.ok) throw new Error(results[0]?.result?.error || "The page did not respond.");
    await browser.scripting.executeScript({ target, world: 'MAIN', files: ['dist/directv-airplay-recovery.js'] });
    recordAirplayStep("Page panel added. Close the popup and look at the top-right of the webpage.");
    airplayMessage.textContent = "Close this popup, exit video fullscreen if necessary, and click Try AirPlay in the Commercial Breaker panel on the page.";
  } catch (error) {
    airplayMessage.textContent = error.message || "Could not add the AirPlay test.";
    recordAirplayStep(`Error: ${airplayMessage.textContent}`);
  } finally {
    airplayButton.disabled = false;
  }
});

async function initialize() {
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });

    // The relay player has its own AirPlay button, and its page isn't a DIRECTV or Paramount+ player.
    if (globalThis.commercialBreakerIsRelayUrl(tab?.url || '')) {
      document.querySelector('#page-status').hidden = true;
      document.querySelector('#airplay-controls').hidden = true;
      document.querySelector('#airplay-history').parentElement.hidden = true;

      return;
    }
  } catch { /* Existing site controls still report their own access errors. */ }

  try {
    await activeTarget();
    document.querySelector("#airplay-controls").hidden = false;
    document.querySelector("#page-status").hidden = false;
  } catch {
    document.querySelector("#airplay-controls").hidden = true;
  }

  update();
}

document.querySelector("#build-status").textContent = "v0.2.23 · Controls ready";
initialize();

async function paramountSetup(start = false) {
  const output = document.querySelector('#paramount-setup-status');
  const input = document.querySelector('#paramount-pairing');

  try {
    const target = start ? await activeTarget('paramountplus.com') : null;

    const result = await browser.runtime.sendMessage(start
      ? { type: 'paramount-capture', tabId: target.tabId, code: input.value.trim() }
      : { type: 'paramount-status' });

    if (start) input.value = '';
    output.textContent = result?.message || 'Background capture unavailable. Reload the extension.';
  } catch {
    output.textContent = 'Open Paramount and allow the extension’s site permissions, then retry.';
  }
}

document.querySelector('#paramount-capture').addEventListener('click', () => paramountSetup(true));
document.querySelector('#paramount-capture-status').addEventListener('click', () => paramountSetup());
void paramountSetup();
