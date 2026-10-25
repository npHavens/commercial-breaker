# Unused features removed — v0.2.46

The app now has two tabs: Automatic and AirPlay. Removed: the Recorder tab,
marker buttons and marked-clip saving; the local cue detector, which ran
during every automatic session for observation only; the Audio and Video
capture probes; the AirPlay tab's TV → Mac → TV test; and the tvOS prototype
target with its PiP generator. Their findings remain in this runbook's history
and `docs/archive`.

Automatic's detection, mute and handoffs are unchanged. Capture feeds Gemini's
buffer directly, as before. Routing logs keep their folder. Without the Changed
channel marker there is no manual context reset; the eight-second buffer
refreshes on its own and confirmation still needs two fresh predictions. A
session folder holds the Gemini log and, in system-audio legs, the existing
six return-audio diagnostic samples. Permission prompts now describe detection
and Vertex upload instead of marked clips.

Run every native test with `Tests/run-native-tests.sh`. `gemini-observation`
uses real timers and can fail under heavy machine load; rerun before treating
it as a regression.

Live verification pending: one Mac-mode and one AirPlay break/return cycle.

# Standalone Gemini setup — v0.2.45

Gemini no longer depends on the Interview Assistant checkout; this supersedes
the v0.2.13 bridge described below. Skybox declares `@google/genai` in
`package.json`, pins Node 24 in `.nvmrc`, and resolves Vertex settings itself
from `GOOGLE_CLOUD_PROJECT` and optional `GOOGLE_CLOUD_LOCATION` (default
`global`). The app starts `node --env-file-if-exists=<checkout>/.env
Tools/gemini-live-worker.mjs`; no TypeScript loader is involved. Vertex remains
the only destination, matching the consent text, and credentials come from
Application Default Credentials. See Gemini setup in the top-level README.

Setup failures stop Gemini with a specific message — missing `.env` project,
missing `npm ci`, or Node 24 not found — while recording continues. The worker
reports only fixed categories and waits for the app to read the reason.

To migrate an existing checkout, run `npm ci`, copy the `GOOGLE_CLOUD_PROJECT`
and `GOOGLE_CLOUD_LOCATION` values into `.env`, then rebuild. An older build
running from an updated checkout keeps working only after `npm ci`, because
the worker now loads the SDK from this checkout. Evaluation tools use the same
settings: `node --env-file=.env Tools/compare-detection.mjs --live`.

Offline checks cover configuration, setup failure reporting and worker
readiness without credentials. A live detection start with this build is not
yet verified.

# Automatic startup focus retry — v0.2.44

October 18 logs show first-start failures after opening the AirPlay picker:
Safari activation succeeds, then focus returns to Skybox. Later attempts work.
Startup now retries TV route verification once after a 0.5-second pause, only
when the focus failure identifies this Skybox process and it remains frontmost.
It still requires the TV already selected; no destination is selected by startup.
Cancellation, another foreground app, missing page controls, and an unexpected
route still stop startup. Break/return handoffs retain their existing focus rules.
Both attempts retain separate routing logs; a successful retry is noted in the
second log. This is a bounded recovery, not a confirmed fix for the focus bounce.

Live verification pending: first start from Skybox with TV already playing;
cancel during startup; switch to another app during startup; verify that an
incorrect initial route and a missing extension panel still fail safely.
The build is separate from the running app; restart only when playback permits.

# Long AirPlay breaks unmute without stopping — v0.2.43

Nick identified the October 11 stop as halftime and requested unmuting after
three minutes. At that limit, AirPlay mode now releases the Mac system-tap mute,
clears classifier context and continues listening with sound on the Mac.
Automatic and keep-awake remain enabled. Two fresh program predictions trigger
the usual TV return; continued break predictions do not mute the same break
again. Once back on TV, the next confirmed break follows the normal cycle.
The timeout cannot run during an in-flight handoff. Local Mac mode retains its
existing three-minute unmute/rearm behavior. Stop and terminal detector/capture
failures still perform normal cleanup and recovery.

Policy regression checks cover audible waiting, duplicate timeout rejection,
program return, next-break handling and stale completions. Live halftime timing
still needs verification. The prior incident is recorded in
`Experiments/oct11-automatic-stop.md`.

# Viewing activity refresh — v0.2.42, October 11

Nick clarified that walking away brought up a screen saver/lock screen rather
than only display sleep. Automatic already held a ProcessInfo display-sleep
activity. It now also reports ongoing local viewing with
`IOPMAssertionDeclareUserActivity` at start and every 30 seconds through the
existing health timer. The refresh runs across handoffs and picker retries,
stops on Stop/failure/shutdown, and releases the latest OS assertion ID. It
does not refresh while the main display is already asleep. Settings are not
changed, no keys or mouse events are synthesized, and it cannot unlock a Mac.
Failures are logged once per session; they do not stop audio detection.

The detector remains crowd-minimal-v2 from October 4. Nick reports that Flash
billing for the week's Skybox usage was only a few dollars; prioritize detection
responsiveness and accuracy over reducing request volume. Retain one in-flight
request to prevent a stale backlog.

Verification: lifecycle tests cover refresh cadence, replacement assertion IDs,
failure throttling, stop/restart and destruction. A live macOS smoke check
confirmed the assertion appeared and was released. Signed Debug build succeeded.
This verifies the API lifecycle, not an unattended screen-saver/lock timeout:
that behavior still needs today's walk-away test. Apple's API documents display
wake and idle-delay behavior; do not claim it overrides every lock policy.
Reference: https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity

Build for this session: `build/mac-audio-oct11/Build/Products/Debug/SkyboxAudioProbe.app`.
The old `build/mac-audio` app is retained. No Safari reload or route command was
issued during this change.

```sh
xcrun swiftc -module-cache-path /tmp/skybox-swift-module-cache \
  MacAudioProbe/ViewingActivity.swift Tests/viewing-activity/main.swift \
  -o /tmp/skybox-viewing-tests
/tmp/skybox-viewing-tests
```

# System mouse event experiment — v0.2.40

Nick confirmed that v0.2.39's process-directed mouse events did not visibly open
the picker. The fallback now posts a complete down/up pair through cghidEventTap
at the verified button center. This is system-wide event delivery, so it repeats
the exact global hit test and Safari foreground check immediately before posting.
No suspension or cancellation point occurs between the two events. Bounds,
permissions and companion-control checks remain. User interaction can still race
with posting; leave Safari untouched during handoff. No claim of hardware-trusted
input or proven picker compatibility is made. Live validation required.

# Verified mouse picker fallback — v0.2.39

After AXPress yields no picker controls, use one mouse down/up pair targeted to
Safari's PID instead of the Space fallback. Revalidate the named page button and
companion controls in Safari's main window; obtain current AX position/size;
require finite positive bounds and an exact system-wide AX hit-test match at the
center. An obscured or mismatched target is rejected. Event-post permission and
Safari foreground are required, with a final focus/cancellation check immediately
before the complete pair. Destination selection/verification is unchanged.
This is a live activation experiment, not a proven Safari user-gesture workaround.

