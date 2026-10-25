# AirPlay playback diagnostics (v0.2.18; panel v0.1.10)

Reload the extension, close the old page panel and add the new panel, then click
Try AirPlay to attach diagnostics to the selected video. No separate recording
button is required. Existing caption suppression and route behavior are unchanged.

Records timestamped waiting/stalled/playing/pause/seeking/load events, wireless
changes, text-track mode/list changes, caption-reset requests, and progress at
most once per five seconds of timeupdate events. Snapshots include finite media
time, buffered end, ready/network/error states and track kind/mode only. No stream
URLs, track labels, cues or audio are exported. Retains the latest 1,200 entries
in page memory; refresh/navigation loses them. Progress may be throttled by Safari
and receiver-side events may not be exposed to the sender.

After the pause, open the extension and click Export AirPlay playback log, then
Save JSON file in the existing export area. Export crosses Safari's injection
bridge as a JSON string. Closing the panel removes listeners but leaves its final
export available until another panel is created or the page leaves. This diagnoses
whether a delayed pause coincides with a route event or caption update; it does
not itself fix buffering. Native app remains v0.2.36.

# DIRECTV caption reset experiment (v0.2.17; page panel v0.1.9)

The DIRECTV panel requests captions/subtitles disabled immediately before opening
its AirPlay picker and again on wireless connection or metadata load while wireless.
It also sets Safari's legacy closed-caption visibility property to false when
available. Metadata and other track kinds are untouched. This is a best-effort
sender-side request: Apple TV may retain independent subtitle selection. The
history reports requests, not verified TV state. No periodic override is installed.
Closing with Restore settings and close restores the track modes originally seen.
Paramount behavior is unchanged.

Reload the temporary extension, close the old page panel, then use Show AirPlay
test on page to create v0.1.9. Use Try AirPlay and verify captions on the TV, including
a subsequent automatic return. Native app rebuild is unnecessary. Tests cover
repeated returns, metadata preservation, restoration and unsupported controls;
Nick reported on October 4 that the AirPlay subtitle issue appears resolved in
the live DIRECTV session. Longer-run and other-service behavior remain unverified.

# Commercial Breaker Safari extension

## Paramount session capture (v0.2.16)

1. Run the root **Start Paramount Extension Helper.command** launcher. Keep its
   Terminal open. This helper is separate from the original manual relay, so
   starting it does not stop existing TV playback.
2. Reload the temporary Safari extension from this folder. Confirm v0.2.16 and
   grant its requested Paramount, Google DAI, Irdeto and loopback access.
3. On the original Paramount tab, open Commercial Breaker, paste the helper's pairing code
   under Paramount TV setup, and click **Capture Paramount & open relay**.
4. Reload that Paramount tab and resume playback. Capture survives the popup
   closing. It waits up to two minutes for this tab's successful variant playlist
   and authorized key request, then asks the helper to validate both.
5. The relay opens in a new tab. Pause the original player; click Play then
   Choose AirPlay. Leave the relay's legacy automatic mute off when using Gemini.

The background listener uses onSendHeaders/onCompleted and only captures while
explicitly armed. Authorization is accepted only for the exact Irdeto key endpoint
and a successful response in the armed tab. Credentials and pairing code are
memory-only; status responses never contain them. A page navigation away cancels
capture. Safari may discard an idle background page; if capture disappears, arm
again. Missing headers and cached key requests require a live Safari check.

The helper accepts authenticated JSON on 127.0.0.1:8766 only, validates Host,
rejects oversized input, and grants no webpage CORS access. The random code
pairs the extension to this helper run. It starts one LAN relay on an available
port; repeated setup cannot silently replace playback. Restart the helper for a
new session. Closing it also stops its relay. No native extension packaging is
required in this iteration; a fully integrated native host remains future work.

Validation: mocked extension request flow plus loopback HTTP tests cover
cross-tab rejection, failed key requests, exact hosts/paths, successful handoff,
pairing, rebinding protection, bounds and redacted failures. The existing relay
suite also passes. Actual Safari header exposure and local fetch permissions
remain a live verification step.


