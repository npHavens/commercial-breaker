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
const toggle = document.querySelector("#toggle");
const refresh = document.querySelector("#refresh");

async function update(shouldToggle = false) {
  toggle.disabled = true;
  refresh.disabled = true;
  try {
    const target = await activeTarget();
    await browser.scripting.executeScript({ target, files: ["select-video.js", "player.js"] });
    const results = await browser.scripting.executeScript({
      target,
      func: (command) => globalThis.commercialBreakerPlayer(command),
      args: [shouldToggle]
    });
    const state = results[0]?.result;
    if (!state?.ok) throw new Error(state?.error || "The player did not respond.");
    toggle.textContent = state.muted ? "Unmute player" : "Mute player";
    status.textContent = state.muted ? "Player is muted." :
      state.volume === 0 ? "Player volume is zero. Raise it in the streaming player." : "Player is unmuted.";
    if (state.paused) status.textContent += " Video is paused.";
    toggle.disabled = false;
  } catch (error) {
    status.textContent = error.message || "Allow Commercial Breaker access to this page, then try again.";
  } finally {
    refresh.disabled = false;
  }
}

toggle.addEventListener("click", () => update(true));
refresh.addEventListener("click", () => update());

const diagnosticStatus = document.querySelector("#diagnostic-status");
const record = document.querySelector("#record");
const markAd = document.querySelector("#mark-ad");
const markProgram = document.querySelector("#mark-program");
const exportButton = document.querySelector("#export");
let recording = false;

async function diagnostics(command = "status") {
  const buttons = [record, markAd, markProgram, exportButton];
  buttons.forEach((button) => { button.disabled = true; });
  try {
    const target = await activeTarget();
    await browser.scripting.executeScript({ target, files: ["diagnostics.js"] });
    const results = await browser.scripting.executeScript({
      target,
      // Serialize before Safari's native injection-result bridge sees nested numbers.
      // This also protects exports from an older recorder still running in the tab.
      func: (action) => JSON.stringify(globalThis.commercialBreakerDiagnostics(action)),
      args: [command]
    });
    const payload = results[0]?.result;
    if (typeof payload !== "string") throw new Error("Diagnostics returned an invalid response. Reload the Commercial Breaker extension.");
    const result = JSON.parse(payload);
    if (!result?.ok) throw new Error(result?.error || "Diagnostics did not respond.");
    recording = result.running;
    diagnosticStatus.textContent = `${recording ? "Recording" : "Stopped"} · ${result.count} entries`;
    if (command === "ad") diagnosticStatus.textContent += " · Commercial marked";
    if (command === "program") diagnosticStatus.textContent += " · Broadcast marked";
    record.textContent = recording ? "Stop recording" : "Start new recording";
    record.disabled = false;
    markAd.disabled = markProgram.disabled = !recording;
    exportButton.disabled = result.count === 0;
    if (result.report) {
      document.querySelector("#export-panel").hidden = false;
      document.querySelector("#recording-json").value = JSON.stringify(result.report, null, 2);
      document.querySelector("#export-status").textContent = "Recording retrieved. Save it or select and copy the JSON.";
    }
  } catch (error) {
    diagnosticStatus.textContent = error.message || "Could not record signals.";
    record.disabled = false;
  }
}
record.addEventListener("click", () => diagnostics(recording ? "stop" : "start"));
markAd.addEventListener("click", () => diagnostics("ad"));
markProgram.addEventListener("click", () => diagnostics("program"));
exportButton.addEventListener("click", () => diagnostics("export"));
document.querySelector('#inspect-metadata').addEventListener('click', async () => {
  const button = document.querySelector('#inspect-metadata');
  button.disabled = true;
  try {
    const target = await activeTarget();
    const results = await browser.scripting.executeScript({ target, files: ['metadata-probe.js'] });
    const payload = results[0]?.result;
    if (typeof payload !== 'string') throw new Error('Metadata probe did not return a response.');
    const result = JSON.parse(payload);
    if (!result.ok) throw new Error(result.error || 'Metadata inspection failed.');
    document.querySelector('#export-panel').hidden = false;
    document.querySelector('#recording-json').value = JSON.stringify(result.report, null, 2);
    document.querySelector('#export-status').textContent = 'Metadata snapshot ready. Click Save JSON file. Your commercial recording is unchanged.';
  } catch (error) {
    document.querySelector('#diagnostic-status').textContent = error.message || 'Could not inspect metadata.';
  } finally { button.disabled = false; }
});
refresh.addEventListener("click", () => diagnostics());
async function playerEvents(command) {
  const message = document.querySelector('#event-status');
  message.textContent = 'Checking player-event recorder…';
  try {
    const target = await activeTarget('directv.com');
    await browser.scripting.executeScript({ target, world: 'MAIN', files: ['player-events.js'] });
    const results = await browser.scripting.executeScript({ target, world: 'MAIN',
      func: (action) => globalThis.commercialBreakerPlayerEvents(action), args: [command] });
    const payload = results[0]?.result;
    if (typeof payload !== 'string') throw new Error('The page event recorder did not respond.');
    const result = JSON.parse(payload);
    if (!result.ok) throw new Error(result.error || 'Player-event test failed.');
    message.textContent = `${result.running ? 'Recording' : 'Stopped'} · ${result.count} entries · ${result.coverage.videojsPlayers || 0} exposed Video.js players · ${result.coverage.videoElements || 0} video elements.`;
    if (!result.coverage.videojsPlayers) message.textContent += ' DOM/media events only; internal player events may be inaccessible.';
    const globals = result.coverage.globals;
    if (globals) {
      message.textContent += ` Global names: ${globals.properties.map(({ name, type }) => `${name} (${type})`).join(', ') || 'none matched'}.`;
      if (globals.truncated) message.textContent += ' Global scan limited.';
      if (globals.failed) message.textContent += ' Global scan failed; results may be incomplete.';
      message.textContent += ' Names alone do not establish player access.';
    }
    if (result.report) {
      document.querySelector('#export-panel').hidden = false;
      document.querySelector('#recording-json').value = JSON.stringify(result.report, null, 2);
      document.querySelector('#export-status').textContent = 'Player events ready. Click Save JSON file.';
    }
  } catch (error) { message.textContent = error.message || 'Safari could not run the page-world event test.'; }
}
for (const [id, command] of [['event-start', 'start'], ['event-ad', 'ad'], ['event-program', 'program'], ['event-stop', 'stop'], ['event-export', 'export']]) {
  document.querySelector(`#${id}`).addEventListener('click', () => playerEvents(command));
}
document.querySelector('#screen-test').addEventListener('click', async () => {
  try {
    await browser.tabs.create({ url: browser.runtime.getURL('screen-test.html') });
  } catch (error) {
    document.querySelector('#frame-status').textContent = error.message || 'Could not open screen test.';
  }
});

