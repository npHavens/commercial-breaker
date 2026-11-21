# Commercial Breaker handoff to Claude — November 15, 2026

## Start here

Repo: https://github.com/npHavens/commercial-breaker (public, MIT, No Hands Stack LLC;
renamed from `skybox` on October 26, and the old URLs redirect).
Local checkout: `/Users/nickhavens/Projects/commercial-breaker` (moved from `skybox` on November 7).
Baseline PR #1 merged into main on October 18 (6cd427c); Codex reviewed the
final commit with no findings. Start focused branches from updated main. Read
README, CONTRIBUTING and `docs/roadmap.md`. Project notes: https://app.notion.com/p/3e04004d3caa810b915fc3f95af2235b.

Nick wants a fun open-source community project with sound engineering, branches,
reviews and understandable structure. Early development, not production. Learning
mode is OFF for this task; take over implementation. Do not disrupt active playback,
restart the app, reload Safari, or remove local experiment data during cleanup.
Do not spawn agents unless requested. Keep changes focused and reviewable.

## Current checkpoint

- On November 15 main's history was rewritten to remove references to other local
  projects, and every commit SHA changed: the old main head e652806 is now 2c3280c. The
  final tree did not change. SHAs in older PR threads, review comments and notes refer to
  the old history; this file cites the new ones. The old-to-new map is in Nick's checkout
  at `.git/history-rewrite-2026-11-15-commit-map.txt`. Every other branch on GitHub was
  deleted, but GitHub keeps the refs of PRs #1–#30, so old-history commits stay reachable by
  SHA and through those PRs' Commits and Files tabs; Nick chose not to request a GitHub
  Support purge. PR titles, descriptions and review comments that named the other projects
  were edited, but #2's timeline still shows its old title, which owners cannot remove.