# Sport selection — v0.2.38

Automatic has a Football/UFC picker, default Football, disabled while running or
recovering. The selection is passed to every worker through SKYBOX_SPORT, including
all capture handoffs and retries. Each worker combines Tools/sport-prompt.mjs
sport-specific editorial criteria with prompt-common.txt shared advertising rules.
Football includes halftime analysis; UFC includes between-fight coverage. Another
sport's commentary is not proof of return. Unknown selections fail worker setup.
Standalone observation defaults to Football. Selection is not persisted at relaunch.

The enabled log records sport and worker-ready records the assembled prompt hash.
The old prompt.txt remains for historical offline evaluations; it is no longer the
live worker prompt. Confirmation timing and six-slot system-audio diagnostics are
unchanged. Live classification improvement is unverified.

# False-return audio diagnostics — v0.2.37

Automatic system capture now retains the exact eight-second WAV request for a
fresh program prediction, with request ID, capture session, window times and
result metadata. Microphone and standalone observation requests are not retained
by this diagnostic. Six rotating slots (48 seconds total, about 1.5 MB of WAV)
are overwritten across capture legs in Application Support/SkyboxAudioProbe/
return-audio-diagnostics. Files remain after stopping for local inspection;
no additional cloud requests are made. Failed saves are logged without stopping
automation. Classification rules are unchanged. This supplies evidence for the
repeated false returns rather than assuming other tabs or prompt wording caused
them. These system clips can contain any app's audio.

# Prepare capture before TV return — v0.2.36

On confirmed program, release system mute, stop the system tap, verify cleanup,
and start microphone capture before selecting the TV. After selection, reset
Gemini context to discard audio accumulated during the picker operation; do not
reconfigure audio devices. Prediction actions remain blocked by the handoff task.

If picker acquisition fails before any destination press, stop the microphone and
restore unmuted system capture before entering the existing 30-second/fresh-
confirmation retry flow. Capture/cleanup failures or uncertain selection outcomes
use terminal recovery. Cancellation/session guards prevent an old handoff from
restarting capture after Stop. This tests whether post-selection tap teardown was
causing the brief TV playback interruption; the cause remains unproven.

# Prevent idle sleep during automatic mode — v0.2.35

Automatic mode holds a ProcessInfo activity with userInitiated and
idleDisplaySleepDisabled after log creation succeeds. This prevents idle system
and display sleep during both Mac and AirPlay operation, including picker retry
cooldowns. Stop, terminal failure (through stopAndRecover), and app shutdown end
the activity. The token also ends on deallocation/process exit. Global Energy
settings are unchanged; manual sleep, lid closure and locking are not overridden.
Standalone recording does not acquire this activity. Live idle-time validation
remains required; successful build does not prove a display stayed awake.

# Stricter program returns — v0.2.34

Commercial confirmation retains accelerated follow-up and one-unclear bridging.
Program candidates reset on any unclear prediction and use the regular five-second
sampling cadence. Confirmation also enforces at least five seconds between the
first candidate window end and the confirming window end, even if predictions
arrive faster. Thus the final five-second decision regions do not overlap.
Opposing evidence resets the candidate; existing stale-data rules remain.
No prompt changes. This addresses the observed Program → Unclear → Program
false return during Nick's reported Ford commercial. It cannot guarantee that
Gemini will distinguish commentary embedded in an ad from actual game coverage.
Live return latency and accuracy remain to be verified.

# Less hesitant sports classification — v0.2.33

The shared prompt now reserves unclear for TV audio that cannot be judged, rather
than requiring proof that audible advertising replaced the picture. Embedded
reads remain program when continuing editorial context is audible. Positive
editorial evidence is still required for program returns. Prior prompt saved as
Experiments/audio-model-eval/prompt-sports-v4.txt. Live accuracy remains unverified.

Confirmation still requires two positive matching predictions. One intervening
unclear sample preserves a one-result candidate for at most 15 seconds from its
last positive evidence; unclear never refreshes that deadline. A second unclear
clears the candidate. Opposing evidence starts a new candidate. Existing stale,
invalid and duplicate timestamp resets remain. Confirmation and automatic-policy
tests pass. This change does not change picker/focus recovery behavior.

# Nonterminal picker acquisition failures — v0.2.32

When the picker fails before any destination selection is attempted, Automatic
now retains capture and stays enabled. A TV-to-Mac attempt keeps the microphone
until the Mac route is confirmed. A Mac-to-TV attempt releases mute but keeps
system capture until the TV route is confirmed; on acquisition failure it stays
in audibleMacAwaitingTV. Both wait 30 seconds, reset Gemini context, then require
fresh confirmation before another attempt. Predictions during cooldown cannot
trigger actions. Program on TV and Break on the audible Mac do not retry the
opposite handoff. Detection health checks still apply throughout cooldown.

Only the bounded missing-destination-rows error before a destination press is
retryable. Routing strips this classification once selection was attempted,
because an unconfirmed result may already have changed playback. Focus errors,
ambiguous selections, capture failures and uncertain post-selection outcomes
still stop and use existing cleanup/recovery. Stop cancels a pending handoff and
clears the cooldown. No prompt or detection thresholds changed.

Validation: signed Debug build and policy tests cover both recovery directions,
stale completion rejection, and stop/recovery guards. Live picker disappearance
itself is not solved or reproduced by these tests; this change prevents that
specific pre-selection failure from terminating a healthy detection session.

# Safari foreground acquisition — v0.2.31

Live relay sessions confirmed breaks but stopped before selecting the Mac route:
the single AppKit activation request did not establish Safari foreground within
the old fixed half-second wait. This does not establish which app held focus.

Routing now yields Skybox activation to Safari, requests cooperative activation,
and polls for one second. If unconfirmed, it requests AXFrontmost on that Safari
process and polls for two more seconds. Cancellation remains effective during
polling; a failed foreground request never authorizes a click. Existing focus
checks throughout picker scanning, selection and keyboard activation remain.
Logs include activation results and the frontmost bundle ID, not window content.
There is no repeated focus stealing after a picker operation begins.

Signed build and existing panel, destination-selection and automatic policy
checks pass. Actual foreground handoff from the running app still needs live
verification; those tests do not simulate macOS activation.

# Relay AirPlay routing — v0.2.30

The existing HLS relay's Choose AirPlay button now participates in the same
bounded picker acquisition, keyboard fallback, exact destination selection and
automatic routing as the extension's Try AirPlay panel. It requires unique
adjacent Play, Check playback and Stop playback buttons; similarly named buttons
without those companions are rejected. Cached controls are revalidated on use.
No relay-page refresh is required.

Nick confirmed fresh-session Paramount relay playback on TV on October 3.
Automatic relay round trips still require live verification. Leave the relay's
playlist-based automatic mute off. With the relay tab active and already playing
on TV, choose TV via AirPlay in the native app's Automatic tab and start.
The existing microphone/system-audio capture and two-prediction policy apply.
The AirPlay three-minute mute cutoff still stops and requests TV recovery.