## AirPlay routing experiment (v0.2.15; page panel v0.1.8)

This tests a possible TV → Mac → TV round trip. It does not detect commercials,
capture a microphone, or coordinate native tap muting. Sound may move to the Mac.

1. Reload the temporary extension and confirm popup v0.2.15. Close any older
   page panel with **Restore settings and close** before adding the new one.
2. Use **Show AirPlay test on page**, close the popup, and use **Try AirPlay**
   in the v0.1.8 panel to select the Apple TV. Wait for working TV playback.
3. Click **Test return route (15 seconds)**. Keep the Safari tab foreground.
   The script sets `disableremoteplayback` for five seconds, then removes it
   and waits ten seconds. It never opens a picker during that test.
4. Watch whether playback moves to the Mac and then returns to the TV without
   another click. Also inspect the final message and retained connection history.
   Local/wireless events alone still need confirmation of actual picture/sound.
5. If playback remains local, use **Try AirPlay** to reconnect manually.

The existing attribute observer pauses its corrections during this experiment.
Closing the panel, player replacement, or page exit cancels pending test timers
and restores the changed attribute. Browser background throttling can delay the
nominal timeouts. Reinjection will not duplicate an existing current panel.
The most recent result is retained as a JSON string in
`globalThis.commercialBreakerAirPlayRouteResult` until page refresh, with no stream URLs.

