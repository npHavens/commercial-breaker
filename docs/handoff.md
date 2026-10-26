# Commercial Breaker handoff to Claude — October 26, 2026

## Start here

Repo: https://github.com/npHavens/commercial-breaker (public, MIT, No Hands Stack LLC;
renamed from `skybox` on October 26, and the old URLs redirect).
Local checkout: `/Users/nickhavens/Projects/skybox`.
Baseline PR #1 merged into main on October 18 (20e5b4e); Codex reviewed the
final commit with no findings. Start focused branches from updated main. Read
README, CONTRIBUTING and `docs/roadmap.md`. Project notes: https://app.notion.com/p/3e04004d3caa810b915fc3f95af2235b.

Nick wants a fun open-source community project with sound engineering, branches,
reviews and understandable structure. Early development, not production. Learning
mode is OFF for this task; take over implementation. Do not disrupt active playback,
restart the app, reload Safari, or remove local experiment data during cleanup.
Do not spawn agents unless requested. Keep changes focused and reviewable.

## Current checkpoint

- Main is at d079dec with PRs #1–#7 merged. The Skybox → Commercial Breaker
  rename (plan PR #6, code PR #7) is in, apart from the Xcode target and product
  name, which wait for phase 4 (see Commands).
- Native v0.2.46 (two tabs: Automatic and AirPlay) built from d079dec, signed and
  running. Build path:
  `build/mac-audio-oct26-rename/Build/Products/Debug/SkyboxAudioProbe.app`.
  On October 26 Nick ran it on a recorded DIRECTV game. The support folder
  migrated, macOS did not re-prompt for microphone, system audio or
  Accessibility, and an AirPlay break moved to the Mac and returned to TV.
- The return to TV fails when another app, usually VS Code, is frontmost: see
  Remaining issues. Keep Safari in front during AirPlay tests.
- Source Safari extension v0.2.21. Packaged automatic attachment/reload lifecycle
  still lacks explicit live verification. The short DIRECTV handoff rewind was
  accepted earlier; it was not separately confirmed in the October 26 test.
- Codex automatic reviews run on every PR (Smart detect). Recheck GitHub before
  merging.
- Offline suites on d079dec (October 26): 172 JavaScript tests, 37 Python tests and
  all 12 native tests (`Tests/run-native-tests.sh`) passed. No new audio was uploaded.

## Behavior and important code

`AutomaticCommercialModel.swift` coordinates routing/capture, and
`AutomaticCommercialPolicy.swift` guards transitions. TV mode uses microphone
capture, then moves a confirmed break to Mac before creating a muted system tap.
On confirmed program return it releases the tap, starts the microphone BEFORE
requesting TV, then resets classifier context. Preserve that ordering.

Mac playback mode stays local, uses system capture, and mutes/unmutes without
requiring Safari focus. The current tap captures/mutes ALL Mac audio. Other apps
can affect detection; isolation is not implemented. Both modes release mute after
three minutes and continue detection. AirPlay waits for confirmed program before
returning TV; local mode waits for program before rearming for another break.

`RoutingModel.verifyTVForAutomation` retries once only when a startup focus failure
returns to this Commercial Breaker process and it remains foreground after a short wait.
Startup verifies an already-selected TV and does not choose a destination. Normal
handoffs still stop on focus loss. Missing picker rows before selection have a
separate bounded retry policy; never treat an unknown post-selection result as
safe to repeat.

`Tools/gemini-live-worker.mjs` uses Gemini 3.8 Flash at thinking level `LOW`
(October 25: Commercial Breaker moved to Vertex project `nhs-commercial-breaker`, where 2.5
Flash is unavailable). In the first live session that day Nick found it working
well enough: 1.68 s median, no thinking tokens, one 20 s timeout in nine requests.
Break and return accuracy has not been measured. `Tools/evaluate-gemini-audio.mjs` remains
the 2.5-only saved-clip experiment and needs a project with 2.5 access. Football prompt:
`Tools/minimal-classifier.mjs` (crowd-minimal-v2); uncertain intelligible content
is classified best-effort rather than routinely unclear. Exact digital silence
is rejected locally, not treated as program or commercial. Eight-second samples,
last five seconds decisive, normally five-second cadence, one request in flight.
Program return confirmation requires two positives spanning fresh audio.

`SafariExtension/directv-airplay-recovery.js` corrects a handoff timeline mismatch
with a guarded seek; preserve its autoload and safety checks. See
`Experiments/airplay-return-oct4.md` for investigation and evidence (historical: its stop
command `skyboxDirectvRecovery.stop()` is now `commercialBreakerDirectvRecovery.stop()`).

## Next work

1. Done: PR #1 merged after Codex review.
2. Done: PR #2 made setup standalone (v0.2.45, live-verified). Commercial Breaker reads
   Vertex settings from its own ignored `.env`; never copy secrets into this
   public repository.
3. Done: PR #3 moved runtime prompts and helpers out of evaluation code and
   `Experiments/` into `Tools/`, with prompt hashes unchanged and a boundary test.
4. Done: PR #4 moved detection to Gemini 3.8 Flash; PR #5 (phase 2, v0.2.46)
   removed tvOS/PiP, the Audio, Video and Recorder tabs, markers, clip store and
   cue detector.
5. Done: PRs #6 and #7 renamed Skybox to Commercial Breaker, live-verified
   October 26.
6. Next, phase 3 of `docs/commercial-breaker-plan.md`: trim the Safari extension
   (keep DIRECTV recovery, the AirPlay button and the Paramount+ relay). Phase 4
   renames the Xcode target and product, and adds the icon set from the
   Scoreboard CB design in Figma. Moving experiment findings into `docs/archive`
   is its own PR.

Do not combine all of this into one rewrite.

## Remaining issues / limits

- Sports betting ads can cause false program returns. Future commercial learning
  should avoid manual labeling burden. No fingerprint library implemented.
- ViewingActivity refresh exists, but screen saver/lock prevention is not proven.
- Earlier all-zero system capture stalled TV return; no verified root-cause fix.
  Recent success does not erase that intermittent observation.
- Cost is not the current constraint: Nick reports Gemini usage costs only a few
  dollars. Prioritize accuracy/speed; retain one in-flight request for freshness.
- Paramount/UFC relay workflow is preserved but not newly validated this session.
- AirPlay handoffs need Safari frontmost. When another app is in front, macOS
  refuses cooperative activation, the Accessibility fallback takes keyboard focus,
  and the focus guard stops once that app regains focus, leaving playback on the
  Mac. With VS Code frontmost, 7 of 9 logged handoffs failed (October 4, 11 and
  26); all 5 with Chrome or Notion frontmost succeeded. When the Accessibility
  press does not open the picker, the fallback mouse click also moves the pointer.
  Low-priority fix in the backlog: keep automatic mode running, offer a one-click
  "Back to TV" from a notification or the menu bar item (activating Commercial
  Breaker makes cooperative activation succeed), then refocus the previous app.

## Local evidence and repository hygiene

Logs/recordings: `~/Library/Application Support/CommercialBreaker/`. The app moves the old
`SkyboxAudioProbe/` folder there on first launch if the new one does not exist; quit the old
app before the first launch of the rebuilt one, since a running old binary recreates the old folder.
Automatic logs are `automatic-*.jsonl`; routing logs `routing-*.log`; capture
sessions are under `recordings/`. Inspect narrow metadata; avoid exposing audio,
room voices, tokens or session URLs. Offline tests do not authorize new uploads.

There are intentional untracked `.vscode/`, audio-cue/evaluation results and live
artifacts under Experiments. They are not part of the public history. Do not
`git add .`, `git clean`, or delete them blindly. Build output and stream URL files
are ignored. Original main baseline is 2b07370; startup fix 4344491; community docs
ed3600d. This handoff is a subsequent documentation-only commit.

## Commands

The rename from Skybox to Commercial Breaker is in progress. Not yet migrated: the
`SkyboxProbe.xcodeproj`, the `SkyboxAudioProbe` target, scheme and `SkyboxAudioProbe.app`
product, the `/tmp/skybox-*` test paths and the local checkout directory. Move the checkout
with phase 4's rebuild, because a built app runs `Tools/` from the path it was built in.

The `com.nohandsstack.skybox.*` bundle IDs and the `com.nohandsstack.skybox.audio-meter`
queue label keep `skybox` permanently: macOS ties Nick's microphone, system-audio and
Accessibility grants to the bundle ID, so they must never be renamed. Six System Settings
instructions still name the old app until the target and product rename in phase 4, because
that is the name System Settings lists: `SafariAccessibility.swift` x3, `RoutingModel.swift` x2,
`MicrophoneInput.swift` x1.

### After pulling the rename

Nick runs the app from this checkout. Pulling changes `Tools/` immediately but Swift only
after a rebuild; an old binary's worker start fails with `app-rebuild-required` (old builds
show it as "see Gemini setup in the README").

