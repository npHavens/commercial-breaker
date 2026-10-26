# Commercial Breaker Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire "Skybox" and make "Commercial Breaker" the product name everywhere it is not load-bearing for already-granted macOS permissions.

**Architecture:** The rename is split by coupling class, not by directory, because each class has a different failure mode: display strings cannot break, compiler-checked Swift identifiers break loudly, and string-keyed `globalThis` bridges and persisted storage keys break *silently*. Each class gets its own task and its own test cycle. Phase 2 of the app plan (PR #5) deleted part of the Swift surface before the code tasks run, so those files are not renamed. Phase 3 has not started, so the extension files it will delete are renamed along with the rest. Bundle identifiers are deliberately not renamed.

**Tech Stack:** Swift/SwiftUI (macOS), Safari Web Extension (vanilla JS, `.cjs` tests), Node 24 ESM tools (`.mjs` tests), Python relay (`unittest`), Xcode project, `swiftc`-driven test executables.

**Spec:** `docs/commercial-breaker-plan.md` — currently on branch `chore/commercial-breaker-plan`, unmerged. Task 1 amends it there.

**Order of work:** Gemini 3.8 Flash (PR #4) and phase 2 (PR #5) are landing first. Line numbers below were taken before those PRs and PR #3 shifted the code, so locate every edit by grep, not by line number.

## Global Constraints

- **Bundle identifiers are NOT renamed.** `com.nohandsstack.skybox.audio-probe` stays byte-identical, as do `com.nohandsstack.skybox.probe`, `.video-probe`, `.live-cues`, `.browser`, `.audio-meter`, `.audio-clips`. macOS TCC keys microphone, system-audio and Accessibility grants to the bundle ID; changing it forces Nick to re-grant all three. This is the one place "across the board" is knowingly not honored.
- **No task changes detection or handoff behavior.** Same prompts (football `promptSHA256` 9ccb506e…), same cadence, two-prediction confirmation, three-minute release, and AirPlay return ordering (release tap, start microphone, request TV, reset classifier context).
- **Naming convention, applied uniformly:** `commercialBreaker` for JS identifiers and `globalThis` properties; `CommercialBreaker` for Swift types and the Application Support directory; `commercial-breaker` for kebab-case storage keys, event names and generated filenames; `COMMERCIAL_BREAKER_` for environment variables. The abbreviation `cb` is rejected: these globals live on pages the app does not own (directv.com, paramountplus.com), where a two-letter global is a collision risk.
- **Historical records are not rewritten.** `docs/archive/`, `Experiments/*.md` and `Experiments/audio-model-eval/manifest.json` are dated findings. They keep "Skybox" and gain no edits. Renaming inside them would falsify records and break references to `skybox-signals-*.json` files that exist on disk.
- **`build/` is gitignored.** Its ~4,500 matches are Xcode artifacts and are never edited; they disappear on the next clean build.
- **Each task is one commit set with its offline suites passing.** Tasks 2–6 run continuously on one local branch once PRs #4 and #5 are merged, and open as stacked per-task PRs when Nick approves the push.

## Review Focus

1. **A `globalThis.skybox*` global renamed on one side of a context boundary only.** These are string-keyed across the content script / page context / popup divide, so a half-rename is a silent no-op at runtime, not an error. Every bridge test must assert the new name is defined *and* the old name is `undefined`.
2. **The Application Support rename orphaning existing data.** `~/Library/Application Support/SkyboxAudioProbe/` holds the logs and recordings the handoff doc points at. A bare rename abandons October's diagnostic history in a directory nothing reads any more.
3. **A persisted key renamed without migration resetting state mid-game.** `skybox-auto-toggle` and `skybox.relay.playback-history` carry live state; a cold default arriving during a game half reads as a malfunction.
4. **The evaluation tools still reading `Library/Application Support/SkyboxAudioProbe/recordings` after Task 6 renames that directory.** `Tools/evaluate-gemini-audio.mjs` and `Tools/compare-detection.mjs` (locate by grep for `SkyboxAudioProbe`) resolve that path with `realpath` as an allow-list root. Once the directory moves they match nothing, and it surfaces as "no recordings found" rather than as a broken path. They must move in the same commit as the directory.
5. **The `SkyboxAudioProbe` scheme name is hardcoded in the build and test commands in `docs/handoff.md`.** Renaming the scheme without updating that doc leaves the documented build command failing for the next person, which is how this repo is handed off.

---

### Task 1: Record the naming decision in the spec

The spec currently states the opposite of the decision: *"**Skybox** is the app. **Commercial Breaker** is its feature"*, and phases 4 and 6 instruct the implementer to rename things *to* Skybox. Every later task reads from this document, so it is corrected first, on the branch where it lives.

**Files:**
- Modify: `docs/commercial-breaker-plan.md` (on branch `chore/commercial-breaker-plan`)

**Interfaces:**
- Produces: the authoritative product name and the bundle-ID exception that Tasks 2–7 cite.

- [ ] **Step 1: Check out the branch the spec lives on**

Run: `git checkout chore/commercial-breaker-plan && git rebase main`

- [ ] **Step 2: Invert the naming sentence in "What it becomes"**

Replace *"**Skybox** is the app. **Commercial Breaker** is its feature: it listens…"* with a sentence making Commercial Breaker the app and naming no feature-level brand. Update the ASCII window mock's title bar from `┌ Skybox ───` to `┌ Commercial Breaker ───` and drop the now-redundant `Commercial Breaker` subtitle line inside it.

- [ ] **Step 3: Correct the rename instructions in phases 4 and 6**

Phase 4's *"Rename the app, target and scheme to Skybox"* becomes *"to Commercial Breaker"*. Phase 6's *"Rename it Skybox"* becomes *"Rename it Commercial Breaker"*, and *"inside Skybox"* becomes *"inside Commercial Breaker"*. Phase 7's *"Skybox starts and stops the relay helper"* becomes *"Commercial Breaker starts and stops…"*. Settings' *"the AirPlay devices Skybox finds"* becomes *"…Commercial Breaker finds"*.

- [ ] **Step 4: Amend the constraint and the decision log**

In "Constraints for every phase", keep the bundle-identifier sentence and extend it to state explicitly that the identifier retains the `skybox` segment by design while every name a person sees becomes Commercial Breaker. In "Calls I made (veto any)", change *"The bundle identifier is not renamed, to keep the permissions already granted"* to record the 2026-10-19 decision: the product is renamed across the board, the bundle identifier excepted, for that reason.

- [ ] **Step 5: Add a line to "Why" dating the decision**

One sentence: the name was settled as Commercial Breaker on 2026-10-19, superseding the earlier app/feature split.

- [ ] **Step 6: Verify no instruction still points at the old name**

Run: `grep -n -i skybox docs/commercial-breaker-plan.md`
Expected: matches only in the bundle-identifier constraint, the decision log entry, the "Why" section's description of the old experiment, and the dated supersession line. No imperative "rename … to Skybox" remains.

- [ ] **Step 7: Commit**

```bash
git add docs/commercial-breaker-plan.md
git commit -m "Make Commercial Breaker the product name in the app plan"
```

---

### Task 2: Repo and package identity

**Files:**
- Modify: `package.json:2`, `README.md`, `CONTRIBUTING.md`, `.env.example:1`, `docs/handoff.md`
- Test: `Tests/safari/*.test.cjs` (regression only — no package name is asserted)

**Interfaces:**
- Consumes: the product name fixed by Task 1.
- Produces: `package.json` `"name": "commercial-breaker"`.

- [ ] **Step 1: Confirm nothing imports the package by name**

Run: `grep -rn '"skybox"' --include='*.json' --include='*.mjs' --include='*.cjs' --include='*.js' . --exclude-dir=node_modules --exclude-dir=build` (quote the globs; unquoted they break in zsh)
Expected: only `package.json:2` and `package-lock.json`. If any import or workspace reference appears, it joins this task.

- [ ] **Step 2: Rename the package**

Set `"name": "commercial-breaker"` in `package.json`, then run `npm install --package-lock-only` to update the two `package-lock.json` occurrences rather than hand-editing them.

- [ ] **Step 3: Rewrite the prose in `README.md`, `CONTRIBUTING.md` and `.env.example`**

8 occurrences in `README.md`, 1 in `CONTRIBUTING.md`, 1 in `.env.example`. All are prose or comments naming the product. Leave the `https://github.com/npHavens/skybox` URL for Step 4.

- [ ] **Step 4: Update `docs/handoff.md`, including the repo URL and scheme caveat**

12 occurrences. Rename the title and prose. Leave `~/Library/Application Support/SkyboxAudioProbe/`, the `SkyboxAudioProbe` scheme name, and the `/tmp/skybox-*` test paths as they are — Tasks 6 and 7 own those, and the doc must keep describing the tree as it stands until then. Add one line under "Commands" noting the rename is in progress and which names are not yet migrated.

- [ ] **Step 5: Run the full offline suite**

Run: `npm test && python3 -m unittest discover -s Tests -p 'test_*.py'`
Expected: PASS, unchanged from before this task.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json README.md CONTRIBUTING.md .env.example docs/handoff.md
git commit -m "Rename the package and docs to Commercial Breaker"
```

- [ ] **Step 7: Ask Nick before renaming the GitHub remote**

The repo rename (`npHavens/skybox` → `npHavens/commercial-breaker`) is an outward-facing change on a public repo. GitHub redirects the old URL and `origin` keeps working, but it changes a public URL others may have linked. Do not run it; surface it as a decision with the redirect behavior stated. If approved, the local directory `/Users/nickhavens/Projects/skybox` is a separate, equally optional step — nothing in the tree depends on the directory name except two absolute paths in `docs/handoff.md`.

---

### Task 3: Node and Python tool environment and strings

**Files:**
- Modify: `Tools/gemini-live-worker.mjs`, `Tools/vertex-client.mjs`, `Tools/relay_bridge.py`, `Tools/evaluate-gemini-audio.mjs`, `Tools/compare-detection.mjs`, `MacAudioProbe/GeminiObservation.swift` (locate each by grep for `SKYBOX_` and `skybox-`)
- Test: `Tests/gemini-audio/vertex-client.test.mjs`, `Tests/gemini-observation/main.swift`

**Interfaces:**
- Produces: `COMMERCIAL_BREAKER_SPORT`, `COMMERCIAL_BREAKER_RETURN_DETECTION`, set by the Swift app and read by the worker.

- [ ] **Step 1: Write the failing test**

In `Tests/gemini-audio/vertex-client.test.mjs`, add a test that sets `COMMERCIAL_BREAKER_SPORT=ufc` and `COMMERCIAL_BREAKER_RETURN_DETECTION=1` in `process.env`, invokes the worker's config resolution, and asserts the resolved sport is `ufc` and return detection is `true`. Add a second test that sets the old `SKYBOX_SPORT=ufc`, and another that sets `SKYBOX_RETURN_DETECTION=1`, and asserts each fails as a setup failure naming the new variable. The worker reads `process.env.SKYBOX_*` inline in `main()` with no exported config function, so extract one: an exported pure function that takes `env` and returns `{ sport, returnDetection }` or throws the setup failure, and test that function. In `Tests/gemini-observation/main.swift`, assert the worker environment the app builds carries the new keys and neither old key.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test Tests/gemini-audio/vertex-client.test.mjs && Tests/run-native-tests.sh gemini-observation`
Expected: FAIL — all three new tests fail: the new names aren't read yet and nothing rejects the legacy names.

- [ ] **Step 3: Rename both reads**

`MacAudioProbe/GeminiObservation.swift` sets `SKYBOX_SPORT` and `SKYBOX_RETURN_DETECTION` in the environment of every worker it launches, so the worker and the app must change together. In `Tools/gemini-live-worker.mjs`, `process.env.SKYBOX_SPORT` becomes `process.env.COMMERCIAL_BREAKER_SPORT` and `process.env.SKYBOX_RETURN_DETECTION` becomes `process.env.COMMERCIAL_BREAKER_RETURN_DETECTION`. In `GeminiObservation.swift`, rename the two keys it sets in the same commit. Read the new names only, with no fallback. If either legacy name is present in the worker's environment, fail startup as a setup failure that names the replacement: a worker-only rename would silently drop UFC selection and AirPlay return detection mid-game, which the spec forbids as a detection-behavior change. These few lines are temporary and phase 4 can delete them. The Swift change takes effect on the next pull for an already-built binary, because the app runs `Tools/` from the checkout it was built from, so rebuild after merging.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test Tests/gemini-audio/vertex-client.test.mjs && Tests/run-native-tests.sh gemini-observation`
Expected: PASS

- [ ] **Step 5: Document the new names**

Add both variables to `.env.example` as commented-out optional overrides, with their defaults (`football`, off). They were previously undocumented in `.env.example`; the app, not `.env`, sets them.

- [ ] **Step 6: Rename the tool-level strings and temp-directory prefixes**

Three user-facing strings in `Tools/relay_bridge.py` — the docstring and the two pairing-code messages — are what Nick reads in Terminal when starting the Paramount relay. Phase 7 removes Terminal eventually; until then they name the product. Rename those, the comment at `Tools/vertex-client.mjs:2`, and the `mkdtemp` prefixes `skybox-gemini-` and `skybox-compare-` in `Tools/evaluate-gemini-audio.mjs` and `Tools/compare-detection.mjs`.

Leave the `Application Support/SkyboxAudioProbe/recordings` paths in those same two files alone. Task 6 owns them and they must move in the same commit as the directory itself.

- [ ] **Step 7: Run the full offline suite and commit**

```bash
Tests/run-native-tests.sh gemini-observation && npm test && python3 -m unittest discover -s Tests -p 'test_*.py'
git add Tools MacAudioProbe/GeminiObservation.swift Tests/gemini-audio/vertex-client.test.mjs Tests/gemini-observation .env.example
git commit -m "Rename worker env vars and tool strings to Commercial Breaker"
```

---

### Task 4: Safari extension page-context bridge globals

The highest-risk task. These `globalThis.skybox*` properties are the contract between injected content scripts, the popup, and page context on sites the app does not own. They are string-keyed, so a rename applied to a definition but not its consumer fails silently.

**Files:**
- Modify: every `SafariExtension/*` file Step 1 finds, including `airplay-session.js`, `relay-controls.js`, `player-events.js`, `player.js`, `diagnostics.js`, `direct-audio.js`, `directv-airplay-recovery.js`, `directv-autoload.js`, `paramount-capture.js`, `airplay-source-trace.js`, `relay-target.js`, `background.js`, `popup.js`, `popup.html`, `manifest.json`, `SafariExtension/README.md`, `Tools/commercial-controller.js`, `Tools/hls_player.html`
- Also modify, although phase 3 will delete them: `audio-probe.js`, `audio-result.js`, `export.js`, `frame-probe.js`, `save-recording.js`, `save-recording.html`, `screen-test.js`, `screen-test.html`, `select-video.js`. Phase 3 has not started, so a global shared between a surviving file and one of these would be half-renamed if they were skipped. Phase 3 deletes a few already-renamed lines at worst.
- Test: `Tests/safari/airplay.test.cjs`, `relay-controls.test.cjs`, `popup.test.cjs`, `player-events.test.cjs`, `player.test.cjs`, `diagnostics.test.cjs`, `direct-audio.test.cjs`, `directv-recovery.test.cjs`, `source-trace.test.cjs`, `paramount-capture.test.cjs`, `commercial-controller.test.cjs`, `export.test.cjs` (it references `skyboxSaveRecording`, so it changes with the rename even though phase 3 will delete the file)

**Interfaces:**
- Produces: `globalThis.commercialBreakerAirPlayPanel`, `…RelayControl`, `…PlayerEvents`, `…Player`, `…Diagnostics`, `…DirectvRecovery`, `…CreateCommercialController`, `…Commercial`, `…AirPlayRouteResult`, `…AirPlaySourceTrace`, `…IsRelayUrl`, `…ParamountCapture`, and the `commercialBreakerVersion` property on the panel and host objects. Task 6 consumes none of these directly; the Swift side matches on AX button labels, not on these names.

- [ ] **Step 1: Enumerate the live globals and freeze the mapping**

Run: `git ls-files 'SafariExtension/*' 'Tools/*' | xargs grep -ohE 'skybox[A-Za-z0-9_]*' | sort -u`

Record the output as the mapping: each `skyboxFoo` becomes `commercialBreakerFoo`. This list is the task's checklist and covers every extension file. The Interfaces list above is illustrative; any global this step finds that it omits is renamed too.

- [ ] **Step 2: Write the failing assertions**

In each listed test file, for every global that file exercises, assert the new name is defined on the harness context *and* assert the old `skybox*` name is `undefined`. The paired negative assertion is the only thing that catches a half-rename across the context boundary.

- [ ] **Step 3: Run the extension suite to verify the new assertions fail**

Run: `node --test Tests/safari/*.test.cjs`
Expected: FAIL on the new-name assertions; the `undefined` assertions on old names also fail, since the old names are still defined.

- [ ] **Step 4: Apply the mapping across every file Step 1 finds**

Rename every occurrence from Step 1's mapping in every file Step 1 finds, whether listed under **Modify** or **Also modify**, definitions and consumers together. Include the `h.context.*` and `f.context.*` harness references in the test files themselves, and the `api:ctx.skyboxParamountCapture` reference. Do not add backwards-compatible aliases: an alias defeats the negative assertions and leaves the old name live on third-party pages.

`SafariExtension/README.md` (locate by grep) documents `globalThis.skyboxAirPlayRouteResult` by name and must change with it; that file's other 7 occurrences are product prose and update in the same pass.

- [ ] **Step 5: Run the extension suite to verify it passes**

Run: `node --test Tests/safari/*.test.cjs`
Expected: PASS

- [ ] **Step 6: Verify no live file still defines an old global**

Run: `git ls-files 'SafariExtension/*' 'Tools/*' 'Tests/safari/*' | xargs grep -n 'globalThis\.skybox\|context\.skybox'`
Expected: no output.

- [ ] **Step 7: Run the full offline suite and commit**

```bash
npm test && python3 -m unittest discover -s Tests -p 'test_*.py'
git add SafariExtension Tools Tests/safari
git commit -m "Rename extension bridge globals to commercialBreaker*"
```

- [ ] **Step 8: Nick confirms one live DIRECTV AirPlay cycle**

Offline tests cannot prove the page-context bridge survived. One break/return cycle on a DIRECTV page, including the short handoff rewind, is the acceptance check. Nothing may interrupt playback to run it.

---

### Task 5: Extension persisted keys and event names

Separated from Task 4 because the failure mode differs: these do not break the bridge, they reset saved state.

**Files:**
- Modify: every extension file Step 1 identifies, including files phase 3 will delete (phase 3 has not started)
- Test: `Tests/safari/relay-controls.test.cjs`, `directv-recovery.test.cjs`, `export.test.cjs`, `popup.test.cjs`

**Interfaces:**
- Produces: `commercial-breaker-commercial-state`, `commercial-breaker-auto-toggle`, `commercial-breaker-auto-history`, `commercial-breaker-auto-status`, `commercial-breaker-direct-audio`, `commercial-breaker-relay`, `commercial-breaker.relay.playback-history`, `commercial-breaker.airplay-attempt`, `commercial-breaker.frames`, `commercial-breaker.audio-test-status`, `commercial-breaker.recording-export`, and the event name `commercial-breaker-airplay-trace-stop`.

- [ ] **Step 1: Locate each key and classify it as live state or scratch**

Run: `git ls-files 'SafariExtension/*' 'Tools/*' | xargs grep -n "skybox[-.][a-z]" | sort`

For each hit, record whether it is read back across a restart (live state: `auto-toggle`, `relay.playback-history`, `commercial-state`) or written and discarded within a session (scratch: `frames`, `airplay-attempt`, `audio-test-status`). Keys in files phase 3 will delete are renamed too; they are scratch keys, so they take no migration.

- [ ] **Step 2: Write the failing migration test**

For each live-state key, add a test that seeds the harness storage with the *old* key and its value, runs the module's initialization, and asserts the value is readable under the new key and the old key has been removed. For scratch keys, assert only the new key is written.

- [ ] **Step 3: Run the tests to verify they fail**

Run: `node --test Tests/safari/*.test.cjs`
Expected: FAIL — no migration exists.

- [ ] **Step 4: Rename the keys and add the one-time migration**

Rename every key per the Interfaces mapping. For live-state keys only, add a single read-time migration helper that copies the old key to the new one and deletes the old, running once on module initialization. Scratch keys are renamed with no migration.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `node --test Tests/safari/*.test.cjs`
Expected: PASS

- [ ] **Step 6: Run the full offline suite and commit**

```bash
npm test && python3 -m unittest discover -s Tests -p 'test_*.py'
git add SafariExtension Tools Tests/safari
git commit -m "Rename persisted extension keys with a one-time migration"
```

---

### Task 6: Swift identifiers, user-facing strings, and the Application Support directory

Written against the tree after phase 2 (PR #5), which deleted `LiveAudioCues`, `ProbeModel`, `VideoProbe`, `AudioClipStore`, `Tests/main.swift`, `Tests/live-audio-cues`, `Tests/audio-clips` and `Tests/audio-clock-clips`. Confirm against the tree before editing, and locate every edit by grep.

**Files:**
- Modify: `MacAudioProbe/SafariAccessibility.swift`, `AutomaticCommercialModel.swift`, `AudioRecorderModel.swift`, `RoutingModel.swift`, `AudioTap.swift`, `GeminiObservation.swift`, `MicrophoneInput.swift`, `ViewingActivity.swift`, `RoutingView.swift`, `MacAudioProbe/README.md`, `docs/handoff.md` (its Application Support path)
- Create: a small support-directory file in `MacAudioProbe/` holding the directory name as one shared constant and the migration, with its own test at `Tests/<name>/main.swift` registered in `Tests/run-native-tests.sh`
- Rename: `MacAudioProbe/SkyboxAudioProbeApp.swift` → `MacAudioProbe/CommercialBreakerApp.swift`; `Tests/skybox-panel` → `Tests/commercial-breaker-panel`, updating its entry in `Tests/run-native-tests.sh`
- Modify in the same commit as the directory rename: `Tools/evaluate-gemini-audio.mjs` and `Tools/compare-detection.mjs` (the `SkyboxAudioProbe/recordings` allow-list root)
- Check only: `MacAudioProbe-Info.plist`. PR #5 already rewrote the permission text for the post-phase-2 app; confirm it names no marked clips and rename the product only if it still says Skybox.
- Do NOT modify: the five Accessibility strings that name "SkyboxAudioProbe" (three in `SafariAccessibility.swift`, two in `RoutingModel.swift`; at phase 2's head `SafariAccessibility.swift:33,42,285` and `RoutingModel.swift:27,208`). They read "Enable Accessibility permission for SkyboxAudioProbe first." or tell Nick to enable it in Privacy & Security → Accessibility, and that is the name System Settings actually lists until the product is renamed, so they move in Task 7. Find them with `grep -n 'SkyboxAudioProbe' MacAudioProbe/*.swift`; they are the hits that sit inside user-facing messages.

**Interfaces:**
- Produces: `SafariAccessibility.isCommercialBreakerPanel(_:)`, `struct CommercialBreakerApp`, the field `focusReturnedToCommercialBreaker`, the shared Application Support directory-name constant (value `CommercialBreaker`), and the migration entry point.

- [ ] **Step 1: Write the failing Application Support migration test**

In the new `Tests/<name>/main.swift`, add a test that creates a temporary directory containing `SkyboxAudioProbe/` with one file, runs the migration entry point, and asserts a `CommercialBreaker/` directory exists containing that file and that `SkyboxAudioProbe/` is gone. Add a second case asserting that when both directories exist, the migration leaves the new one untouched and does not merge. Register the test in `Tests/run-native-tests.sh`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `Tests/run-native-tests.sh`
Expected: FAIL — no migration entry point exists.

- [ ] **Step 3: Implement the migration**

Add a `migrateApplicationSupportDirectory(from:to:)` entry point that renames the directory with `FileManager.moveItem` when the old path exists and the new one does not, and is a no-op otherwise. Call it once at app launch, before any logging or recording path is resolved. Define the new directory name once, as a shared constant, and use it for the three hardcoded `"SkyboxAudioProbe"` directory literals now in `AutomaticCommercialModel.swift`, `RoutingModel.swift` and `AudioRecorderModel.swift`. Find them with `grep -n 'SkyboxAudioProbe' MacAudioProbe/*.swift`. Three hits are directory literals to change: `AutomaticCommercialModel.swift` (`.appendingPathComponent("SkyboxAudioProbe")`), `RoutingModel.swift` (`.appendingPathComponent("SkyboxAudioProbe", isDirectory: true)`) and `AudioRecorderModel.swift`, where the name is embedded in `"SkyboxAudioProbe/recordings/\(id…)"`. The other five hits are the Accessibility messages, which are skipped. Update the `~/Library/Application Support/SkyboxAudioProbe/` path in `docs/handoff.md` in the same commit.

In the same commit, update the two evaluation tools that resolve this directory as an allow-list root. They are JavaScript with no Swift test covering them, and they break the moment the directory moves (Review Focus item 4). Add a Node test asserting the resolved root ends in `CommercialBreaker/recordings`.

- [ ] **Step 4: Run the test to verify it passes**

Run the Step 2 command.
Expected: PASS

- [ ] **Step 5: Rename the Swift identifiers**

`isSkyboxPanel` → `isCommercialBreakerPanel` (and its call site), `isSkyboxButton` → `isCommercialBreakerButton`, `SkyboxMicrophone` → `CommercialBreakerMicrophone`, `SkyboxAudio` → `CommercialBreakerAudio`, `focusReturnedToSkybox` → `focusReturnedToCommercialBreaker` (including `failure.focusReturnedToSkybox`), and `SkyboxAudioProbeApp` → `CommercialBreakerApp` with its file renamed via `git mv`. Also `git mv Tests/skybox-panel Tests/commercial-breaker-panel` and update the references to it. `SkyboxCues` lived in the deleted `LiveAudioCues.swift`; rename it only if grep still finds it. These are compiler-checked; a miss is a build error, not a silent failure.

Leave the AX button label strings `"Try AirPlay"` and `"Restore settings and close"` exactly as they are. `isCommercialBreakerPanel` matches on those labels, not on the product name, and they must stay in sync with the extension's DOM.

- [ ] **Step 6: Confirm the permission usage descriptions**

PR #5 rewrote the strings in `MacAudioProbe-Info.plist` to match the post-phase-2 app. Confirm they mention no saved or marked clips. Where they still say Skybox, rename it to Commercial Breaker; do not otherwise rewrite them.

- [ ] **Step 7: Rewrite the remaining prose**

`MacAudioProbe/README.md` holds 32 occurrences — the largest single prose block in the repo (recount by grep, since phase 2 changed it). Rename the product throughout; leave any quoted historical log output intact, and leave the Accessibility "SkyboxAudioProbe" wording for Task 7.

- [ ] **Step 8: Build and run every Swift suite**

Run `Tests/run-native-tests.sh`, then build the app with a new derived-data path.
Expected: all suites PASS; the app builds with no new warnings.

- [ ] **Step 9: Commit**

```bash
git add MacAudioProbe MacAudioProbe-Info.plist Tests Tools docs/handoff.md
git commit -m "Rename Swift identifiers and migrate the support directory"
```

- [ ] **Step 10: Nick confirms the permissions survived**

Launch the rebuilt app and confirm macOS does not re-prompt for microphone, system audio or Accessibility — the proof that leaving the bundle identifier alone worked. Confirm the migrated logs directory contains the prior history.

---

### Task 7: Xcode target, scheme and product name

**Deferred into phase 4 of `docs/commercial-breaker-plan.md`, not run standalone.** Phase 4 already owns "rename the app, target and scheme", rebuilds the window around the new name, and adds the icon. Renaming the target here instead would mean doing it twice and invalidating the build commands between two in-flight branches.

**Files phase 4 touches for the rename:** `SkyboxProbe.xcodeproj/project.pbxproj`, `SkyboxProbe.xcodeproj/project.xcworkspace/contents.xcworkspacedata`, `SkyboxProbe.xcodeproj/xcshareddata/xcschemes/SkyboxAudioProbe.xcscheme`, `SkyboxProbe.xcodeproj/xcshareddata/xcschemes/SkyboxProbe.xcscheme` (deleted, not renamed).

Carried into phase 4 as requirements:
- Target and scheme `SkyboxAudioProbe` → `CommercialBreaker`; the product becomes `CommercialBreaker.app`.
- In `project.pbxproj`, change the `name = SkyboxAudioProbe;` target entry but **not** the adjacent `PRODUCT_BUNDLE_IDENTIFIER` lines. Both strings contain "skybox" and sit near each other; a careless find-and-replace over this file is the single most likely way to lose Nick's granted permissions. Verify with `grep -c 'com.nohandsstack.skybox' project.pbxproj` before and after — the count must not change.
- `PRODUCT_BUNDLE_IDENTIFIER` stays `com.nohandsstack.skybox.audio-probe`.
- `SkyboxProbe.xcodeproj` → `CommercialBreaker.xcodeproj`, with the `container:SkyboxProbe.xcodeproj` workspace references updated. The `SkyboxProbe` target, its scheme and `SkyboxProbe-Info.plist` are deleted by phase 2, not renamed.
- `docs/handoff.md`'s build and test commands update in the same PR, including the scheme name and the `/tmp/skybox-*` paths (Review Focus item 5).
- Rename the product in the five Accessibility strings that name "SkyboxAudioProbe": three in `SafariAccessibility.swift` and two in `RoutingModel.swift`. Find them with `grep -n 'SkyboxAudioProbe' MacAudioProbe/*.swift`; most read "Enable Accessibility permission for SkyboxAudioProbe first.", so a grep for `Privacy` misses three. Task 6 leaves them because they name the entry System Settings lists today; they change in the same PR that renames the product.
- The icon and wordmark come from the design work commissioned 2026-10-19.

---

## Not renamed, deliberately

| Thing | Why |
|---|---|
| `com.nohandsstack.skybox.*` bundle IDs | Preserves granted microphone, system-audio and Accessibility permissions |
| `docs/archive/prototype-overview.md` (18), `Experiments/*.md`, `Experiments/audio-model-eval/manifest.json` | Dated historical findings; renaming falsifies the record |
| `skybox-signals-*.json` filenames referenced in experiment logs | Files that exist on disk under those names |
| `build/**` (~4,500 matches) | Gitignored Xcode artifacts; cleared by the next clean build |
| AX labels `"Try AirPlay"`, `"Restore settings and close"` | Matched by the Swift AX layer; contain no product name |
| Files deleted by phase 2 (PR #5) | Already gone before the code tasks run |
| Accessibility instruction strings naming `SkyboxAudioProbe` | They name what System Settings lists until Task 7 renames the product |

## Execution order

Task 1 first and alone — every other task cites it. Tasks 2 and 3 are independent and can run in either order. Task 4 before Task 5, since both touch the same extension files and Task 4 is the riskier diff. Tasks 2–6 wait for PRs #4 and #5 to merge, then run in order on one local branch; Task 6 is written against the post-phase-2 tree. Task 7 does not run; it rides phase 4.
