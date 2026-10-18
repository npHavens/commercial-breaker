# Skybox handoff to Claude — October 18, 2026

## Start here

Repo: https://github.com/npHavens/skybox (public, MIT, No Hands Stack LLC).
Local checkout: `/Users/nickhavens/Projects/skybox`.
Branch: `experiment/crowd-detection`; baseline PR: https://github.com/npHavens/skybox/pull/1.
Main still contains the older baseline until PR #1 is merged. Do not start from
main assuming the current behavior is there. Read README, CONTRIBUTING and
`docs/roadmap.md`. Project notes: https://app.notion.com/p/3e04004d3caa810b915fc3f95af2235b.

Nick wants a fun open-source community project with sound engineering, branches,
reviews and understandable structure. Early development, not production. Learning
mode is OFF for this task; take over implementation. Do not disrupt active playback,
restart the app, reload Safari, or remove local experiment data during cleanup.
Do not spawn agents unless requested. Keep changes focused and reviewable.

## Current checkpoint

- Native v0.2.44 built, signed and launched. Running build path:
  `build/mac-audio-oct18-startup/Build/Products/Debug/SkyboxAudioProbe.app`.
- Nick reports AirPlay working well. He just confirmed BOTH the startup fix and
  Mac playback working. This supersedes earlier pending-live-check statements.
  He did not separately confirm every cancellation/timeout/focus edge case.
- Source Safari extension v0.2.21. Packaged automatic attachment/reload lifecycle
  still lacks explicit live verification. Short DIRECTV handoff rewind accepted.
- Codex automatic reviews enabled, following personal preferences (Smart detect).
  A manual `@codex review` was posted on PR #1; bot acknowledged with eyes.
  No submitted review/findings existed when this handoff was prepared. Recheck
  GitHub before merging or changing reviewed code. PR is being marked ready;
  it is not merged as part of this handoff.
- Native signed build and automatic-policy tests passed. Latest offline suites:
  135 JavaScript tests and 37 Python tests passed. Python HTTP tests needed
  loopback networking outside the sandbox. No new audio was uploaded for these.

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
returns to this Skybox process and it remains foreground after a short wait.
Startup verifies an already-selected TV and does not choose a destination. Normal
handoffs still stop on focus loss. Missing picker rows before selection have a
separate bounded retry policy; never treat an unknown post-selection result as
safe to repeat.

`Tools/gemini-live-worker.mjs` uses Gemini 2.5 Flash. Football prompt:
`Tools/minimal-classifier.mjs` (crowd-minimal-v2); uncertain intelligible content
is classified best-effort rather than routinely unclear. Exact digital silence
is rejected locally, not treated as program or commercial. Eight-second samples,
last five seconds decisive, normally five-second cadence, one request in flight.
Program return confirmation requires two positives spanning fresh audio.

`SafariExtension/directv-airplay-recovery.js` corrects a handoff timeline mismatch
with a guarded seek; preserve its autoload and safety checks. See
`Experiments/airplay-return-oct4.md` for investigation and evidence.

## Next work

1. Review PR #1 and Codex feedback, then merge after review. Start subsequent
   focused branches from updated main; do not silently merge an unreviewed PR.
2. Remove the sibling Interview Assistant dependency. Native
   `GeminiObservation.makeWorker` expects Node 24 under nvm and loads its tsx,
   `.env` and SDK/config from `~/Projects/interview-assistant/app`. The JS worker
   imports that project's Vertex resolver. Declare Skybox's own dependencies and
   configuration; verify a fresh clone can run detection without the other repo.
   Never copy secrets into this public repository.
3. Separate runtime prompts/helpers from evaluation code BEFORE removing old
   experiments. The worker still imports `evaluate-gemini-audio.mjs`, and UFC
   still reads `Experiments/audio-model-eval/prompt-common.txt`.
4. Remove obsolete tvOS/PiP target and unused probe UI in a separate audited PR;
   preserve useful regression tests/findings. Then migrate extension logic to
   TypeScript and popup to React with behavior parity.

See roadmap for acceptance checks. Do not combine all of this into one rewrite.

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

Logs/recordings: `~/Library/Application Support/SkyboxAudioProbe/`.
Automatic logs are `automatic-*.jsonl`; routing logs `routing-*.log`; capture
sessions are under `recordings/`. Inspect narrow metadata; avoid exposing audio,
room voices, tokens or session URLs. Offline tests do not authorize new uploads.

There are intentional untracked `.vscode/`, audio-cue/evaluation results and live
artifacts under Experiments. They are not part of the public history. Do not
`git add .`, `git clean`, or delete them blindly. Build output and stream URL files
are ignored. Original main baseline is 2b07370; startup fix 4344491; community docs
ed3600d. This handoff is a subsequent documentation-only commit.

## Commands

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