Validation: panel/relay matching, destination selection and automatic-policy
tests passed; signed Debug build passed. These do not establish live picker or
audio handoff success.

# Shared manual picker acquisition — v0.2.29

The AirPlay tab's Inspect, Select TV and round-trip test used immediate AXPress
and scanning, bypassing Automatic's bounded wait and focused-keyboard fallback.
They now reuse availablePickerControls. Inspection requests any nonempty set of
picker controls; an empty requested-label array no longer makes an empty scan
succeed. Selection still requires the exact destination, and already-selected TV
is left unchanged. Manual failures retain scanner diagnostics. The round-trip
reacquires the picker before its final TV request too. This does not fix Paramount
blob/HLS playback: the native app still activates Safari's page button. Prior relay
playback and current picker routing are separate compatibility questions.

# Local mute timeout continues detection — v0.2.28

Mac playback no longer stops automation at the three-minute mute limit. It
requests unmute on the existing tap, clears the mute deadline and Gemini context,
and continues capture/worker operation. It waits for a new confirmed program
before rearming; repeated break predictions cannot immediately mute that same
break again. The existing two-result confirmation applies after the context reset.
If unmute fails, the normal stop/cleanup path removes the tap. Detector terminal
failures still stop and release sound. The TV/AirPlay timeout behavior is unchanged
pending resolution of its separate picker issue. Policy tests cover expiration,
duplicate notifications, rearming only after program, and late completion rejection.

# UFC replay prompt correction — October 3, 2026

Nick reported a false mute during a post-fight replay. Two fresh promo predictions
triggered it based on model descriptions of a TV-show promotion. Prompt-only
revision distinguishes embedded promotional reads from standalone spots and uses
unclear when an audio excerpt cannot distinguish them. No network-specific rules
or added confirmation delay. The prior prompt and incident notes are preserved
under Experiments/audio-model-eval/. No marked audio exists to replay this exact
incident; effectiveness requires a subsequent live check. Stop/restart automatic
mode to load the prompt; the native app stays v0.2.27 and needs no rebuild.

# Direct Mac automatic mode — v0.2.27

Nick requested skipping another observation-only recording round. Automatic now
has Mac playback (default) and TV via AirPlay modes. Local playback starts one
unmuted system tap and Gemini worker, mutes the existing tap after two matching
break predictions, then restores it after two program predictions. Capture and
model context stay running while output is muted; no picker or route changes
occur. All captured Mac audio is affected. Stop/quit removes the tap and releases
mute. The three-minute muted bound and bounded request retries remain.

Start with Paramount audibly playing locally, choose Automatic > Mac playback,
then Start automatic test. Do not change AirPlay routes during this mode. The
state-machine tests exercise local transitions, duplicates, and recovery; real
UFC accuracy and physical mute behavior require the live test. This mode reuses
the existing CoreAudio tap mute operation rather than adding a new audio path.

# UFC and shared program classification — v0.2.26

The live response schema, native confirmation policy and route controller now use
program/commercial/promo/unclear rather than football. The prompt covers both
UFC/MMA and football without network-specific music rules. UFC coverage includes
walkouts, corner breaks, decisions, interviews and between-fight analysis; sports
inside standalone ads/promos still count as breaks. Ambiguity remains unclear.
Two matching predictions and fresh-audio confirmation cadence are unchanged.

The previous football prompt is preserved as prompt-football-v2.txt beside the
current prompt. Existing recordings/results are unchanged; new predictions use
program and new markers use Program returned / Changed channel. Legacy marker
names remain accepted for recording context and channel-reset behavior.

First live UFC check: keep Paramount+ playing audibly in Safari on Mac, use the
Recorder tab with System audio, Start listening, then Start Gemini. Mark commercial
starts and program returns. This observation path does not mute or change routes.
UFC accuracy and Paramount automatic AirPlay handoffs are not yet verified. The
Automatic tab still requires TV AirPlay already active; v0.2.25 keyboard activation
fallback remains unverified. Do not imply local observation automatically mutes.

# Keyboard activation fallback — v0.2.25

Nick confirmed no picker appears during automated AXPress, although the page
handler logs Picker requested; manual clicks open it. This does not prove the
specific Safari cause, but shifts the experiment from scanning to activation.
After an empty bounded picker wait, automation now tries Space once on the
verified Try AirPlay button. It requires event-post permission, successful AX
focus assignment, matching focused-element identity, and foreground Safari.
The key pair targets Safari's PID, with no cancellation point between down/up.
No coordinate fallback or keys to the general video player are intentional.
Destination selection remains exact and independently verified. Live testing is
required to establish whether Safari accepts this keyboard activation.

# Embedded picker search — v0.2.24

The 4:09 PM startup attempts reached the page button handler (confirmed by Nick),
but the native-only scanner exposed no destination controls. Manual clicking still
opened the picker. The cause is not yet confirmed. An empty native scan now falls
back to searching webpage descendants for picker containers, retaining exact route
matching and selected-state verification. Ordinary webpage buttons are excluded;
only controls within the existing picker roles qualify. The fallback is bounded
at 3,000 elements, depth 40, and five seconds. This tests whether Safari embeds the
picker in the previously skipped AXWebArea. Page-button diagnostics are retained
before subsequent picker scans overwrite them. Live validation remains necessary.

# Bounded recovery for unclassified requests — v0.2.23

At 4:01:18 PM one request-failed event with no HTTP status disabled detection,
causing TV recovery while the last confirmed state was commercial. Unclassified
request failures now use the existing fresh-audio retry delays (5 then 10 seconds).
Capture and the current route stay active during recovery. Three consecutive
failures still stop automation and recover TV; success resets the failure count.
Explicit nonretryable HTTP client/authentication errors remain terminal. Unknown
errors are not asserted to be transient; retries are bounded. Confirmation resets
on failure, so fresh matching predictions are required before a route change.
The three-minute muted-break bound remains in force.

# Flattened Safari panel — v0.2.22

The 3:50 PM diagnostic confirms Safari exposes the enabled Try AirPlay button,
but its parent is AXWebArea rather than a small panel group. For that structure,
validate a bounded neighborhood (four siblings on either side) for the exact
Try AirPlay and Restore settings and close controls. The existing 80-element
subtree bound and duplicate rejection remain. No whole-page companion search
or coordinate clicks are used. Tests cover nearby versus distant companions
and page edges; a live route retry is still needed.

# Safari panel compatibility — v0.2.21

The visible-panel startup failure in v0.2.20 exposed overly strict matching.
The lookup now checks up to four bounded ancestor subtrees for the exact enabled
Try AirPlay button and its Restore settings and close companion. It no longer
requires the history text area's accessibility label. Duplicate Try AirPlay
buttons remain rejected within each complete candidate subtree. Searches compare
AX elements with CFEqual; equal hash values alone no longer discard distinct
controls. Diagnostics record counts and validation stages, without page content.
Live Safari validation remains required. Automatic mode still has no session limit.