document.querySelector('#test-frame').addEventListener('click', async () => {
  const button = document.querySelector('#test-frame');
  const message = document.querySelector('#frame-status');
  const preview = document.querySelector('#frame-preview');
  button.disabled = true;
  preview.hidden = true;
  message.textContent = 'Reading one video frame…';
  try {
    const target = await activeTarget();
    await browser.scripting.executeScript({ target, files: ['select-video.js'] });
    const results = await browser.scripting.executeScript({ target, files: ['frame-probe.js'] });
    const payload = results[0]?.result;
    if (typeof payload !== 'string') throw new Error('Frame probe did not respond.');
    const result = JSON.parse(payload);
    const labels = {
      'pixels-readable': 'Pixels readable. Does the image below match the TV right now?',
      'near-black': 'Frame is nearly black. This does not establish usable video access.',
      'no-frame': 'No local video frame is available.',
      'access-blocked': 'Safari blocked pixel readback. This method cannot read this video.'
    };
    message.textContent = labels[result.outcome] || result.error || 'Frame test failed.';
    message.textContent += ` AirPlay: ${result.wireless === true ? 'connected' : result.wireless === false ? 'not connected' : 'unknown'}.`;
    if (result.preview?.startsWith('data:image/png;base64,')) {
      preview.src = result.preview;
      preview.hidden = false;
    }
    document.querySelector('#export-panel').hidden = false;
    document.querySelector('#recording-json').value = JSON.stringify({ version: 2, probe: 'video-frame',
      entries: [{ at: new Date().toISOString(), kind: 'frame-test', ...result }] }, null, 2);
    document.querySelector('#export-status').textContent = 'Frame test ready to save. This includes the small preview image if available.';
  } catch (error) { message.textContent = error.message || 'Frame test failed.'; }
  finally { button.disabled = false; }
});

