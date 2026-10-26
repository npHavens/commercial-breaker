# Commercial Breaker app plan

Drafted October 18, 2026 for Nick's review. Once approved, this replaces roadmap
items 3–5 in [roadmap.md](roadmap.md). Each phase below becomes one or two
focused PRs with its own implementation plan, written when the phase starts.

## Why

Skybox works, but it is an experiment control panel: five tabs of probes and
tests, version numbers in titles, raw logs on the main screen, and setup spread
across Terminal, `.command` files and READMEs. Nick uses one thing: automatic
commercial muting while watching DIRECTV football, and occasionally Paramount+
UFC. The goal is an app someone can set up once and then use every game day
without knowing how it works inside.

The name was settled as Commercial Breaker on 2026-10-19, superseding the earlier
split of Skybox as the app and Commercial Breaker as its feature.

## What it becomes

**Commercial Breaker** is the app: it listens to the game, mutes confirmed
commercials, and brings the sound, or the TV, back when the game returns. It has
no separate feature-level brand.

- **Main window, status first.** One large Start/Stop button, the current state
  in plain words, where playback is (this Mac or the TV's name) and the sport.
  No raw predictions, histories, version numbers or test buttons.
- **Settings:** where you watch (This Mac or TV via AirPlay), which TV (picked
  from the AirPlay devices Commercial Breaker finds, not typed), and sport (Football or UFC).
- **Setup checklist:** shown on first run and whenever something is missing.
  Each item has a status and one fix action. Start stays disabled, with the
  reason shown, until the items needed for the chosen mode are ready.
- **Diagnostics window** (menu: Window › Diagnostics): event history, raw
  predictions and confirmation counts, routing history, picker inspection,
  Select TV / recover, open the logs folder, and opt-in diagnostic audio samples.

```
┌ Commercial Breaker ─────────────────────────────┐
│                                           ⚙︎     │
│                                                  │
│  ● Watching the game                             │
│    Living Room TV · Football                     │
│                                                  │
│          [  Stop Commercial Breaker  ]           │
│                                                  │
│  Last break 7:42 PM · muted 2 min 10 s           │
│  Audio samples go to Google Vertex AI            │
└──────────────────────────────────────────────────┘
```

States the user sees: Ready · Starting · Watching the game · Commercial, muted
(Mac) or Commercial, playing muted on this Mac (AirPlay) · Game's back,
returning to TV · Stopped · Needs attention (one sentence plus a fix).

## Keep and remove

Keep: Mac playback and TV-via-AirPlay modes; Gemini detection and the automatic
policy; the DIRECTV handoff correction and autoload; the extension's on-page
AirPlay button; the Paramount+ relay and UFC sport; routing recovery tools in
Diagnostics.

Remove (Nick, October 18): the tvOS prototype target, PiP test video and
generator; the Audio, Video, Recorder and AirPlay tabs as tabs; marker buttons
and marked-clip saving; the local cue detector; the extension's experiment
buttons and its manual and legacy automatic mute; evaluation-only tools whose
findings are already recorded. Findings move to `docs/archive`, not the bin.

## Constraints for every phase

- UI phases do not change detection or handoff behavior: same prompts (football
  `promptSHA256` 9ccb506e…), cadence, two-prediction confirmation, three-minute
  release, and AirPlay return ordering (release tap, start microphone, request
  TV, reset classifier context).
- Bundle identifier stays `com.nohandsstack.skybox.audio-probe`, so macOS keeps
  the microphone, system-audio and Accessibility permissions already granted.
  The identifier retains the `skybox` segment by design, while every name a
  person sees becomes Commercial Breaker: the app, target, scheme and window.
- Audio goes only to Vertex. Consent is a one-time acknowledgement before the
  first start, then a single always-visible line. TV mode states that nearby
  voices can be included.
- No audio is saved by default. Today system-audio legs keep up to six 8-second
  program samples; that becomes a Diagnostics opt-in.
- Each phase is a PR from updated main with offline tests, a Codex review, and
  a merge before the next phase starts. Live checks are Nick's, and nothing
  interrupts playback. Builds use a new derived-data path.

## Phases

### 1. Separate runtime code from experiments

Move `makeContents`, `parseResult` and `responseSchema` out of
`Tools/evaluate-gemini-audio.mjs`, and `prompt-common.txt` out of
`Experiments/`, into runtime modules under `Tools/`. Point the evaluation tools
at them.
**Done when:** every prompt hash (football/UFC × standard/return) is
byte-identical before and after, and the test suites pass. No native change.

### 2. Remove unused native features

Delete the tvOS target, `SkyboxProbe/`, the PiP generator, the Video and Audio
probes (`VideoProbe`, `ProbeModel`, and the routing round-trip test that depends
on it), the Recorder tab, markers, `AudioClipStore`, `LiveAudioCues` and
`BreakCueDetector`, with their tests and tools. The AirPlay tab stays, minus the
round-trip test, until phase 4 moves its TV setting and recovery tools. Before
deleting each item, confirm Commercial Breaker does not reach it: for example,
Gemini's audio buffer must not depend on the clip store's ingest path.
**Done when:** the app builds with one target, the remaining native and JS
suites pass, and Nick completes one Mac-mode and one AirPlay break/return cycle.

### 3. Trim the Safari extension

Reduce the popup to page status, Show AirPlay button, and the Paramount+ relay
section. Remove the probe scripts, recording export, screen test and both popup
mute toggles. Keep `directv-airplay-recovery.js`, `directv-autoload.js`,
`airplay-session.js` and the relay files, with their regression tests. The relay
player still loads `commercial-controller.js`, and `hls_relay.py` imports
`commercial_timing.py`. Remove the relay's legacy automatic mute only where it
separates cleanly from playback, and keep whatever the relay still needs.
**Done when:** the extension tests pass and Nick completes one DIRECTV AirPlay
cycle with the trimmed extension, including the short handoff rewind.

### 4. Commercial Breaker app shell and branding

Build the main window, Settings and Diagnostics described above. Rename the app,
target and scheme to Commercial Breaker, add an app icon, and set the category to
Entertainment. Rewrite every user-facing string, including the microphone and
system-audio permission text, which still mention saving marked clips. Map
`AutomaticCommercialModel` state onto the user-visible states above.
**Done when:** a view-state test covers each state, Diagnostics still offers
picker inspection and recovery, and Nick watches one full game half using only
the main window.

### 5. Guided setup

Build the setup checklist with live checks: microphone, system-audio capture,
Accessibility, Node 24, `npm ci`, `.env` project, Application Default
Credentials, Safari extension reachable, and TV chosen. The worker gains a
check mode that validates configuration and credentials, including a token
fetch, and then exits without sending audio. Missing credentials then surface
in setup instead of at the first request. Add a "Test the TV handoff" button
that uses the same routing calls as Commercial Breaker.
**Done when:** each check has a failing and a passing test, and a fresh clone on
a second macOS user account reaches Ready by following only the checklist.

### 6. Packaged Safari extension

Package the extension as a Safari Web Extension target inside Commercial Breaker, so it is
turned on once in Safari Settings and survives Safari restarts. Temporary
extensions do not. Rename it Commercial Breaker.
**Done when:** after quitting and reopening Safari, a DIRECTV page attaches
automatically and the handoff correction works. This closes the outstanding
packaged autoload/reload check.

### 7. Paramount+ relay without Terminal

Commercial Breaker starts and stops the relay helper itself and shows the pairing
code, which replaces both `.command` launchers. Capture, validation and memory-only
credential handling stay as they are.
**Done when:** the relay tests pass and Nick completes one Paramount+ UFC
break/return cycle without opening Terminal.

## Later, not planned yet

A menu bar status item for Mac mode while working in other apps; the
TypeScript/React extension migration; Node from Homebrew; app-specific muting
(audio isolation); and handling sports-betting ads, which cause false returns.

## Calls I made (veto any)

- Phases 2 and 3 remove before phase 4 rebuilds, so the new UI is designed
  around only what survives.
- Diagnostics stays in the app, as a separate window, rather than being
  deleted, because routing recovery tools still help on bad nights.
- Decided 2026-10-19: the product is renamed to Commercial Breaker across the
  board, the bundle identifier excepted, which is not renamed so the permissions
  already granted are kept.
- The app icon starts as a simple placeholder I make, replaceable with real art.
- Sport stays a setting rather than being detected automatically.