# Targeted page-panel lookup — v0.2.20

The 3:41:30 PM startup log fails immediately after “Opening AirPlay picker”:
the include-web scan locating Try AirPlay exhausted its bound before any route
selection. It previously collected every pressable control across the page even
when the extension panel had already been encountered.

Opening the picker now searches trailing children first (the extension appends its
floating panel), stops after verifying the panel's exact button/close/history
labels, and caches the button. Cache reuse requires current-window ancestry and a
fresh bounded panel validation. Only the active Safari window is searched. Buttons
with the same name outside that panel and duplicate buttons inside it are rejected.
Device selection retains its existing complete, bounded native picker scan.
Panel signature tests and the signed build pass; live Safari verification remains
necessary because accessibility structure can change. The no-session-limit setting
from v0.2.19 remains in effect.

# Continuous automatic mode — v0.2.19

Automatic mode has no 15-minute deadline. Each recorder leg explicitly starts
without a time limit, so a long uninterrupted game cannot stop detection through
the recorder's former default. It runs until stopped or an existing failure/recovery
condition occurs. The standalone marked Recorder retains its 15-minute default.
The three-minute muted-break limit and stop/recovery controls remain unchanged.
Continuous mode continues Vertex audio requests while enabled; it does not restart
after an app exit or failure. This change does not claim unattended routing is
reliable or prevent Mac sleep.

Apple TV can independently enable automatic subtitles, even with player captions
off. First check Settings → Video and Audio → Automatic Subtitles → Show When Muted.
This is a possible explanation for the reported AirPlay captions, not a confirmed
cause; no subtitle settings or track modes were changed in the extension.
Source: https://support.apple.com/en-gb/guide/tv/atvb7d97de8b/tvos

# Picker startup and service recovery — v0.2.18

The first automatic test successfully moved TV → Mac and captured muted system
audio. At 20:20:13Z Gemini returned a generic request failure. This stopped detection
and triggered TV recovery at 20:20:14Z, confirmed at 20:20:15Z. Contrary to the initial
appearance, no confirmed Football pair triggered that return: football guesses in
an ad were interrupted by unclear and then the failed request. The previous logs
do not establish the provider/network cause of that generic error.

Subsequent starts failed after a single picker read found no destination controls.
Routing now waits for expected rows, retries the page button once only if no controls
appear, and logs focused-element/role diagnostics on failure. This hardens timing
and provides evidence; live restart success is not established by the build.

Gemini reports only fixed error classes and optional numeric HTTP status. HTTP408,
429, 5xx and allowlisted temporary transport failures recover with fresh audio after
5/10 seconds; three consecutive temporary failures stop detection. Auth, malformed
responses and unclassified failures still stop. Unknown failures are not assumed
transient. Worker tests cover this distinction without transmitting audio.

The prompt now distinguishes actual game broadcasts from realistic football scenes
in ads/promos, explicitly prohibits invented visual evidence, and accommodates both
room microphone and direct system audio. The prior prompt is preserved as
`Experiments/audio-model-eval/prompt-v1.txt`; live worker-ready logs record prompt
hash. No accuracy improvement is claimed without live testing. Two-result timing
and microphone gain are unchanged.

# Supervised automatic commercial test — v0.2.17

The new Automatic tab connects two-result Gemini confirmations to native AirPlay
routing and the existing muted system-audio tap. Start with DIRECTV already playing
on the TV, the Skybox extension page panel visible in Safari, and exact Mac/TV names
saved in the AirPlay tab. Stop other capture/recording tests first.

Click **Start automatic test**. This enables audio uploads to Vertex AI for the
15-minute test, including nearby voices while using the microphone and all Mac
playback while using system audio. The initial TV selection must be verified.

- While on TV, the microphone feeds Gemini. A confirmed Break stops microphone
  capture, verifies the TV → Mac handoff, and creates an already-muted system tap.
- While muted on the Mac, system audio feeds Gemini. Confirmed Football removes
  the tap before requesting/verifying the TV route, then restarts microphone input.
- Each capture leg has its own recorder folder, raw prediction/confirmation log
  and optional marked clips. `automatic-<UUID>.jsonl` links the legs and actions.
- **Stop & return to TV** immediately stops capture/removes mute, cancels the current
  action, then attempts TV recovery after that action exits. Recovery failure leaves
  local audio unmuted and reports that Safari's picker needs manual recovery.
- A detector/capture failure, the three-minute muted limit, or the 15-minute test
  deadline stops automation and attempts TV recovery. Closing the app removes mute
  immediately but cannot wait for asynchronous TV recovery.

The picker automation brings Safari forward and requires it to stay foreground
during each handoff. Brief audible Mac playback can occur during transitions.
Selected-state verification is not proof of physical TV picture/sound; this is the
first integrated live test. All Mac playback is captured/muted, not only DIRECTV.
No network-specific rules, additional model tuning, or microphone-gain changes.
Other app capture/routing controls are disabled while the automatic controller owns
capture. Markers remain available in Automatic and never cause a mute by themselves.

Verification: signed Debug build passes. Pure state tests cover the complete cycle,
duplicate predictions, wrong-phase completions, and recovery; existing confirmation,
worker protocol, and native fake-worker lifecycle tests remain applicable. Actual
combined detector/routing/mute behavior still needs the user-started test.

# Faster confirmation — v0.2.16

A pending 1/2 prediction now requests its follow-up as soon as the current request
finishes and at least one second of newer audio is available. The control timer
checks every 250 ms; receiving a result also immediately checks eligibility.
Stable states retain the normal five-second sampling interval. There is still
only one request in flight, and timeout backoff takes precedence. Raw audio windows
remain eight seconds long; requests never resend an unchanged window for a vote.

This removes the fixed five-second wait for confirmation. With the measured
roughly 1.5-second responses, the added confirmation time may approach another
model response instead of another full polling interval. Actual transition delay
also includes the first polling interval and audible evidence, so it is not a
promise of 1.5-second overall detection. More-overlapping samples may repeat the
same mistake. Playback stays manual while this is tested. Logs identify fast
follow-ups for timing comparison. The fake-worker integration test verifies that
confirmation occurs before the normal interval and uses at least one second of
new audio, alongside reset/stop/timeout recovery checks.

# Two-prediction confirmation — v0.2.15

The live display now shows a raw prediction and a separate two-prediction result.
Commercial and promo share the Break category. Two consecutive matching results
confirm Break or Football; unclear interrupts the pending pair. During an opposing
single prediction or unclear audio, the previous confirmed state is explicitly
labeled **Last confirmed**, not asserted to be current. No playback action occurs.
Game changes, stop/start, request errors and audio older than 15 seconds clear
confirmation. Audio windows more than 15 seconds apart cannot form a pair.
Both raw and confirmation results are logged for comparison. Markers do not feed
the confirmation logic. Overlapping audio windows are not independent evidence.

