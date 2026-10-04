# October 4: delayed AirPlay reload and return classification

Native app 0.2.41, extension 0.2.19, page panel 0.1.11.

The supplied DIRECTV exports show source resets about 13–17 seconds after
several wireless connections. Emptied/loadstart and track removal follow.
The existing observer cannot identify the caller. Repeated stalled events also
occur during normally advancing playback, so those alone are not failures.
The 19:29:43Z export still lacks sourceTrace. At 19:29:15.665Z it connects,
then resets at 19:29:30.795Z. Another reported seek remains pending from
19:21:10 to 19:26:55; remote currentTime may be stale, not physical TV position.

## Source tracing

Reload the temporary Safari extension, close the previous page panel, and add
its replacement through the extension popup. The panel must show 0.1.11.
MAIN-world tracing starts when the panel is added. Export AirPlay playback log,
then Save JSON file, includes sourceTrace alongside playback events.

Trace covers JavaScript load(), src/srcObject setters and src attribute
writes/removals on videos and their source elements. It preserves original
receivers, arguments, return values and exceptions. It keeps 600 events, stops
after one hour, panel close or page exit, and restores hooks only if still owned.
Callers contain origin, script ID and line/column; raw URL paths/queries and
arguments are not exported. Script IDs are session-local (up to 128).
Cached methods, browser-internal operations, other frames/worlds and other DOM
mutation APIs can bypass tracing. Empty traces do not prove no reload occurred.
The tracing has unit coverage. The later 19:45:11Z capture verified a live
Safari src-setter trace; see the investigation below.

## DIRECTV caller investigation, 19:45 capture

Input: `skybox-signals-2026-10-04T19-45-17-428Z.json`, exported at
19:45:11.191Z. Nick confirmed the video-and-audio interruption, but did not
confirm an earlier audio-only dropout in this particular capture. All times
below are UTC (subtract five hours for local time).

- 19:44:48.426: wireless connection confirmed.
- 19:44:50.411: currentTime 3772.417, bufferedEnd 3791.788.
- 19:44:54.887: currentTime 3772.713, bufferedEnd 3659.656.
- 19:45:00.149: currentTime still 3772.713, bufferedEnd 3665.662.
- 19:45:02.456: traced `HTMLMediaElement.src=` from DIRECTV JavaScript.
- 19:45:02.457: source reset; wireless false at .460, true again at .567.
- 19:45:03.095: seeking at 3638.652; the last sample at 19:45:09.187
  still reports that position. This does not independently establish TV output.

Read-only inspection of the loaded public scripts matched trace script 1,
line 1, column 2118601 to
`/att-purern.4534198552626af3f2c1.bundle.js`. The Safari player wrapper's
`prepare()` assigns `this.videoElement_.src = t.contentUrl` in a Promise
callback. Trace script 2, line 3, column 17739 matches New Relic's `nrWrapper`
in `/thirdParty/newrelic-sdk.96c7caad89bd79390216.js`. The asynchronous
boundary means this stack does not identify the upstream error that requested
preparation. Script 3 was not mapped.

The active React player configuration, read without invoking player controls,
has bufferTimeoutSeconds=10, networkRequestTimeout=8000, networkRetries=2,
maxRetuneAttempts=2, and retuneableErrorCodes including 1502. Retune-on-error
and fallback-on-error are enabled; vstbStallDetectionEnabled is false.
These are application configuration values, not a snapshot of the private
controller's timer state.

The matching bundle implements the following recovery path:

1. The controller creates a polling buffer timer when enableBufferTimer is
   enabled (SDK default true). Its buffered test examines the range containing
   currentTime, or the next future range, and requires more than one second of
   playable buffer. Ended content is exempt. This timer has no wireless-target
   condition.
2. If the timer finds no playable buffer, it waits the configured timeout,
   with timeupdate/canplaythrough/ended listeners that reschedule the check.
   At expiry it checks the buffer again, then emits TIMEOUT (1502) if necessary.
3. The retuner subscribes to buffer-timer and player errors. A permitted error
   invokes the preparation callback again, reaching the traced src assignment.

This is consistent with the reported buffer ending behind currentTime after
the AirPlay handoff and a reload roughly 14 seconds after connection. It is a
strong candidate, not proof of the specific trigger: the capture contains no
internal retune/error event, full buffered ranges, or timer state. A player
error on another allowed code can also invoke preparation. The separately
disabled stall detector uses pause/resume or seeks; it is not the same as the
buffer timeout mechanism.

The native automatic log records the TV handoff at 19:44:46 and confirmation
at 19:44:48, with no additional automatic routing command around 19:45:02.
No playback controls, timeout settings, or recovery behavior were changed
during this investigation. Next discriminating evidence: the internal retune
event's root error code (1502 versus another allowed error).

## Opt-in recovery experiment