Apple documents a [picker-based selection API](https://developer.apple.com/documentation/webkitjs/adding_an_airplay_button_to_your_safari_media_controls).
WebKit's [JavaScript interface](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/html/HTMLMediaElement.idl)
exposes wireless state as read-only; its internal target-selection methods are
not exposed there. Re-enabling remote playback is not a documented reconnect
command. This experiment tests the actual behavior rather than assuming that
Safari will retain and reuse the route. Live behavior remains unverified.

## Direct Web Audio test (v0.2.14)

Show direct Web Audio test on page adds a panel to stream.directv.com. Close the popup and click Start direct audio test on the page to supply Safari's audio gesture. Use local playback with AirPlay disconnected. It creates a MediaElementAudioSourceNode and routes it through an analyser to the audio destination, without changing the video's mute, volume, source, or time. This changes the audio route and may silence restricted content. Refresh DIRECTV to restore the original route if needed.

Sampling stops after three seconds; the connected graph deliberately remains to preserve playback and is reused on repeat tests. Closing it immediately would silence the bound media element. Page exit closes the context. A five-second resume deadline avoids waiting indefinitely before binding. Results are shown in the page and recoverable with Show last audio result. Nonzero samples prove only sample access; silence does not distinguish actual silence, cross-origin restrictions, or protected media. No microphone, raw recording, or external upload is involved. Live Safari behavior is unverified until Nick runs this test.

## Safari audio result bridge (v0.2.13)

Nick reported “Audio probe did not respond” in local Safari playback. This means the popup received no string result, not that capture itself failed. The popup now ignores the injected file's return value and uses an explicit synchronous `executeScript({func})` call to retrieve the stored result or pending/not-tested state. This path also powers Show last audio result. A regression test simulates an undefined file-injection result and verifies recovery through the function call. Live Safari verification remains required.

## Audio result visibility (v0.2.12)

The audio button and status now appear at the top of the popup. A completed attempt's timestamped status survives closing/reopening the popup, labeled Previous attempt. If the popup closes mid-test, **Show last audio result** retrieves the timestamped result retained in the page, without starting another capture. Page refresh clears that retained result. Retrieval distinguishes pending capture from no saved result. The extension reports an explicit unknown result if the page bridge has not responded within eight seconds; this timeout does not cancel an in-flight injection or establish whether audio is accessible. Capture cleanup remains in the page probe. The static loading version now matches the script version to help diagnose cached popup resources.

## Silent audio access test (v0.2.11)

With DIRECTV or Paramount+ playing, click **Test silent audio access (3 seconds)** and keep the popup open. The probe uses the selected video's `captureStream()` only if exposed, analyzes a separate captured audio stream through a zero-gain output, and exports aggregate peak/RMS measurements and capture state. No microphone, raw audio recording, network upload, source changes, mute changes, or volume changes are used. It does not use `createMediaElementSource`, which would reroute the original player audio.

Unsupported capture, rejected capture, missing audio tracks, suspended analysis, and silent samples are distinct outcomes. Nonzero samples establish only that samples were observed; they do not classify ads or prove audio matches the broadcast. Silence is inconclusive. Track access remains subject to browser and content restrictions. The three-second deadline uses browser timers and can be delayed by background throttling. Captured tracks, nodes and context are released on completion, error, or page exit; concurrent tests share one capture. Closing the popup can lose the displayed result, but cleanup runs in the page.

First live test: Safari playing locally, AirPlay disconnected (Nick's current setup). If samples are readable, repeat with the player muted to verify silent observation, then separately with AirPlay. Do not infer Safari/AirPlay support from synthetic tests. Capture behavior reference: https://www.w3.org/TR/mediacapture-fromelement/ .

## Player global discovery (v0.2.10)

Start player-event test now takes a one-time inventory of own global property names matching Quickplay or FreeWheel (case insensitive). It inspects at most 5,000 names and reports at most 30 matches, each at most 160 characters. Only names and descriptor value types are exported; accessors are labeled without invoking them, and object contents are never traversed. Limit and failure flags distinguish partial scans from no matches. Browser-generated named DOM properties may appear as objects: a matching name does not prove an SDK instance or an accessible event bus.

For this test, start, stop, and export immediately; no commercial transition is needed. Save JSON through the existing export workflow. The popup also displays matches directly. Save any old recording before upgrading: replacement of the old injected recorder stops its listeners and starts with fresh state. This discovery does not add Quickplay/FreeWheel subscriptions or enable automatic muting.

## Player-event test (v0.2.9)

Start player-event test requests injection into the page MAIN world and passively subscribes to a fixed list of DOM ad-event names, native video lifecycle events, and documented Video.js ad events if existing instances are exposed through videojs.getPlayers(). It does not initialize a player, monkey-patch event dispatch, capture event payloads, or alter playback. Reference for Video.js events: https://videojs.github.io/videojs-contrib-ads/integrator/api.html. DIRECTV's use of this registry has not been established.

Check the reported source coverage first. Zero exposed Video.js players means private player buses remain inaccessible; no observed DOM events is inconclusive. If a useful source is attached, mark the commercial and football return using the dedicated event-test buttons, stop, export player events, then Save JSON file through the existing fallback. Recording continues with the popup closed, caps at 600 entries, stops after 15 minutes or page exit, and detaches listeners on stop. Discovery handles replacement players with a maximum of 64 attached targets. In-page data is lost on reload. Page-world observations are untrusted diagnostic data, never automatic mute commands.

Synthetic tests cover player event transitions, marker recording, no payload collection, reinjection, cleanup, bounds, absent registry, and MAIN-world popup routing. Safari's MAIN-world support and DIRECTV's actual event coverage require the live test; unsupported execution is reported as an error rather than silently falling back to an isolated world.

## Window capture test (v0.2.8)

Open screen capture test launches a persistent extension page. Move that tab into a separate Safari window so selecting the DIRECTV window does not capture the test itself. Click Choose DIRECTV window, then select it in Safari's native picker. getDisplayMedia is invoked directly from that page button's user gesture, with audio disabled. The test stays local; no upload or remote peer is involved.

Keep native AirPlay connected initially. Inspect the preview and click Capture frame and stop. Capture ends after that click (including pixel-read failure), Stop sharing, page exit, or a 30-second timer. The timer depends on browser scheduling. A late picker result after page exit is stopped immediately. A PNG download is available after successful readback; it includes the selected window, so inspect it before sharing. Browser chrome surrounding a black video area is not proof the game was captured. An AirPlay placeholder also does not provide footage. If the API is unavailable on the extension page, report that error; live Safari compatibility is not assumed.

Reference: https://webkit.org/blog/13399/webkit-features-in-safari-16-1/ documents Safari window capture through a user-selected getDisplayMedia prompt. The DIRECTV content result remains unverified.

## Local video-frame read test (v0.2.7)

While native AirPlay remains active, click Test video frame. The probe selects a unique visible player and draws one frame to an unattached, downscaled canvas (320 pixels wide; height capped at 320). It attempts pixel readback and reports readable pixels, nearly black output, unavailable local frame, or access blocked. It does not change playback, source, cross-origin attributes, track modes, DRM, or the AirPlay target.

A readable preview is not proof of current live video: compare it with the TV, then repeat after the scene changes. A black frame could be real black content, unavailable decoding, or protection; no specific cause is inferred. Save JSON file exports diagnostics plus the small image if available, through the existing local save workflow. Existing commercial recordings remain intact in tab memory. This is an access experiment, not commercial detection. Safari/AirPlay behavior requires Nick's live test.

## DIRECTV PRIV field preview (v0.2.6)

A confirmed-commercial snapshot still showed PRIV/info (249 characters) and one binary byte, without plain JSON or recognized marker strings. The metadata probe now includes a maximum 512-character preview only of PRIV's observed info field, plus the data value only when it is exactly one byte. It redacts URL, bearer, JWT, and common named credential patterns before returning the preview. Pattern redaction is not a guarantee that every sensitive identifier is removed; keep these diagnostic exports local. Other arbitrary payload strings remain hidden and captions are not inspected.

Capture one snapshot during football and one during a commercial with the same version. No recording is needed. The goal is to identify the field's encoding and whether it changes meaning across a break; PRIV presence alone is not a mute signal.

## Metadata shape snapshot (v0.2.4)

On a DIRECTV or Paramount+ tab, Inspect metadata now captures one read-only snapshot of active metadata cues. Click Save JSON file afterward and use the save tab's Download JSON link. No new recording or commercial marker is needed for this first format inspection. It does not change track modes, playback, mute, or the existing recorder; exporting a commercial recording again replaces the snapshot in the popup's save field.

The probe records cue times plus bounded payload structure, binary lengths, primitive types, and a small allowlist of protocol/event labels. Arbitrary strings and field names are redacted, number values inside payloads are omitted, and caption/subtitle cues are not read. Cycles, nested values, and inaccessible cue properties are handled without returning raw objects through Safari's native bridge. This is format discovery, not ad classification; redaction can hide meaningful values, which should be inspected selectively only after their schema is understood.

Implementation reference: WebKit DataCue support at https://bugs.webkit.org/show_bug.cgi?id=131799. Actual DIRECTV cue format remains to be established from the snapshot.

## Download API fallback (v0.2.3)

Safari reported no downloads API despite the manifest requesting downloads permission. Save JSON file now falls back to a persistent extension tab with an ordinary Download JSON link when the API is missing or rejects the request. A single extension-local recovery copy is retained until replaced by another fallback export or cleared using that page's button. The Blob URL belongs to the tab, so closing the popup does not revoke it. Keep the save tab open until the file finishes saving. If needed, Open the JSON provides a separate tab for Safari File → Save As.

For an existing recording, first close and reopen the popup and check for v0.2.3, then Export recording and Save JSON file. Do not reinstall the extension, reload the stream, or start a new recording while trying to recover a pending recording. Safari may cache old extension resources; if the new version is not visible, preserve the existing recording before reloading the extension. The fallback has automated coverage (51 JavaScript tests pass); actual Safari saving remains to be verified. The current DIRECTV session is live football, not pre-show.

## Safari export crash workaround (v0.2.2)

The September 20 Safari crash report shows an abort in `_writeJSONNumber` while WebKit converts an `executeScript` result through `toInjectionResultParameters`. This occurred on Export recording, before the download step. Non-finite recorded numbers are the suspected trigger; the original recording was not recovered, so the exact field is unconfirmed. Cue times were previously returned without finite-number checks.

The recorder now normalizes non-finite media/cue numbers to null. The popup's injected diagnostics call serializes its result with JavaScript JSON.stringify before returning across Safari's native bridge, then parses the string in the popup. This also sanitizes reports from an older recorder already in a tab. There are 49 passing JavaScript tests, including non-finite cue samples and the actual export callback with a legacy report. These tests do not reproduce Safari's native crash; live verification is pending.

Reload the temporary extension and confirm v0.2.2. First record only 10 seconds, stop, export, and save to Downloads. Once that succeeds, record a full commercial break. Recordings still live in tab memory until exported; a browser crash or page reload can lose them.

## DIRECTV pre-show recording (v0.2.1)

DIRECTV now exposes manual mute/unmute and Commercial signals in the popup alongside native AirPlay. Reload the temporary extension and verify v0.2.1. Start a recording during programming, mark commercial started when the TV changes to a full-screen break, and mark broadcast returned when programming resumes. Stop and export the recording, then save the JSON before refreshing the page. Recording lasts at most 15 minutes and continues with the popup closed while Safari schedules the page.

This uses the existing bounded DOM and video-state recorder; it does not automatically classify or mute DIRECTV commercials. Exported reports identify the service without collecting stream URLs or credentials. If an older injected recorder rejects DIRECTV after the extension reload, refresh the DIRECTV page before starting a new recording, then reconnect native AirPlay. Save any pending recording first.

Verification: 47 JavaScript behavior tests passed, including DIRECTV popup routing, recording markers/service identity, manual mute preserving playback, and lookalike-domain rejection. Actual DIRECTV signal coverage requires a live break recording. Older sections below document previous versions and their narrower scope.

## Relay integration (v0.2.0)

The extension now controls the local HLS relay player: manual mute/unmute and an opt-in automatic commercial-mute toggle. On the relay tab, Commercial Breaker checks its private-LAN session URL and page marker, then operates the existing page controller. No additional host permissions or credential capture are used. DIRECTV/Paramount page controls remain separate; automatic commercial mute is currently supported only on the relay player.

Restart the updated relay, open its new session URL in Safari, reload this temporary extension, and confirm **v0.2.0** in the popup. Enable automatic mode after confirming manual mute reaches the TV. See [the relay guide](../Experiments/hls-relay.md#extension-and-automatic-commercial-mute-v020) for the full real-break test. Automated behavior is implemented; its alignment and TV audio effects still need live verification.

Automatic mode follows HLS cue markers at the video's playback timestamp. It restores only mutes it applied. Unknown/stale timing releases its mute; manual audio changes turn automatic mode off. Monitoring remains in the player when the popup closes, and is off after a page refresh. Safari background suspension can delay transitions.

Part of the existing Commercial Breaker project. A dependency-free Manifest V3 prototype for manually muting Paramount+ during Safari extended-desktop AirPlay playback.

## Status

Manual mute/unmute, active-tab injection, and player selection are implemented. Local verification uses JavaScript syntax checks, manifest JSON validation, and Node behavior tests. Nick verified manual mute/unmute against Paramount+ in Safari while extending the desktop to Apple TV. Automatic commercial detection is not implemented.

## Player selection

The extension chooses the unique visible playing video. If no visible videos are playing, it accepts exactly one visible video. Missing or ambiguous players produce an error without muting anything. A hidden playing preview does not displace a visible paused player.

## Local checks

```sh
node --test Tests/safari/*.test.cjs
node --check SafariExtension/popup.js
python3 -m json.tool SafariExtension/manifest.json > /dev/null
```

Tests execute the actual selection and player scripts against a simulated DOM. They cover inspection versus mutation, mute/unmute preserving playback and volume, hidden previews, paused fallback, ambiguous players, offscreen players, and navigation to an unsupported hostname. They do not simulate Safari's extension permission system or Paramount+'s player internals.

## Load in Safari

1. In Safari Settings, enable developer features under Advanced.
2. In the Developer settings tab, use the temporary-extension loading control and choose this `SafariExtension` directory (the directory containing manifest.json).
3. Open Paramount+, play the live stream, and open Commercial Breaker from Safari's toolbar. Grant page access if Safari asks.
4. With extended-desktop AirPlay still active, click Mute player. Verify that TV audio stops and video continues. Click Unmute player and verify audio returns.
5. Also check a Paramount+ page without a video and a different website. They should display an error rather than act on another tab.
6. Reload the Paramount+ tab and verify controls still work. Change mute using Paramount+'s own control, then use Check again to refresh the popup state.

Temporary extensions expire after 24 hours or when Safari quits. See Apple's guide: https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension

## Scope

Uses activeTab, scripting, and downloads permissions; no persistent site permissions, background worker, remote requests, credentials, telemetry, or video capture. The popup checks the Paramount+ HTTPS hostname before injecting code. It operates on light-DOM video elements in the top frame. Cross-origin iframes, shadow-root players, and site code that overrides muted changes need investigation if encountered. The visibility heuristic checks geometry and the video's computed style; it does not prove the element is unobscured.

The extension changes only `video.muted`, retaining volume, playback position, and play/pause state. Reported state is the DOM state at click time, not a measurement of sound at the television. Zero player volume requires adjustment in Paramount+.

## Record commercial signals

Reload the temporary extension in Safari's Developer settings (remove and add the same folder again if no reload control is available). Close and reopen its popup. The updated popup includes Commercial signals. If updating removes page access, grant it again on Paramount+.

1. Start recording while the broadcast is playing normally. Close the popup; sampling continues in the page.
2. At the next commercial, reopen Commercial Breaker and click Mark commercial started.
3. When the broadcast returns, click Mark broadcast returned.
4. Click Stop recording, then Export recording → Save JSON file. Download before refreshing or closing the Paramount+ tab, because recordings live only in that tab's memory.
5. Supply the downloaded commercial-breaker-signals JSON file for analysis. A second complete break will help distinguish reliable signals from coincidental changes.

The recorder samples once per second while browser scheduling permits. It stops at the first tick after 15 minutes and retains at most 1,200 entries. Starting a new recording clears the previous one. Reopening the popup does not restart the timer. Manual marks refer to when you click, so allow for human reaction time and AirPlay delay.

Samples include playback state and timing, text-track cue timings (not caption text), and bounded ad-related class/id/ARIA-label candidates from the top-frame DOM. Each sample scans at most 5,000 attributed elements and retains up to 40 matching candidates. No network interception, stream URLs, cookies, account storage, screenshots, or full-page HTML are collected. Some candidate labels can still contain page text; inspect the exported file before sharing it elsewhere.

These are candidate signals, not commercial classifications. Hidden markers can remain present during programming; server-inserted ads may expose no DOM marker at all. A lack of matches is inconclusive. The recorder never changes mute or playback state. Real break transitions and export through Safari still require live verification.

## Export recovery (0.1.1)

The first export implementation used an anchor pointing to a blob URL created in the extension popup. Safari reported “failed to open page”; that path is replaced with an explicit downloads API request using a data URL. Export first displays the complete JSON in a readonly field, so a failed save does not hide the report. Select JSON allows manual copying without clipboard permissions. Downloads permission is needed for Save JSON file; requesting a download is not proof it completed.

For an existing unsaved recording, close and reopen the popup first to check whether the changed resources are picked up. Do not remove/reinstall the extension, quit Safari, reload the Paramount+ tab, or start another recording before recovering the report: any of these may discard the in-memory data. Safari download behavior for the new export path still needs device verification. Automated tests cover JSON encoding, missing permission, empty recordings, and rejected downloads.

## Native AirPlay for DIRECTV and Paramount+ (0.1.3)

On a DIRECTV or Paramount+ HTTPS tab, the popup offers Show AirPlay test on page. Paramount+ also retains its mute and recording controls. Nick verified DIRECTV native AirPlay playback and muting; Paramount+ native AirPlay remains to be verified. It injects a small panel in the top document; exit video fullscreen to see it. Disable Mac Screen Mirroring/extended desktop and play the selected service locally first. Then click Try AirPlay in the page panel. This direct click calls Safari's `webkitShowPlaybackTargetPicker()` synchronously with user activation.

The experiment temporarily removes `disableremoteplayback` and `x-webkit-wirelessvideoplaybackdisabled`, and sets `x-webkit-airplay=allow` on the selected video. It reports whether those disabling attributes were found and whether the source uses a blob URL, without recording or displaying the URL. Restore settings and close restores the original attributes and removes its event listener/panel. Version 0.1.7 watches for site attribute resets and player removal; see below. A missing picker API, ambiguous video selection, or inaccessible iframe is a failed test, not proof AirPlay is impossible.

No stream replacement, media-key changes, video reload, or automatic playback command is performed. A successful picker request or reported wireless target does not establish video/audio playback on the TV. MSE players may need a separate AirPlay-compatible source: https://webkit.org/blog/15036/how-to-use-media-source-extensions-with-airplay/

Eighteen automated tests pass, including direct-click gating, original attribute restoration, duplicate panel prevention, unsupported picker handling, and site restriction. The automated tests cover both supported domains, but do not replace live playback verification on Paramount+.

## Popup troubleshooting (0.1.4)

The popup header shows `v0.1.4 · Controls ready` only after event handlers have been registered. The AirPlay action immediately displays `Adding the AirPlay button to this page…` before awaiting injection. If clicking produces no text change, verify the loaded build before attributing the failure to the video player. Twenty automated tests pass, including popup routing on Paramount+ and visible injection errors. These tests do not reproduce Safari extension resource caching.

### Persistent AirPlay feedback (0.1.5)

Last AirPlay attempt records timestamped progress and errors in extension-local storage (at most 12 lines, no page URLs or video data). Reopening the popup displays this history even if its transient status was reset. This helps distinguish popup recreation from an injection error or a panel hidden by the webpage. A fresh attempt replaces the previous history. Twenty-one tests pass, including history retention across popup instances. The root cause of Paramount+'s reported flashing feedback is not yet established.

### Stale page script correction (0.1.6)

The live popup log returned `Open the DIRECTV player first.` on Paramount+. That exact message exists only in the older DIRECTV-only script, not the current dual-service source. The injected script is now named `airplay-panel.js` and all references use the new path so Safari requests a fresh resource. The popup identifies itself as v0.1.6. Both supported hostnames and popup injection are covered by the existing tests; live Paramount+ playback still needs verification.


### Handoff investigation (0.1.7)

Paramount+ opens Safari's native picker and wakes the selected Apple TV, but Nick reports that the AirPlay indicator appears briefly and disappears without playback transferring. This is not yet a verified working Paramount+ handoff.

The panel now observes the selected video and reapplies AirPlay attributes if the site resets them. It stops after ten corrections per selected element to avoid an endless conflict. Closing disconnects observers and event listeners before restoring the original attributes. Player removal is reported and requires another click to select the new player; the extension does not automatically change the playback target.

A selectable history retains the last 40 messages while the panel remains open, including wireless transitions, availability, media error codes, source changes, and player removal. Source reporting contains only source kind and count of network source alternatives, never source URLs or error messages from the media service. A blob source with no exposed network alternative is a diagnostic clue, not proof of the cause. The extension cannot synthesize a compatible AirPlay stream by changing attributes.

To test:
1. Close the existing page panel using **Restore settings and close**.
2. Reload the temporary extension in Safari's Developer settings. Verify **v0.1.7 · Controls ready** in the popup. Save any pending recording before reinstalling or refreshing the page.
3. Turn off Mac Screen Mirroring; play Paramount+ locally. Click **Show AirPlay test on page**, close the popup, then **Try AirPlay → Living Room**.
4. Leave the page panel open. If the handoff drops, select and copy the connection history from its text box. Both connect and disconnect events remain visible there.

The injected resource is now `airplay-session.js` to avoid the previously observed stale resource issue. An existing older panel must be closed before this version can be injected. Twenty-six simulated-DOM behavior tests pass; they cover reset handling, bounded corrections, event history, source privacy, replacement detection, cleanup, and popup routing. They do not validate real Safari media transport or establish why this specific stream fails.