Nick clarified that the previous return marker was late and an NFL promo preceded
the game return. This makes the early football predictions plausible, not verified
independent ground truth. Keep marking transitions to evaluate this live display.

# Timeout recovery — v0.2.14

An isolated Gemini timeout no longer requires restarting observation. After the
first two consecutive timeouts the app waits 5 and 10 seconds, then checks a fresh
audio window. It never retries the old clip. Three consecutive timeouts, other
errors, or an unresponsive worker stop Gemini; recording continues. A successful
response resets the timeout count. Playback remains manual. The recovery bounds
and actual fake-worker recovery path are covered by tests.

# Live Gemini observation — v0.2.13

The Recorder now offers an explicitly enabled Gemini observation mode. It uses
Interview Assistant's installed Node 24/tsx/Google SDK and Vertex credentials,
without modifying that project. This development bridge requires the Skybox and
Interview Assistant source directories to remain in their current locations.
It discovers Node 24 under `~/.nvm/versions/node`. Worker startup fails if the
shared configuration is not Vertex, matching the destination named in the UI.

1. Open Recorder and choose Microphone for native AirPlay, or System audio for
   playback on the Mac. Start listening and confirm a changing input level.
2. Click **Start Gemini · send audio**. This explicitly enables sending the latest
   eight seconds, including nearby voices, to Google Vertex AI approximately every
   five seconds. No audio is uploaded merely by launching the app or recording.
3. After roughly eight seconds plus inference time, read the timestamped
   Football / Commercial / Promo / Unclear prediction. Continue using the existing
   Commercial started / Football returned / Changed game buttons. Markers are
   logged locally and never provided to the model.
4. **Changed game** resets the sample window and discards results from the prior
   context. Stop recording before changing the capture source or AirPlay route.
5. **Stop Gemini** ends uploads while local recording continues. **Stop & save**,
   closing the app, or the 15-minute recorder limit stops both. An audio request
   already sent cannot be recalled. Muting and routing remain manual throughout.

The worker uses `gemini-3.8-flash` at its lowest thinking level, `LOW`; Gemini 3
models no longer support the `thinkingBudget: 0` that disabled thinking on 2.5
Flash, which new Vertex projects cannot use. The football prompt was tuned on 2.5
Flash, so its accuracy on 3.8 Flash is unproven. This is an experimental
latency baseline, not a validated detector or permanent model choice. One request
is allowed at a time, without retries or queued audio. Non-timeout failures disable Gemini
while recording continues; timeout recovery follows v0.2.14 above. Capture gaps, nonfinite input, format changes and game
changes clear the eight-second buffer. Predictions older than 15 seconds are no
longer displayed as current. Confidence is not treated as a control threshold.

`gemini-observations.jsonl` saves enable/disable events, request audio time bounds,
model responses, usage, latency and discarded results in the existing recording
session directory, beside marker events and marked WAVs. Unmarked sample audio is
held temporarily in memory, not saved to disk. Raw provider errors and credentials
are not logged. The prompt requests TV evidence, not room-conversation transcripts;
model output can still be inaccurate. Original marked recordings remain local.

Verification: nine Node tests cover input validation, structured output, no queue
or retries, timeout/cancellation and protocol framing. Native buffer tests cover
8/44.1/48/192 kHz conversion, exact duration/format, discontinuities and stale
samples. A native fake-worker test verifies current predictions, game-change
invalidation and stop/restart without sending any audio. The real worker startup
was checked without an inference request. Live hardware/network operation through
the new UI still requires a user-started session.

```sh
node --test Tests/gemini-audio/*.test.mjs
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -parse-as-library -module-cache-path /tmp/skybox-swift-module-cache \
  MacAudioProbe/GeminiAudioBuffer.swift MacAudioProbe/GeminiRecovery.swift \
  MacAudioProbe/GeminiConfirmation.swift MacAudioProbe/GeminiObservation.swift \
  Tests/gemini-observation/main.swift -o /tmp/skybox-observation-tests
/tmp/skybox-observation-tests
```

---

# Native macOS capture probe

## Prospective transition cues — v0.2.12

A frozen exploratory rule now emits **Possible break cue** while recording. It
requires a sustained music rise and crowd drop relative to earlier context; the
full thresholds are logged under `breakRule` in the classifier metadata. The app
shows the last cue time and count, and writes `breakCandidate` events to
`live-cues.jsonl`. Existing marker buttons and recording behavior are unchanged.
No mute, route change, or automatic commercial-state transition is performed.
There is no return detector yet.

In the first replay, this rule emitted two candidates: 9.79 seconds before the
first commercial click and 7.54 seconds after the second. It emitted no other
candidates during that session. These are offsets from approximate user clicks,
not measured broadcast boundaries. The data had already been inspected; this is
an exploratory result that needs new footage, not an accuracy claim. See
[the replay report](../Experiments/audio-cues/187D0070/README.md).

For the next session, start listening and keep using the existing start, return,
and game-change markers. Do not adjust markers to agree with the displayed cue.
The candidate needs at least 15 seconds of prior audio context after a game change.
Scores continue during ordinary football so extra signals and misses can be
reviewed afterward without another button.

Validation: signed Debug build passed. Swift detector replay exactly matches the
Python candidate times and baseline features; tests cover persistence, thresholds,
cooldown, resets, invalid input, and bounded history. The streaming WAV regression
also passed with candidate integration. Live prospective validation is pending.

## Continuous sound scores with existing markers — v0.2.11

Recorder now displays speech, music, and crowd/cheering scores and writes
`live-cues.jsonl` throughout each listening session. The built-in Apple SoundAnalysis
classifier runs locally using three-second windows with 50% overlap. The crowd
indicator is the maximum of crowd, cheering, and applause, with constituent scores
also logged. These are sound cues, not commercial probabilities or automatic mute
commands. Nearby voices can affect the speech score.

There are no additional marker buttons. Existing **Commercial started** and
**Football returned** markers identify intervals for later review. **Changed game**
resets classifier context and leaves the marked state unknown until the next
start/return marker. Initial context is also unknown. The app labels displayed
context as marked by the user, never as a model decision.

Raw audio remains limited to marked clips. Numeric sound scores continue between
markers, allowing normal football/replay music to be compared with commercials.
A separate bounded analysis queue handles classification; unsupported input,
overload, or logging failure disables analysis and reports an error while the
recorder continues. Stale displayed results clear after eight seconds. Stop and
source changes tear down analysis; game changes reject stale classifier callbacks.

After recording, generate interval summaries with:

```sh
python3 Tools/summarize-live-cues.py '<session-directory>'
```

The tool joins original monotonic window timestamps to existing markers, preserves
unknown intervals, and excludes windows within five seconds of marker boundaries
because clicks are approximate. Counts and mean scores are exploratory; overlapping
windows are correlated and no detection accuracy is implied. It writes
`cue-summary.json` beside the session logs. This summary step is not an app button.