`Tools/directv-airplay-recovery.js` was activated in the current DIRECTV page at
19:59:44Z. Live checks confirmed controller attachment and inclusion under
`sourceTrace.recoveryExperiment` in the source-trace exporter. The source tracer
was absent at initial installation and was installed alongside the experiment.
No page reload, native app restart, or playback command was needed.

The script locates the observed React hook's bridge/QuickPlayPlayer controller,
validates the active polling timer's shape and native 10-second setting, and
wraps its timeout callback. Only when that callback reaches its no-playable-buffer
condition while wireless does it defer the native check once by 20 seconds.
It leaves the native timeout configuration and other error handling unchanged.
At the end of the grace period, the original callback runs and can emit 1502
and trigger the normal retune. Native progress handlers can cancel the deferred
callback. An already scheduled callback from before attachment can run unchanged
once; installation does not restart the timer.

On wireless disconnect, pending grace is cancelled and ordinary checks restart
with the native 10-second window. Controller replacement detaches the old
observer and attempts attachment to a supported replacement. The experiment
stops after an hour, page exit, or the panel's restore/close event. Manual stop:
`skyboxDirectvRecovery.stop()` in the MAIN world. Cleanup restores the original
callback if still owned and restarts normal checks if grace was pending.
To reapply after page navigation, explicitly inject source tracing followed by
the experiment; this is not an automatically installed extension feature.

The bounded diagnostic records timeout conditions, grace expiry, numeric
controller/root error codes, wireless state, currentTime and up to eight buffered
ranges. It exports no error messages, source URLs, credentials or media data.
Eight focused tests cover grace timing, cancellation, restoration, unsupported
controllers, reinjection, controller destruction, expiry and error redaction.
Activation is verified; whether it prevents the TV interruption remains untested.

### 20:02 timeout confirmed; callback receiver correction

The supplied 20:02:30 download was a video-frame test (pixel readback blocked),
so the running page diagnostic was read directly. Evidence is saved in
`directv-recovery-2026-10-04T20-02.json`:

- 20:02:01.045: AirPlay connects.
- 20:02:14.418: controller retune 1562 with root error 1502.
- 20:02:14.419: native buffer timer emits 1502.
- 20:02:14.420: traced video src assignment.
- 20:02:14.425: wireless false; true again at .512.

This confirms the buffer timeout triggered this reload. The grace period did
not run: the first wrapper incorrectly required `this === timer`, but native
setTimeout invokes the callback without that receiver. The original callback
is an arrow function with a captured timer, so that guard was unnecessary.
The fixture had incorrectly bound the receiver; it now models the native
unbound scheduling and arrow callback. A regression test verifies the full
10-second native wait plus 20-second grace with browser-style invocation.
All nine focused tests passed. The corrected diagnostic was reapplied and
verified attached/exportable at 20:05:08.664Z. No playback restart was performed;
live effectiveness of the corrected grace period still awaits another timeout.

### 20:25 capture: grace ran, timeout still caused a reload

`skybox-signals-2026-10-04T20-25-34-959Z.json` (exported 20:25:29.081Z)
includes the corrected experiment and confirms its live execution:

- 20:24:38.837: AirPlay connects.
- 20:24:55.482: native timeout condition reached; 20-second grace begins.
  currentTime=3741.405; buffered range=[3611.630,3677.674].
- 20:25:15.486: grace expires; currentTime unchanged, buffer now
  [3616.750,3695.692], still entirely behind the reported playhead.
- 20:25:15.508: retune 1562, root error 1502.
- 20:25:15.509: native buffer error and traced source assignment.
- 20:25:15.516: wireless false; true again at .594.

The grace delayed recovery as intended but did not resolve the reported buffer
condition. This does not establish whether the TV was playing normally during
the extra 20 seconds; that observation is needed to distinguish an inappropriate
local-buffer recovery from a genuine remote playback failure. No further timeout
increase or permanent suppression is justified by this capture alone.

### 20:29: observation-only follow-up

Nick was unsure whether the TV was frozen during the grace period. At his
request the live experiment was stopped and the extra delay removed. The
current `Tools/directv-airplay-recovery.js` is now observation-only: no callback
replacement, timeout configuration changes, or recovery rescheduling. Four
focused tests verify native timing, cleanup, replacement and bounded/redacted
logging. Earlier grace-period descriptions above are historical.

The observer was attached and verified at 20:29:10.602Z with mode=observe-only,
graceSeconds=0, and export integration active. It samples buffered and seekable
ranges, seeking state, and getStartDate when available once per second for
45 seconds after attachment, route/metadata/empty/seek transitions. The ring
holds 600 events; the existing one-hour/page-close cleanup remains.