try {
  const last = localStorage.getItem('skybox.audio-test-status');
  if (last) document.querySelector('#audio-status').textContent = `Previous attempt: ${last}`;
} catch { /* Storage may be unavailable; the live result still works. */ }
async function audioTest(readOnly = false) {
  const button = document.querySelector(readOnly ? '#read-audio' : '#test-audio');
  const message = document.querySelector('#audio-status');
  button.disabled = true;
  message.textContent = readOnly ? 'Retrieving the page’s last audio result…' : 'Starting audio test. Keep this popup open…';
  let responseTimer;
  try {
    const request = async () => {
      const target = await activeTarget();
      if (!readOnly) {
        await browser.scripting.executeScript({ target, files: ['select-video.js'] });
        // Safari may omit results for injected files. The probe stores its result in the page.
        await browser.scripting.executeScript({ target, files: ['audio-probe.js'] });
      }
      return browser.scripting.executeScript({ target, func: () => {
        if (globalThis.commercialBreakerAudioProbePending) return JSON.stringify({ outcome: 'pending' });
        return typeof globalThis.commercialBreakerLastAudioProbeResult === 'string'
          ? globalThis.commercialBreakerLastAudioProbeResult : JSON.stringify({ outcome: 'not-tested' });
      } });
    };
    const results = await Promise.race([request(), new Promise((_, reject) => {
      responseTimer = setTimeout(() => reject(new Error('No response from the page within 8 seconds. Audio access is still unknown.')), 8000);
    })]);
    if (typeof results[0]?.result !== 'string') throw new Error('Audio probe did not respond.');
    const result = JSON.parse(results[0].result);
    const labels = {
      'pending': 'The page audio test is still running. Try Show last audio result again shortly.',
      'not-tested': 'No completed audio test on this page. Run the test first; a page refresh clears results.',
      'unsupported': 'This browser does not expose video captureStream().',
      'unsupported-analysis': 'Web Audio analysis is unavailable.',
      'nonzero-samples': 'Nonzero audio samples captured. This does not yet identify commercials.',
      'silent-or-inaccessible': 'Only silence measured: actual silence or inaccessible audio; inconclusive.',
      'no-audio-track': 'No captured audio track appeared within 3 seconds.',
      'context-not-running': 'Audio analysis could not start; no access conclusion.',
      'capture-failed': 'The browser rejected audio capture.',
      'analysis-error': 'Audio analysis failed.',
      'page-exit': 'Test stopped because the page was left.',
      'wrong-site': 'Open DIRECTV or Paramount+ first.'
    };
    message.textContent = labels[result.outcome] || 'Unknown audio test result.';
    if (result.measuredAt) message.textContent += ` Measured at ${new Date(result.measuredAt).toLocaleTimeString()}.`;
    if (result.errorName) message.textContent += ` ${result.errorName}.`;
    document.querySelector('#export-panel').hidden = false;
    document.querySelector('#recording-json').value = JSON.stringify({ version: 1,
      probe: 'audio-access', at: new Date().toISOString(), ...result }, null, 2);
    document.querySelector('#export-status').textContent = 'Audio measurements ready to save. No audio recording is included.';
  } catch (error) { message.textContent = error.message || 'Audio test failed.'; }
  finally {
    clearTimeout(responseTimer);
    button.disabled = false;
    try { localStorage.setItem('skybox.audio-test-status', `${new Date().toLocaleTimeString()} · ${message.textContent}`); }
    catch { /* Do not hide the live result when persistence is unavailable. */ }
  }
}
document.querySelector('#test-audio').addEventListener('click', () => audioTest());
document.querySelector('#read-audio').addEventListener('click', () => audioTest(true));
document.querySelector('#direct-audio').addEventListener('click', async () => {
  const message = document.querySelector('#audio-status');
  try {
    const target = await activeTarget('directv.com');
    await browser.scripting.executeScript({ target, files: ['select-video.js', 'direct-audio.js'] });
    message.textContent = 'Close this popup and click Start direct audio test in the panel on the DIRECTV page. Refresh DIRECTV if sound stops.';
  } catch (error) { message.textContent = error.message || 'Could not show the direct audio test.'; }
});

document.querySelector("#select-recording").addEventListener("click", () => {
  const field = document.querySelector("#recording-json");
  field.focus();
  field.select();
});
document.querySelector("#save-recording").addEventListener("click", async () => {
  const button = document.querySelector("#save-recording");
  const message = document.querySelector("#export-status");
  button.disabled = true;
  try {
    const result = await globalThis.commercialBreakerSaveRecording(browser, document.querySelector("#recording-json").value);
    message.textContent = result.method === 'page' ?
      "Opened a recording save tab. Click Download JSON there and keep it open until saved." :
      "Download requested. Check Safari’s Downloads list for completion.";
  } catch (error) {
    message.textContent = `Save failed: ${error.message}. The JSON remains above; select and copy it.`;
  } finally {
    button.disabled = false;
  }
});