Validation: live-analysis service replayed an existing WAV and passed checks for
real classifier output, score bounds, reset/gap timing, JSONL, invalid input, and
backlog shutdown. Marker-joining tests cover ordinary play, commercial intervals,
game changes, duplicate markers, stopping, boundary-crossing windows, and invalid
scores. Native signed build passed. The new UI and continuous logging still need a
live TV session; microphone recording and earlier clip analysis were tested in
previous versions.

## Quiet-TV microphone test — v0.2.10

September 27: the first session saved two commercial-start clips and one football-return
clip from the microphone. RMS was approximately −50 dBFS, without clipping or
reported dropped blocks. This confirms nonzero input, not intelligible TV speech
or separation from nearby voices. The default microphone input-volume scalar was
0.27450982; it was raised to 0.5 and read back successfully for the next experiment.
This is a system-wide input setting, not automatic gain control. It can be changed
in System Settings → Sound → Input; the previous setting was about 27%.

The original clips contain about 29.248 seconds instead of the intended 30.
The microphone now maps AVAudioTime sample positions and host timestamps to marker
uptime, avoiding overlap trimming caused by callback scheduling jitter. Missing
sample/host timestamps stop capture with an error rather than falling back to
jittery arrival times. Actual sample gaps remain gaps. Existing recordings are
unchanged; the timing fix applies to new sessions.

Keep the same TV volume and Mac location for the next comparison. Room voices are
expected; louder input alone does not improve the TV-to-room-noise ratio. Evaluate
captured content before adding detection thresholds. Signed build and clip tests
passed, including an integrated 4096-frame / 48 kHz regression at realistic uptime
that saves exactly 1,440,000 samples (30 seconds) despite callback jitter.
Live validation of the new timing and input level is pending.

## Marked audio recorder — v0.2.9

The app now opens on **Recorder**. It collects examples across games without
network-specific rules. It does **not** detect commercials, mute playback, or
automatically change AirPlay routes. Signed Debug build passed. Automated checks passed for audio levels, tap channel
conversion, readable WAV clips with exact pre/post boundaries, partial clips,
game/sample-rate resets, timestamp recovery, and existing route selection.
Live microphone permission, TV audibility, and saved broadcast clips still need
verification; the earlier routing results below do not verify this new recorder.

1. For TV playback through native AirPlay, choose **Microphone · TV / AirPlay**.
   Keep the Mac close enough to hear the TV. For local Safari playback, choose
   **System audio · Mac playback** and pause other Mac audio sources; this source
   captures the system mix, not only DIRECTV.
2. Click **Start listening** and allow the relevant macOS recording permission.
   Check that the input level responds to the broadcast. The session stops
   automatically after 15 minutes; the remaining time is shown.
3. Click **Commercial started** when a break starts and **Football returned**
   when the game returns. Each marker saves up to 20 seconds before and 10 seconds
   after the click, limited to the audio available. A slightly late click is fine;
   the recorded marker is your click time, not a verified broadcast boundary.
4. Click **Changed game** when switching games. This saves pending clips as
   partial clips and clears the preceding audio context so clips do not span games.
   **Stop & save before changing audio source or AirPlay route**, then start a
   new session using the appropriate source. Other capture/routing tests are
   disabled while recording.
5. After at least one complete break, click **Stop & save**. Waiting ten seconds
   after the last marker preserves its full trailing context; stopping sooner
   saves the available partial clip. **Show saved clips** opens the session folder.

Files stay on this Mac in
`~/Library/Application Support/SkyboxAudioProbe/recordings/<session UUID>/`:
marked WAV clips, their JSON metadata, and `events.jsonl`. Metadata records
available coverage and missing-audio information; a marker with no audio may
produce metadata without a WAV. Unmarked audio is held only in a bounded memory
buffer and discarded. Microphone clips can include nearby conversations; nothing
is uploaded. Saved files can be read directly for analysis without a Safari export.

The first live check is usable audio in saved clips, marker timing, and clean
stop/source changes. Commercial classification is a subsequent experiment; see
[general audio cues](../Experiments/general-audio-cues.md).

## One-second settling experiment — v0.2.8

Live result at 17:13Z September 26: all ten muted measurement intervals contained
nonzero audio (960,512 samples), with no cleanup errors. Mac selection was
requested at 17:13:44Z and the muted tap started at 17:13:46Z, approximately two
seconds later at the logs' timestamp precision. TV selection was requested at
17:13:57Z. Evidence: `routing-673BDB71-80CC-48C3-A078-221E19D9E1BD.log` and
`probe-1790442826-64A2CD48-6F63-46DF-A920-A9A2B989B1DE.jsonl`. This is one
successful shorter-delay sample-access run, not long-term reliability evidence.

Reduces only the explicit local settling wait from five seconds to one second.
Route confirmation, muted-at-creation tap, ten-second measurement, and tap removal
before requesting the TV stay unchanged. Picker inspection and tap startup add
time beyond this wait, so this is not a promise of a one-second audible gap.
The successful five-second configuration remains documented below; the shorter
configuration has now passed the live sample-access test above. Run the same round-trip test with
Safari foreground for about twenty seconds.

## Create the post-handoff tap muted — v0.2.7

Live result at 17:10Z on September 26: all ten measurement intervals contained
nonzero audio while mute was requested from tap creation (960,512 samples).
Cleanup reported no errors, followed by the TV selection request. This verifies
sample access with muted-at-creation capture after the local handoff; TV playback
and physical silence remain observations for the listener. Evidence:
`routing-C50F71CF-21F9-4C36-8D95-AE120174C646.log` and
`probe-1790442628-08861748-5447-4D5A-B055-0C089B0A9FED.jsonl`.

This removes the five-second unmuted capture phase from the successful v0.2.6
sequence. The existing five-second local settling interval and route confirmation
remain, isolating whether a tap created with `mutedWhenTapped` still captures
after the handoff. The tap now starts muted, measures for ten seconds, and is
removed before requesting TV. The initial mute has the same 45-second fallback.
The Audio tab still starts unmuted by default. Audio logs record the actual app
version and whether mute was requested at tap creation.

Brief audible local playback remains during settling/confirmation and possibly
before the TV reconnects. If this configuration succeeds, the settling interval
can be shortened separately. The live result above now verifies muted-at-creation
capture; it was not inferred from the earlier unmuted-then-muted result.

## Successful combined handoff/capture test — September 26

The v0.2.6 run at 17:05Z switched to Mac before creating the tap, captured nonzero
audio in all five unmuted intervals and all ten mute-requested intervals, removed
the tap without cleanup errors, and requested the TV again. Nick reported that
the run appeared to work. Audio evidence: 1,434,624 samples, including 954,368
during the mute phase. This establishes sample access in the combined workflow;
the listener still determines physical output and TV playback success.

Evidence files: `routing-8B91CF83-6266-4F73-9489-1B2F7EDE31D4.log` and
`probe-1790442336-6F960A8C-47CD-4F42-8DEB-3DC08EB14E2A.jsonl` in the diagnostics
folder. Starting the tap after local handoff is a working configuration; the
experiment does not isolate a single cause of earlier failures because Safari
was also restarted and tap removal before TV handoff changed. Microphone capture,
commercial recognition, reduced audible transition time, and background routing
remain unimplemented or unverified.