Initial live samples reported currentTime=3638.648, seeking=true, and a buffered
range beginning at 3836.404 (later 3842.420), entirely ahead of the reported
playhead. The stream start date was unavailable. That playhead matches the
pending seek at 20:25:16.050 in the supplied log. This is a reported unresolved
seek, not proof of the physical TV state. The SDK buffer timer accepts a future
buffer range with more than one second of content, which can explain why it
does not necessarily time out in this different condition. The next handoff
samples are needed to localize the earlier backward buffer transition.

### 20:43 guarded handoff seek

The 20:40 export shows buffer and seekable ranges moving backward before the
traced source resets at 20:37:39 and 20:39:50. Both resets follow timeout 1502.
At Nick's request, the current diagnostic adds a single guarded seek per wireless
connection, with a global 60-second correction cooldown. It only acts within
60 seconds of connection/attachment on live, unpaused, non-seeking media with
readyState >= 3. Two successive samples must show the playhead stationary within
0.25 seconds and more than five seconds beyond both range ends. The target is
two seconds inside the latest buffered/seekable overlap of at least four seconds.
No overlap means no action. Failed writes consume the attempt; native recovery
is unchanged. Eight seconds afterward the observer records whether reported
playback advanced; this is not direct evidence of TV output.

Seven focused tests passed, including browser timer behavior, cleanup, one-shot
correction, advancing playback, expired windows and paused/seeking/local/VOD
exclusions. Activated at 20:43:47.245Z; live attachment and export integration
verified. Playback was already advancing during verification, so no correction
was needed. Effectiveness awaits a matching handoff failure. This remains a
temporary page injection, removed by refresh, close, or its one-hour expiry.

### 20:53 capture: first successful guarded correction

Nick reported a short rewind with no recurrence of the video/audio interruption.
The 20:53:13.780Z export confirms:

- 20:52:14.106: AirPlay connected.
- 20:52:18.244: one guarded seek from 3781.546 to 3636.655.
- 20:52:18.394: seek completed, about 150 ms later.
- 20:52:26.276: reported playback advancing.
- No source changes or timeout/retune errors recorded during this handoff.
- Wireless remained true until 20:52:57.290; the reason for that later route
  change is not established by these diagnostic events alone.

The stream start date changed from 19:48:43Z to 19:51:07Z (144 seconds) after
the seek. The numeric position decreased by 144.891 seconds. This strongly
supports a timeline-origin change rather than 145 seconds of actual content
rewind. Comparing those origins suggests roughly a one-second content rewind,
but startDate can itself update late, so this is an inference, not frame-level
measurement. One successful observed handoff is not broad validation.

## Simpler return classifier

Only the system-audio leg of TV via AirPlay uses the new binary question:
selected-sport coverage present? audio_usable is a separate boolean.
The worker normalizes these to program, not_program or unusable. Negative or
unusable samples reset return evidence without declaring a commercial break.
Two positive predictions spanning at least five fresh seconds are still required.
Football includes studio and halftime; UFC includes between-fight coverage.
Standalone sports advertisements/promos are excluded. A best-effort binary
decision can increase false positives; no accuracy improvement is claimed yet.

Microphone commercial detection, standalone observation and Mac-only automatic
playback retain the existing classification. Restart the native app to use the
new return mode; the active app was not interrupted. Existing saved diagnostic
clips retain only positive system predictions, not all unclear samples.

### Packaged correction: extension 0.2.21

The canonical correction now lives in `SafariExtension/directv-airplay-recovery.js`.
`directv-autoload.js` injects it in MAIN on completed DIRECTV page loads and into
already completed DIRECTV tabs when the background starts. This requires the new
exact host permission `https://stream.directv.com/*`. The AirPlay popup also
injects it, with a no-op on other services. Reinjection is idempotent. The
correction now lasts until page exit or panel restore/close rather than expiring
after an hour; the diagnostic ring remains bounded. Source tracing still has its
separate one-hour limit. The current page was updated and attachment verified.

Reload temporary extension v0.2.21 once and allow DIRECTV access to activate
refresh persistence. That browser lifecycle path has automated coverage but has
not yet been manually verified following an extension reload. Full Safari suite
had one stale expiry expectation; after updating that expectation, all nine
correction/autoload tests passed. All other Safari tests passed in the full run.

### Detection comparison follow-up

See [October 4 detection results](detection-oct4/results.md) for 24 approved
saved-clip/synthetic-silence requests comparing the current prompt, minimal
boolean output and Nick's crowd-plus-commentary variant. Minimal output was
faster in this pass but did not justify a live prompt replacement. All three
misclassified digital silence as program; worker source now rejects an exactly
silent final five seconds locally before calling Gemini. Eighteen Node tests
and Swift confirmation checks passed. Existing worker processes were not
restarted; future workers load the source fix. No playback commands, native
relaunch or extension reload occurred. Representative labeled transitions are
still needed to measure quality and boundary delay.