1. Pull only when no detection session is running.
2. Rebuild to a NEW derived-data path (the build command is in the README).
3. Quit the old app, launch the new one, and confirm the history now lives in
   `~/Library/Application Support/CommercialBreaker/`.
4. Reload the temporary Safari extension, re-grant site access if Safari asks, and refresh
   any open DIRECTV, Paramount+ and relay tabs. An old DIRECTV recovery instance keeps
   running beside the new one until the page is refreshed.
5. Verified October 26: a DIRECTV AirPlay break/return with Safari in front, and no
   re-prompt for microphone, system audio or Accessibility.

```sh
node --test Tests/gemini-audio/*.test.mjs Tests/safari/*.test.cjs
python3 -m unittest discover -s Tests -p 'test_*.py'
xcrun swiftc -module-cache-path /tmp/skybox-swift-module-cache \
  MacAudioProbe/GeminiConfirmation.swift MacAudioProbe/AutomaticCommercialPolicy.swift \
  Tests/automatic-commercial-policy/main.swift -o /tmp/skybox-policy-tests
/tmp/skybox-policy-tests
```

Local Xcode is `/Users/nickhavens/Downloads/Xcode.app`. Use scheme
`SkyboxAudioProbe` and a NEW derivedDataPath to avoid altering the running bundle.
A build can be done separately; launch/restart only when Nick's playback permits.