## Tap after local handoff — v0.2.6

Nick restored DIRECTV audio by restarting Safari, then separately confirmed a
manual AirPlay round trip and local tap capture/mute/restoration. Earlier
combined tests created a muted tap while playback was still on the TV. Version
0.2.6 changes the ordering to investigate that interaction:

1. Confirm the TV is selected; select Mac with no tap running.
2. Allow five seconds of audible playback, then confirm Mac in the picker.
3. Start the tap unmuted and measure for five seconds.
4. Mute through the tap and measure for ten seconds, with a 45-second fallback.
5. Stop/remove the tap before requesting the TV. Local sound may briefly resume.

This is intentionally audible during the first local phase. The routing log
reports counts of nonzero intervals before and during the mute; boundary
intervals can straddle the mute change. Audio JSONL remains the detailed evidence.
No causal claim about the old silence is established yet. Mac/TV field values
now persist in user defaults after editing. Keep Safari foreground for roughly
thirty seconds. These instructions supersede the older muted-from-start tests.

## Longer handoff audio test — v0.2.5

The repeat routing run with keyboard mute removed still produced all-zero audio
in five intervals (472,064 samples). Keyboard mute alone therefore does not
explain the observed result. Version 0.2.5 extends the local dwell from three
to twenty seconds and sets a 45-second tap-mute fallback; completion, cancellation,
and failure still stop capture and restore output. Keep Safari foreground for
about thirty seconds. This tests delayed local audio resumption before changing
the tap lifecycle. No nonzero audio after an AirPlay-to-Mac transition has yet
been verified.

## First successful routing test — September 26

Nick confirmed the second TV → Mac → TV attempt worked after accepting a
permission prompt. The routing log requested Mac at 16:42:47Z, confirmed the
Mac selection before requesting TV at 16:42:51Z, and ended capture at 16:42:52Z
without cleanup errors. This verifies the foreground picker-automation route
with user-observed playback return, not unattended/background operation.

The five measured audio intervals during this run were all zero (474,112
samples). Silent observation immediately after returning from AirPlay therefore
remains unverified despite the earlier successful local-only audio test. The
next experiment should allow more time for local playback to resume and, if
needed, restart the tap after the route transition. Extend the mute lifetime
alongside any longer local dwell; the current ten-second fallback is not a
commercial-length mute controller. Commercial classification and microphone
capture remain unimplemented.

## Live picker inspection — v0.2.4

September 26 inspection successfully resolved eight Safari AirPlay destinations.
The local label is `Nick’s MacBook Air` (curly apostrophe); `Living Room` is an
available TV label. Safari reported the selected Mac checkbox as disabled.
Route confirmation now accepts selected controls regardless of enabled state;
pressing a new destination still requires a unique enabled match. Both row-label
inspection and permission access are verified, but the automated round trip is
still awaiting a live test.

## Picker row labels — v0.2.3

After the scoped Accessibility reset and user grant, native inspection opened
Safari's picker successfully. The September 26 log showed an AXPopover containing
eight AXRows, eight unnamed AXCheckBoxes, and eight AXStaticText elements; focus
belonged to Safari's AXTable. Version 0.2.3 resolves an unnamed checkbox/radio
control's name from one distinct static-text label within its own AXRow. Multiple
labels or bounded traversal failures remain inconclusive. This applies only to
picker containers, never webpage content. Live device-name verification and
automated destination selection remain outstanding.

## Stable development signing — v0.2.2

Accessibility remained denied after the user removed/re-added the v0.2.1 app.
Inspection confirmed the running executable was the expected project build,
but its ad-hoc designated requirement was a pair of build-specific code hashes.
The macOS target now signs with Nick's existing Apple Development identity and
team SHL25NTZ48. The v0.2.2 build succeeds and its designated requirement uses
the bundle identifier and development certificate instead of build hashes.
This corrects an identity-instability issue; whether it resolves the current
Accessibility denial still requires a fresh grant and live inspection.
Subsequent macOS TCC logs confirmed that the new executable was being checked
against an old ad-hoc code-hash requirement, failing with status -67050. A scoped
`tccutil reset Accessibility com.nohandsstack.skybox.audio-probe` succeeded on
September 26. The user must grant Accessibility again for the development-signed
app. No TCC database edits or global permission resets were performed.

## Picker diagnostics — v0.2.1

The September 26 inspection reached the picker scan but found no pressable
destination controls. No route was selected. Version 0.2.1 waits an additional
1.2 seconds during inspection and records the focused Accessibility element's
owner, visited role counts, unnamed-control counts, and bounded candidate labels.
This distinguishes a delayed, differently structured, or separately hosted picker
without relaxing the requirements for choosing a destination. Build and existing
selection checks pass; repeat **Inspect picker** with Safari foreground to collect
the new evidence. No successful automated route switch has been demonstrated.

## Native AirPlay routing experiment — v0.2.0

The **AirPlay** tab adds Accessibility-based picker inspection, explicit TV
selection, and a bounded TV → Mac → TV test. Build and exact-name selection
checks pass. Live Safari Accessibility behavior remains unverified.

1. Quit the old probe and open the newly built app. Confirm **v0.2.0** in AirPlay.
2. In Safari, play DIRECTV and show Skybox's page panel with **Try AirPlay**.
   Keep that tab in the front Safari window, exit fullscreen, and connect to TV.
3. In the native app, click **Enable Accessibility**. Enable **SkyboxAudioProbe**
   under System Settings → Privacy & Security → Accessibility. This permission
   is separate from system-audio recording; the app requests it only on click.
4. Click **Inspect picker** and leave Safari foreground during inspection. The
   native app activates Safari and presses the page's Try AirPlay button using
   AXPress. Return to the app after inspection and read the logged controls.
5. Enter the exact displayed Mac and TV labels, including capitalization.
   The default “This Computer” is only a placeholder assumption. Close an open
   picker before starting the next action if it did not dismiss automatically.
6. Stop any Audio-tab capture, then click **Test TV → Mac → TV**. Avoid typing
   or changing apps during the test. It requires a selected-state signal for
   the TV, starts the native audio tap and its ten-second mute, selects Mac,
   waits three seconds, reopens the picker, confirms Mac is selected, and
   requests the TV. Normal completion or failure stops the tap and restores
   local sound. Physical TV picture/sound must still be verified by the viewer.
7. **Cancel** prevents subsequent routing steps and stops the owned tap. An AX
   call already sent can finish. It does not automatically restore a TV route.
   **Select TV / recover** is a separate explicit request for that purpose.