const airplayButton = document.querySelector("#airplay");
const airplayMessage = document.querySelector("#airplay-status");
const airplayHistory = document.querySelector("#airplay-history");
const historyKey = "skybox.airplay-attempt";
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
    await browser.scripting.executeScript({ target, files: ["select-video.js"] });
    recordAirplayStep("Player selection loaded; adding page panel.");
    await browser.scripting.executeScript({ target, files: ["airplay-session.js"] });
    const results = await browser.scripting.executeScript({ target, func: () => ({
      ok: globalThis.commercialBreakerAirPlayPanel?.isConnected && globalThis.commercialBreakerAirPlayPanel.commercialBreakerVersion === '0.1.11',
      error: 'Refresh the player page or close the old AirPlay panel, then retry.'
    }) });
    if (!results[0]?.result?.ok) throw new Error(results[0]?.result?.error || "The page did not respond.");
    await browser.scripting.executeScript({ target, world: 'MAIN', files: ['airplay-source-trace.js', 'directv-airplay-recovery.js'] });
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
    if (globalThis.commercialBreakerIsRelayUrl(tab?.url || '')) {
      document.querySelector('#relay-controls').hidden = false;
      document.querySelector('#paramount-controls').hidden = true;
      document.querySelector('#airplay-controls').hidden = true;
      document.querySelector('#airplay-history').parentElement.hidden = true;
      await updateRelay();
      return;
    }
  } catch { /* Existing site controls still report their own access errors. */ }
  try {
    await activeTarget();
    document.querySelector("#airplay-controls").hidden = false;
    document.querySelector("#paramount-controls").hidden = false;
  } catch {
    document.querySelector("#airplay-controls").hidden = true;
  }
  update();
  diagnostics();
}
async function updateRelay(command = 'status') {
  const message = document.querySelector('#relay-status');
  const mute = document.querySelector('#relay-mute');
  const auto = document.querySelector('#relay-auto');
  mute.disabled = auto.disabled = true;
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!globalThis.commercialBreakerIsRelayUrl(tab?.url || '')) throw new Error('Open the Commercial Breaker relay player first.');
    const target = { tabId: tab.id };
    await browser.scripting.executeScript({ target, files: ['relay-target.js', 'relay-controls.js'] });
    const results = await browser.scripting.executeScript({
      target, func: (action) => globalThis.commercialBreakerRelayControl(action), args: [command]
    });
    const result = results[0]?.result;
    if (!result?.ok) throw new Error(result?.error || 'Relay controls did not respond.');
    message.textContent = result.message;
    if (result.paused) message.textContent += ' Playback is paused.';
    mute.textContent = result.muted ? 'Unmute player' : 'Mute player';
    auto.textContent = result.enabled ? 'Disable automatic mute' : 'Enable automatic mute';
    mute.disabled = auto.disabled = false;
  } catch (error) {
    message.textContent = error.message || 'Allow Commercial Breaker access to the relay page.';
  }
}
document.querySelector('#relay-mute').addEventListener('click', () => updateRelay('toggle-mute'));
document.querySelector('#relay-auto').addEventListener('click', () => updateRelay('toggle-auto'));
document.querySelector('#relay-refresh').addEventListener('click', () => updateRelay());
document.querySelector("#build-status").textContent = "v0.2.21 · Controls ready";
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

document.querySelector('#airplay-export').addEventListener('click', async () => {
  try {
    const target = await activeTarget(['directv.com', 'paramountplus.com']);
    const results = await browser.scripting.executeScript({ target, func: () =>
      globalThis.commercialBreakerExportAirPlayPlayback?.() || '' });
    const json = results[0]?.result;
    if (typeof json !== 'string' || !json) throw new Error('Open the updated AirPlay page panel first.');
    const trace = await browser.scripting.executeScript({ target, world: 'MAIN', func: () =>
      globalThis.commercialBreakerAirPlaySourceTrace?.export() || '' });
    const report = JSON.parse(json);
    report.sourceTrace = trace[0]?.result ? JSON.parse(trace[0].result) : { unavailable: true };
    document.querySelector('#recording-json').value = JSON.stringify(report);
    document.querySelector('#export-panel').hidden = false;
    document.querySelector('#export-status').textContent = 'AirPlay playback log ready. Click Save JSON file.';
  } catch (error) { airplayMessage.textContent = error.message || 'Could not retrieve playback log.'; }
});
