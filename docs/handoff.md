# Commercial Breaker handoff to Claude — October 18, 2026

## Start here

Repo: https://github.com/npHavens/skybox (public, MIT, No Hands Stack LLC).
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

- Native v0.2.46 on `chore/remove-unused-native` removes unused features (two
  tabs remain: Automatic and AirPlay); live break/return cycles pending.
- Native v0.2.45 built, signed and running. Build path:
  `build/mac-audio-oct18-standalone/Build/Products/Debug/SkyboxAudioProbe.app`.
  Nick started a live session on October 18: worker ready in about a second,
  unchanged football prompt hash, predictions and a confirmed break normal.
- Nick reports AirPlay working well and confirmed the v0.2.44 startup fix and
  Mac playback. He did not separately confirm every cancellation, timeout or
  focus edge case.
- Source Safari extension v0.2.21. Packaged automatic attachment/reload lifecycle
  still lacks explicit live verification. Short DIRECTV handoff rewind accepted.
- Codex automatic reviews run on every PR (Smart detect). PRs #1 and #2 merged
  after reviews with no findings. Recheck GitHub before merging.
- Latest offline suites: 142 JavaScript tests, 37 Python tests and all 11
  native tests (`Tests/run-native-tests.sh`) passed. No new audio was uploaded.

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
`Experiments/airplay-return-oct4.md` for investigation and evidence.

## Next work

1. Done: PR #1 merged after Codex review.
2. Done: PR #2 made setup standalone (v0.2.45, live-verified). Commercial Breaker reads
   Vertex settings from its own ignored `.env`; never copy secrets into this
   public repository.
3. Done on `chore/separate-runtime-code`: runtime prompts and helpers moved out
   of evaluation code and `Experiments/` into `Tools/`, with prompt hashes
   unchanged and a boundary test.
4. In review on `chore/remove-unused-native` (v0.2.46): tvOS/PiP, the Audio,
   Video and Recorder tabs, markers, clip store and cue detector are removed;
   the AirPlay tab keeps the TV setting and recovery tools. Needs one Mac-mode
   and one AirPlay cycle from Nick before merging.
5. Next, per the technical cleanup plan in Nick's Notion project notes: trim the
   Safari extension (keep DIRECTV recovery, the AirPlay button and the
   Paramount+ relay), then move experiment findings into `docs/archive`.
   Release work (branded UI, guided setup, packaged extension) is deferred;
   brand and UI design is happening separately in Figma.

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
`SkyboxProbe.xcodeproj`, the `SkyboxAudioProbe` target and scheme, the
`/tmp/skybox-*` test paths, the GitHub repo URL and the local checkout directory.

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
The `SkyboxProbe` scheme is the historical tvOS app. A build can be done separately;
launch/restart only when Nick's playback permits.