The scan reads the main Safari window and nonstandard Safari popup windows.
Destination controls must be in picker-like containers, outside page content,
and support AXPress. Missing, disabled, duplicate or truncated matches stop the
test. Different picker structures or an out-of-process picker require follow-up
implementation based on real diagnostics; the code never falls back to screen
coordinates, synthetic keyboard shortcuts, or selecting a vaguely similar name.
Focus is checked before each press. No microphone or commercial classifier is
implemented, and this is not yet background automation.

Logs save as `routing-<UUID>.log` in the diagnostics folder below. They contain
recognized picker control labels/roles/state and routing events, not page text,
URLs or an entire Accessibility tree. The source labels used for route selection
are not persistent device IDs. The native app needs Accessibility consent after
signing changes if macOS invalidates the prior grant.

Selection checks:

```sh
xcrun swiftc -module-cache-path /tmp/skybox-module-cache \
  MacAudioProbe/AirPlayRouteChoice.swift Tests/airplay-routing/main.swift \
  -o /tmp/skybox-routing-tests
/tmp/skybox-routing-tests
```

These cover exact and trimmed matching, case sensitivity, disabled destinations,
empty/missing names, duplicate matches, and an empty picker. They do not simulate
Safari's actual Accessibility tree or prove that a press changes the route.

`SkyboxAudioProbe` is a macOS target in the existing `SkyboxProbe.xcodeproj`.
It has independent Audio and Video tabs. Requires macOS 14.2 or newer.
The native build and arithmetic checks pass. Local DIRECTV audio capture and
mute-while-capturing were verified on September 20, 2026. Native AirPlay audio
capture and tap-based TV muting failed in the subsequent test.

## Observed results — September 20, 2026

- Local Safari DIRECTV: 3,258,368 samples, nonzero audio in all 34 measurement
  intervals, including 12 intervals labeled with the mute request active.
  Nick confirmed DIRECTV was the only audio source and sound went quiet while
  the meter continued moving. The tap restored output and stopped without errors.
- Native Safari AirPlay: 3,248,128 samples across 34 intervals, all zero,
  including the mute-test intervals. Nick reported that TV sound did not mute.
  The callback was running, so this was not simply failure to start capture.
  These results support receiver-side playback bypassing the Mac audio mix;
  the experiment does not directly inspect the receiver's playback pipeline.
- Video: Nick reported that video went black again. The saved session contains
  40 complete frames, but its retained first/latest images show a blank area
  and the probe window, not DIRECTV's player. Those files do not independently
  establish the cause or whether the intended source was selected.

Audio evidence files in the diagnostics directory:
`probe-1789948259-CA7C642B-D77F-40E4-B2D9-FF4110F4BC3D.jsonl` (local) and
`probe-1789948446-8EB11F83-3EAE-4B58-B679-6795108C6237.jsonl` (AirPlay).

## Build and open

Select the **SkyboxAudioProbe** scheme and **My Mac** in Xcode, then Run.
Alternatively, from the project root on Nick's Mac:

```sh
DEVELOPER_DIR=/Users/nickhavens/Downloads/Xcode.app/Contents/Developer \
  xcodebuild -project SkyboxProbe.xcodeproj -scheme SkyboxAudioProbe \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/mac-audio build
open build/mac-audio/Build/Products/Debug/SkyboxAudioProbe.app
```

The development target uses Apple Development signing. No extra dependencies or audio
drivers are installed. Audio capture requires macOS system-audio recording
consent; video uses the system content-sharing picker. If audio permission is
denied, enable the app in System Settings → Privacy & Security → Screen &
System Audio Recording, quit/reopen the probe, and retry.

## Audio test

1. Disconnect native AirPlay. Pause other audio-producing apps and tabs.
2. Play ordinary, unprotected audio. In Audio, select **Unprotected control**
   and click **Start capture**. Accept macOS's audio recording prompt.
3. Wait five seconds. Require **Nonzero system audio received**, changing
   peak/RMS values, and increasing sample counts. Zero samples or all-zero
   samples are distinct inconclusive results, not proof of DRM blocking.
4. Click **Mute Mac audio for 10s**. Confirm the sound actually becomes quiet
   while nonzero measurements continue. It restores output after ten seconds;
   **Restore output now** and **Stop** also end the mute test. This affects
   all captured Mac playback audio, not just Safari.
5. Stop. Pause the control source, play DIRECTV locally in Safari, select
   **DIRECTV · Safari local**, and repeat steps 2–4.
6. Only after local success, stop, activate native AirPlay, select the AirPlay
   test label, and repeat. Mac audio access during native AirPlay is unproven.
7. Check stop/restart and closing the app during the mute test. Output should
   return. Capture automatically ends after three minutes.

The label is diagnostic metadata, not a process filter. This deliberately taps
all system playback so Safari's separate WebKit processes are included.
No microphone input, raw audio file, upload, or commercial classifier is used.

## Video test

1. Open Video → **Choose window**. Select an ordinary window in the macOS
   sharing picker. Move or scroll its content; require corresponding changes
   in the preview. The first and latest complete frames save as JPEGs.
2. Stop, select the Safari DIRECTV window, and repeat with local playback.
   Inspect the broadcast area itself: captured controls around a black player
   do not establish access to protected video.
3. Repeat with **Choose display** if the window test fails. Avoid selecting
   the probe itself; keep its preview off the selected display where possible.
4. Cancel the picker once and reopen it. Test stopping and starting a second
   capture. Each stream automatically ends after two minutes.

The preview updates at up to one frame per second. Static content may produce
no new complete frames; the last-frame timestamp prevents mistaking a stale
preview for fresh capture. Audio is disabled on the video stream so the two
experiments remain independent. Native capture does not guarantee access to
protected video.

## Saved diagnostics

Files save automatically in:

```text
~/Library/Application Support/SkyboxAudioProbe/
```

- `probe-<timestamp>-<UUID>.jsonl`: timestamped startup, level measurements,
  mute requests, and stop/error events. No raw audio. `mutedRequested` reports
  the tap setting; the listener must confirm that physical output is quiet.
- `video-<UUID>/first.jpg`, `latest.jpg`, `status.json`: two captured images
  and frame count/timestamp/status. The latest image is replaced atomically.

Codex can read these paths directly. No Safari export or copy/paste is needed.
Diagnostic files persist across launches; each run gets a distinct filename.

## Verification

```sh
xcrun swiftc -module-cache-path /tmp/skybox-module-cache \
  MacAudioProbe/AudioLevels.swift Tests/mac-audio/main.swift \
  -o /tmp/skybox-audio-tests
/tmp/skybox-audio-tests
```

Checks cover peak/RMS, silence versus missing data, nonfinite input, clipping,
large finite samples, and accumulation across samples. Hardware/TCC and capture
permissions are tested through the actual app, not mocked success.

The tap uses a private, tap-only aggregate device and native Float32 PCM.
The audio callback accumulates scalar measurements on a serial queue without
retaining samples; the UI reads them once per second. Teardown requests unmute,
stops I/O, removes the callback, and destroys the aggregate and tap, reporting
cleanup errors. `mutedWhenTapped` ties output suppression to active tap reads.

References: [Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps),
[ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).
