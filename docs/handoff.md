# Commercial Breaker handoff to Claude — November 8, 2026

## Start here

Repo: https://github.com/npHavens/commercial-breaker (public, MIT, No Hands Stack LLC;
renamed from `skybox` on October 26, and the old URLs redirect).
Local checkout: `/Users/nickhavens/Projects/commercial-breaker` (moved from `skybox` on November 7).
Baseline PR #1 merged into main on October 18 (20e5b4e); Codex reviewed the
final commit with no findings. Start focused branches from updated main. Read
README, CONTRIBUTING and `docs/roadmap.md`. Project notes: https://app.notion.com/p/3e04004d3caa810b915fc3f95af2235b.

Nick wants a fun open-source community project with sound engineering, branches,
reviews and understandable structure. Early development, not production. Learning
mode is OFF for this task; take over implementation. Do not disrupt active playback,
restart the app, reload Safari, or remove local experiment data during cleanup.
Do not spawn agents unless requested. Keep changes focused and reviewable.

## Current checkpoint

- PRs #1–#24 are merged. v0.2.50 (PR #24) adds the app icon, built unsigned in CI and
  not yet seen live; `Tools/app-icon/render.sh` makes it. The Skybox → Commercial Breaker
  rename (plan PR #6, code PR #7) is in; the Xcode project, target and app name
  follow in the v0.2.48 rename (see Commands).
- Native v0.2.48 built signed from cf46103 (the offline suites and all 12 native tests
  pass there) after the rename, at
  `build/v0.2.48/Build/Products/Debug/Commercial Breaker.app`, with the same bundle
  ID and designated requirement as before. On November 8 Nick watched football with
  it for 36 minutes with no permission prompt reported. Accessibility and microphone
  grants worked (routing read Safari's picker; detection ran); worker-ready logged
  `gemini-3.7-flash`, 347 predictions at a 2.3 s median, and 10 failures (7 timeouts)
  in one burst early on, all recovered. Not yet checked: the system-audio grant,
  which a Mac playback start or a break exercises, a break/return cycle, and System
  Settings listing Commercial Breaker.
  The title-version change after cf46103 has not run live.
- v0.2.51 (PR #25) keeps detection running through up to five minutes of Gemini
  timeouts instead of stopping at the third failure in a row, which happened 11 times
  since October 27. In AirPlay mode a break still returns to the TV after a minute of
  failures (see the v0.2.51 changelog). Not yet run live.
- v0.2.47 (`build/v0.2.47/…/SkyboxAudioProbe.app`) is the fallback build until v0.2.48
  completes a break/return cycle.
- The previous v0.2.46 build (from d079dec, `build/mac-audio-oct26-rename/`) was
  verified on October 26: Nick ran it on a recorded DIRECTV game. The support folder
  migrated, macOS did not re-prompt for microphone, system audio or
  Accessibility, and an AirPlay break moved to the Mac and returned to TV.
- The return to TV fails when another app, usually VS Code, is frontmost: see
  Remaining issues. Keep Safari in front during AirPlay tests.
- Source Safari extension v0.2.21. Packaged automatic attachment/reload lifecycle
  still lacks explicit live verification. The short DIRECTV handoff rewind was
  accepted earlier; it was not separately confirmed in the October 26 test.
- Every PR gets a Codex review (Smart detect) and the offline suites plus an unsigned
  app build in CI (`.github/workflows/tests.yml`). Same-repo PRs also get a Claude
  review running `/code-review high` (`.github/workflows/claude-review-reusable.yml`, called by
  `claude-review.yml`; other repos call it at `@main`) when they
  open or are marked ready; fork PRs never do. To review later pushes, mark the PR draft,
  then ready. A comment starting `@claude review` also starts a review, but it reports on the
  default branch's commit, not the required check on the PR's head. Here, that run uses main's
  caller and so main's reusable workflow. In other repos, the caller that runs picks the version:
  once switched, main's caller uses `@main`. Review comments come from `github-actions[bot]`.
  `main` requires a PR, passing CI and `claude-review / review`, blocks force pushes and deletion,
  and applies those rules to admins. The merge gate is in `AGENTS.md`.
- Offline suites on cf46103 (November 8): 172 JavaScript tests, 37 Python tests and
  all 12 native tests (`Tests/run-native-tests.sh`) passed. The identity test added
  after it brought the Python suite to 41, the review workflow tests to 64, and PR #24's
  icon and identity tests to 70 Python tests in total; CI runs it on pull requests and pushes to main. No new audio was uploaded.

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

`Tools/gemini-live-worker.mjs` uses Gemini 3.7 Flash at thinking level `LOW`
(October 25: Commercial Breaker moved to Vertex project `nhs-commercial-breaker`, where 2.5
Flash is unavailable). 3.8 Flash came first and worked well on October 25 (1.68 s
median, one 20 s timeout in nine requests), but on October 26 and November 1 its
latency swung up to 15 s, and on November 1 5 of about 25 live requests timed out. 3.7 Flash
answered in 2.1–3.6 s in a side-by-side probe on November 1, then had 14 of 14 live
requests succeed (2.4 s median), so Nick chose to keep it. Break and return accuracy
has not been measured on either, and whether 3.7 offers a level below `LOW` is
unchecked (see Next work). The worker picks up the switch on the next pull, but a
v0.2.46 build still logs `gemini-3.8-flash` in its enabled event and no model on
worker-ready. Rebuild (v0.2.47) before comparing sessions; its worker-ready event
carries `model`. `Tools/evaluate-gemini-audio.mjs` remains
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
   October 26. PRs #8–#10 added the code review rules and Claude review, #11 added
   CI, #12 switched detection to Gemini 3.7 Flash (v0.2.47), and #13 moved the
   Claude review to `/code-review high`.
6. Next, phase 3 of `docs/commercial-breaker-plan.md`: trim the Safari extension
   (keep DIRECTV recovery, the AirPlay button and the Paramount+ relay). Phase 4
   builds the app shell and adds the rest of the icon set from the
   Scoreboard CB design in Figma: the static app icon is in v0.2.50, while the
   runtime Dock state, menu bar glyph and Safari toolbar icons are still to come.
   Moving experiment findings into `docs/archive`
   is its own PR.

7. Check whether Gemini 3.7 Flash supports a thinking level below `LOW`. If it
   does, trying it changes live latency and accuracy, so measure it live.
8. Deferred from PR #12: the worker and `Tools/compare-detection.mjs` each build
   their own `generateContent` config from `REQUEST`; export one builder from
   `Tools/gemini-live-worker.mjs` and use it in both. Also export the worker's
   `safeUsage` to replace compare-detection's copy, and show `REQUEST` in its dry run.
9. Confirm `Read(//proc/**)` also stops `Grep` on a runner. Project skills under
   `--setting-sources user` are untested too.
10. Restore-step limits left from PR #17: it matches file names by hand and repeats the list in
   two `find` commands, does not check for symlinked parent folders or differently cased names,
   and recreates folders a PR deleted. Reading rules from a kept `.review-base` would remove
   the name list.
11. Switch the other three repos to `@main`: copy CB's `claude-review.yml` except its `uses:` line,
   which becomes the `@main` path in its header, and show a successful live run in each. After
   each switch merges, confirm the comment path with a real `@claude review` comment there,
   because comment runs on the switch PR still use the old pin. The
   No Hands Stack HQ session coordinates this. On November 8 each repo's run log showed its
   own repo checked out for the rules restore; none of those PRs tampered with a rules file,
   so that case was only tested locally. Severity labels were still missing in some of those
   repos before PR #21, so check whether its user-level `CLAUDE.md` rule fixed them.

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

Since v0.2.48 the project is `CommercialBreaker.xcodeproj` with one `CommercialBreaker`
target and scheme, building `Commercial Breaker.app`. Not renamed: the `MacAudioProbe/`
source folder and `MacAudioProbe-Info.plist`. The checkout moved on November 7 with the v0.2.47
rebuild. A built app runs `Tools/` from the path it was built in, so any later move needs a rebuild.

The `com.nohandsstack.skybox.*` bundle IDs and the `com.nohandsstack.skybox.audio-meter`
queue label keep `skybox` permanently: macOS ties Nick's microphone, system-audio and
Accessibility grants to the bundle ID, so they must never be renamed. The app's System
Settings instructions name Commercial Breaker, the name System Settings lists since v0.2.48.

### After pulling the rename

Nick runs the app from this checkout. Pulling changes `Tools/` immediately but Swift only
after a rebuild; an old binary's worker start fails with `app-rebuild-required` (old builds
show it as "see Gemini setup in the README").

1. Pull only when no detection session is running.
2. Rebuild signed to a NEW derived-data path: the command under "Build and open" in
   `MacAudioProbe/README.md` with a fresh `-derivedDataPath`. The README's
   `CODE_SIGNING_ALLOWED=NO` command only checks compilation; an unsigned build loses
   the macOS permission grants.
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
Tests/run-native-tests.sh
```

### After the v0.2.48 app rename

The app file changes from `SkyboxAudioProbe.app` to `Commercial Breaker.app`. Its bundle ID
and designated requirement are unchanged. On November 8 two grants were shown to survive:
Accessibility (routing read Safari's picker at 18:41 UTC) and microphone (347 predictions).
System audio is unverified: starting a session in Mac playback mode, or a break in TV mode,
uses it. A break/return cycle and the System Settings name are also unchecked.
`Tests/test_app_identity.py` fails if the bundle ID, signing team, style or identity, the
sandbox or hardened-runtime setting or the product name changes, if an SDK-specific override
appears, if the two versions differ, or if entitlements are added. It cannot check the
signing certificate, whose name is part of the designated requirement: a build signed with a
different certificate loses the grants even with every one of these settings intact.

1. Quit the old app. Its process and menu are still named SkyboxAudioProbe, so it is easy to
   miss. Never run an old and a new build at once: they share a bundle ID, and both would
   try to capture and mute.
2. Launch `Commercial Breaker.app` from a NEW derived-data path and confirm there is no
   prompt for microphone, system audio or Accessibility.
3. System Settings may keep listing the grant as SkyboxAudioProbe while old builds remain on
   disk, because every build shares the bundle ID. That row is this app; do not add a
   second one. Keep the v0.2.47 build as the fallback until v0.2.48 is verified live;
   after that, Nick may delete the old `SkyboxAudioProbe.app` builds under `build/`
   (build output, not experiment data) so macOS only knows the new name.

Local Xcode is `/Users/nickhavens/Downloads/Xcode.app`. Use scheme
`CommercialBreaker` and a NEW derivedDataPath to avoid altering the running bundle.
A build can be done separately; launch/restart only when Nick's playback permits.