- PRs #1–#30 are merged except #29, which was closed. v0.2.50 (PR #24) adds the app icon, which v0.2.51 carries into
  its November 14 live run; `Tools/app-icon/render.sh` makes it. The Skybox → Commercial Breaker
  rename (plan PR #6, code PR #7) is in; the Xcode project, target and app name
  follow in the v0.2.48 rename (see Commands).
- Native v0.2.48 built signed from 2125a21 (the offline suites and all 12 native tests
  pass there) after the rename, at
  `build/v0.2.48/Build/Products/Debug/Commercial Breaker.app`, with the same bundle
  ID and designated requirement as before. On November 8 Nick watched football with
  it for 36 minutes with no permission prompt reported. Accessibility and microphone
  grants worked (routing read Safari's picker; detection ran); worker-ready logged
  `gemini-3.7-flash`, 347 predictions at a 2.3 s median, and 10 failures (7 timeouts)
  in one burst early on, all recovered. Not yet checked: the system-audio grant,
  which a Mac playback start or a break exercises, a break/return cycle, and System
  Settings listing Commercial Breaker.
  The title-version change after 2125a21 ships in v0.2.51, which ran live on November 14.
- v0.2.51 (PR #25) keeps detection running through up to five minutes of Gemini
  timeouts instead of stopping at the third failure in a row, which happened 11 times
  since October 27. In AirPlay mode a break still returns to the TV at the third
  failed request with no Gemini answer in between (see the v0.2.51 changelog). Built signed
  from 8501e44 on November 14 at `build/v0.2.51/Build/Products/Debug/Commercial Breaker.app`,
  with the same designated requirement as v0.2.48; 172 JavaScript, 70 Python and 12 native
  tests pass there. On November 14 Nick watched UFC on Paramount+ through the manual
  relay with it in TV via AirPlay mode, using a wireless microphone in front of the TV
  speaker (00:41–02:47 UTC, two sessions). All 29 confirmed breaks moved to the Mac and 28
  returned on their own; 28 Gemini requests failed and none stopped detection; 1,278
  predictions at a 2.3 s median. No permission prompt; the system-audio grant worked.
  Issues: 17 of the second session's 23 breaks lasted under 45 seconds. The microphone
  side called walkout music and similar program audio commercial or promo, and the Mac
  side's system audio called it program within 15–30 seconds. One break stayed on the Mac
  for 23 minutes: its system capture was exact digital silence for 21 minutes (all 235
  answers local), so program never confirmed (see Remaining issues). Stop from the
  Commercial Breaker window then failed to return to TV (fixed in v0.2.52). Both handoffs
  with VS Code frontmost succeeded, through the mouse fallback.
- v0.2.52 retries startup and Stop's return to TV once when focus bounces back to Commercial
  Breaker before the selection (see its changelog). Not yet run live.
- v0.2.53 stops promos alone from confirming a break: on November 14 every promo-only
  break was in-broadcast UFC content (see its changelog for the log replay). Built signed
  from a8247a9 on November 15 at `build/v0.2.53/Build/Products/Debug/Commercial Breaker.app`,
  with the same designated requirement as v0.2.48; 172 JavaScript, 70 Python and 13 native
  tests pass there. It was built just before the rewrite, from 7f86b57, whose tree a8247a9 keeps.
  v0.2.53 has been in daily use since November 15, but its logs haven't been checked
  against the promo rule yet.
- v0.2.54 returns an AirPlay break to the TV after six silent answers in a row (about 30
  seconds) from the Mac's capture, through the same path as a confirmed program, and keeps
  the rest of that break on the TV until program is confirmed there (see its changelog). It
  limits a stall like November 14's, which left a break on the Mac for 23 minutes, to about
  30 seconds; the cause is still unknown. Built signed from 655dad3 on November 15 at
  `build/v0.2.54/Build/Products/Debug/Commercial Breaker.app`, with the same designated
  requirement as v0.2.53; 172 JavaScript, 47 Python and 13 native tests pass there. Not yet
  run live.
- v0.2.55 retries an incomplete Gemini answer instead of stopping detection (the third in a
  streak still stops), logs Gemini's finish or block reason, and records a stopped capture's own reason when a session
  stops on its own (see its changelog). Not yet built or run live.
- v0.2.51 (`build/v0.2.51/…/Commercial Breaker.app`), which completed 28 automatic
  break/return cycles on November 14, is the fallback build.
- The previous v0.2.46 build (from b1fa0aa, `build/mac-audio-oct26-rename/`) was
  verified on October 26: Nick ran it on a recorded DIRECTV game. The support folder
  migrated, macOS did not re-prompt for microphone, system audio or
  Accessibility, and an AirPlay break moved to the Mac and returned to TV.
- The return to TV fails when another app, usually VS Code, is frontmost: see
  Remaining issues. Keep Safari in front during AirPlay tests.
- Source Safari extension v0.2.21. Packaged automatic attachment/reload lifecycle
  still lacks explicit live verification. The short DIRECTV handoff rewind was
  accepted earlier; it was not separately confirmed in the October 26 test.
- PRs get a Codex review (Smart detect) when it runs. Since November 21 its findings count
  in the merge gate again; a run that is missing, stuck or stopped at its usage limit
  doesn't block a merge. Every PR gets the offline suites plus an unsigned
  app build in CI (`.github/workflows/tests.yml`). Same-repo PRs also get one Claude
  review running `/code-review high` when they open or are marked ready; fork PRs never do.
  Since November 15, `claude-review.yml` calls the shared `claude-review-reusable.yml` in the
  public npHavens/.github repo at `@main`, which also gives the reviewer that repo's
  `review/review-standard.md`. That repo doesn't review its own PRs. All four repos call it,
  so CB's own copy and its tests were removed; the "Review caller matches the shared copy"
  CI job checks that CB's caller is still an unchanged copy. A run that never reaches the model now reads "did not
  complete", not "finished" (npHavens/.github#3). When later pushes need a re-review is in the
  merge gate in `AGENTS.md`. A comment starting `@claude review` starts one; that run reports on the default branch's commit,
  not the PR's head, and uses main's caller. Review comments come from `github-actions[bot]`.
  `main` requires a PR and passing CI (`JavaScript and Python`, `Native build and tests`;
  `claude-review / review` stopped being required on November 14), blocks force pushes and deletion,
  and applies those rules to admins. For the November 15 rewrite, force pushes were allowed and
  admin enforcement was off for one push; both were restored right after it. The merge gate is
  in `AGENTS.md`.
- Offline suites on 2125a21 (November 8): 172 JavaScript tests, 37 Python tests and
  all 12 native tests (`Tests/run-native-tests.sh`) passed. The identity test added
  after it brought the Python suite to 41, the review workflow tests to 64, and PR #24's
  icon and identity tests to 70 Python tests in total; CI runs it on pull requests and pushes to main. No new audio was uploaded.
  On November 15 the 23 review workflow tests left with CB's copy of that workflow, leaving 47
  Python tests; npHavens/.github tests the shared workflow.

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

`RoutingModel.routeForAutomation(retryFocusBounce: true)`, used only by startup and Stop's
TV recovery, retries its pre-selection steps once when the route began with this Commercial
Breaker process frontmost, focus returned to it, and it remains foreground after a short
wait (`FocusBounceRetry`, v0.2.52). Handoffs still stop on any focus loss. Startup
verifies an already-selected TV and does not choose a destination. Missing picker rows before selection have a
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
9. For the shared workflow in npHavens/.github, coordinated by the No Hands Stack HQ
   session: confirm `Read(//proc/**)` also stops `Grep` on a runner; project skills under
   `--setting-sources user` are untested.
10. Also for the shared workflow: the rules-restore step's limits from PR #17. It matches
   file names by hand and repeats the list in two `find` commands, does not check for
   symlinked parent folders or differently cased names, and recreates folders a PR deleted.
   Reading rules from a kept `.review-base` would remove the name list. The case where a PR
   tampers with a rules file has only been tested locally, never on a runner.
11. Done November 15: all four repos run the shared review from npHavens/.github, and CB's
   copy, its tests and the `AGENTS.md` text about it are removed. Still open, for HQ: whether
   PR #21's user-level `CLAUDE.md` rule fixed the missing severity labels in the other repos.

12. Focus bounce, from PR #27: find what returns focus to Commercial Breaker after Safari
    activates (both cases start from a click in its window), for example by waiting for
    mouse-up or a short settle before yielding activation, so the v0.2.52 retry stops being
    the fix. Also test `routeForAutomation`'s use of `FocusBounceRetry` by putting the AX
    calls behind injectable closures, so a fake can show a selection is never retried.
    `AutomaticCommercialModel` already takes its capture and routing through the
    `AutomaticCapture` and `AutomaticRouting` protocols, and `Tests/automatic-commercial-model`
    drives it with fakes; extend that test when changing break and return behavior.

Do not combine all of this into one rewrite.

## Remaining issues / limits

- Sports betting ads can cause false program returns. Future commercial learning
  should avoid manual labeling burden. No fingerprint library implemented.
- ViewingActivity refresh exists, but screen saver/lock prevention is not proven.
- All-zero system capture used to stall the TV return. It recurred on November 14 (23
  minutes on the Mac during a UFC break, 21 of them silent, until Stop and a restart). Since v0.2.54 the
  break returns to the TV after about 30 seconds of it. The root cause is still unknown: the
  capture heard program for about a minute after the handoff, then only zeros, which
  points to the Mac's relay playback stalling rather than the tap. The relay keeps no log.
- v0.2.53, in daily use from 12:38 PM on November 15, stopped on its own four times by the
  next morning: twice on an incomplete Gemini answer (retried since v0.2.55), once on wake
  after the Mac was put to sleep with a session running, and once at 3:29 PM during an
  AirPlay break handoff, when Safari no longer showed Commercial Breaker's AirPlay button. A
  restart failed the same way, and Nick switched to Mac playback. Why the button was missing
  is unknown.
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
are ignored. Original main baseline is 6e738c9; startup fix ce94934; community docs
3870502.

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
