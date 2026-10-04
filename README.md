# Project Skybox

## Native macOS capture experiment

The [macOS probe](MacAudioProbe/README.md) adds system-audio metering, a ten-second
mute-while-capturing test, and native window/display video previews. Use the
**SkyboxAudioProbe** scheme in the existing Xcode project. Diagnostics save
automatically outside Safari. Local DIRECTV audio capture continued while output
was muted, verified by Nick. Native AirPlay returned only zero audio samples
and tap muting did not silence the TV. Native video was reported black again;
the saved images do not independently verify the DIRECTV video area.

## Safari experiment

Nick verified DIRECTV native AirPlay and mute control. Paramount's original player handoff failed, but the [local HLS relay](Experiments/hls-relay.md) achieved moving video and sound on the Mac and Apple TV. Extension v0.2.0 adds relay controls and automatic muting from playlist commercial markers; real-break alignment and TV mute transitions remain to be verified.

The current experiment lives in [SafariExtension](SafariExtension/README.md), within this same project. Safari extended-desktop AirPlay playback and manual Paramount+ player mute/unmute have been confirmed by Nick. Nick verified the manual mute extension against Paramount+ in Safari. A local commercial-signal recorder is now implemented; eleven behavior tests pass. Actual commercial signals remain unverified pending a marked recording.

Experimental sports-viewing companion. The current tvOS 27 probe tests whether Skybox's own video can stay in Picture in Picture while DIRECTV plays full-screen, and whether app code and network requests continue during that interval. Automatic commercial detection and external mute control are not implemented.

Observed capture results: ReplayKit saved Skybox frames but stopped when switching apps. ScreenCaptureKit's `.window` picker compiled but failed on tvOS 27.0 with error -3823 (unsupported content style). The older capture screen remains available for reference.

## PiP background execution experiment

1. Open Skybox and select **Prepare video**. This starts a silent, bundled 60-second looping clip and activates the audio playback background mode with mixing enabled.
2. Once **Start PiP** is enabled, select it. If it never enables, or an error appears, record the event log; do not infer success from inline playback.
3. Go to Apple TV Home and open DIRECTV. Play the broadcast for two minutes. Observe whether the Skybox PiP remains visible and DIRECTV video/audio continue normally.
4. Return to Skybox, select **Stop test**, then **Event log**. Look for `scene background` heartbeats spaced about five seconds apart and network requests that both start and finish during the background interval. Long heartbeat gaps or completions only after returning indicate suspension or stalls.
5. Repeat start/stop to check recovery. A run automatically stops at the first heartbeat at or after five minutes; if the app is suspended, cleanup occurs when execution resumes. Closing PiP also stops the run.

The clip is prerecorded: its movement is **not** proof of app execution. Heartbeats use monotonic time; the log records wall-clock timestamps. Network checks request Apple's small public `https://www.apple.com/library/test/success.html` response every ten seconds, with cache bypass, an eight-second timeout, and at most one request in flight. They do not contact Sportradar or need an API key. This is a feasibility test, not proof of App Store acceptance or guaranteed long-term background execution.

**Mute investigation:** `AVAudioSession.outputVolume` is read-only. Muting the probe's player does not mute DIRECTV or the external audio system. The user's LG soundbar uses optical input; its exact model and network-control capability are still needed. **Log audio route** records tvOS's route and reported volume without changing them. No external mute command is implemented or sent.

The PiP video uses `AVPlayerLayer`, `AVPictureInPictureController`, and `MPNowPlayingSession`. Apple's June 2026 [developer-support response](https://developer.apple.com/forums/thread/830764) says custom sample-buffer PiP is unsupported on tvOS despite its API annotations. A future live data display needs its own investigation; this clip tests playback coexistence and execution only.

The generated asset is `SkyboxProbe/PiPTest.mp4`. To regenerate it on macOS, run `swift Tools/generate-pip-video.swift /tmp/new-pip-test.mp4` with Xcode selected, then replace the asset. The destination must not already exist. Generation requires access to macOS video-encoding services.

## Run on Apple TV

1. Open `SkyboxProbe.xcodeproj` in Xcode 27 or newer with the tvOS 27 SDK. The Apple TV must run tvOS 27 or newer. On this Mac, Xcode 27.1 is currently at `~/Downloads/Xcode.app`; `/Applications/Xcode.app` is still 26.6.
2. In Xcode Settings → Accounts, add your personal Apple Account if needed.
3. Select the blue project icon → SkyboxProbe target → Signing & Capabilities. Enable automatic signing and select your Personal Team. Use a unique bundle identifier if Xcode reports that the current one is unavailable.
4. Put the Mac and Apple TV on the same network. On Apple TV open Settings → Remotes and Devices → Remote App and Devices.
5. In Xcode, open Window → Devices and Simulators. Select the discovered Apple TV, pair, and enter the displayed code. Follow any Developer Mode or device preparation prompts.
6. Choose SkyboxProbe and your physical Apple TV in Xcode's toolbar, then press Run (Cmd-R).

Xcode handles signing and installation. The Apple TV's signed-in account need not match the signing account. If no Personal Team is offered, finish the free developer-account setup for the Apple Account used in Xcode. Free signing may require reinstalling after the provisioning expires.

## Earlier window picker experiment (failed on tvOS 27.0)

1. Open **Earlier capture experiment**, then select **Choose window**. Inspect the system picker before accepting: does it offer another app, only Skybox, or just a recording confirmation? Record the exact choices. Cancel once and confirm you can reopen it. If another app is offered, select it; otherwise accept the available source and document that limitation. The button is disabled during selection/startup/capture; **Stop capture** is enabled once startup completes.
2. For a Skybox source, stay in the probe for 60 seconds. Expect an initial frame and another roughly every 20 seconds while fresh video samples continue. Previously saved ReplayKit images remain in the gallery: compare timestamps and the new “Saved window frame” events, not the total count alone.
3. Select **Frames** to inspect full saved images and timestamps; use the remote's Back button to return. **Event log** shows lifecycle transitions, saved frames, and recorder errors, newest first.
4. Return to the probe's main screen, note the time, then switch to Apple TV Home or another app for 60 seconds. Return and stop capture if it is still running. Inspect frames and logs.
5. **Pass requires fresh images of the other app during that interval.** Old probe images, black frames, a growing elapsed-time counter, or images saved only after returning do not pass. If capture stops or stalls, record that failure and stop here.
6. Only if step 4 passes, repeat with the target sports streaming app for 2–3 minutes. Require actual video pixels, then test an ad transition and return to the event.
7. Repeat by launching the installed probe from Apple TV Home without the debugger; then repeat with the Mac disconnected.

Avoid interpreting the live clock as evidence of capture. It is independent of capture. The last-saved age and persisted images are the evidence. Inspecting the gallery during capture will itself appear in subsequent captures.

## Implementation and limitations

- The probe calls `SCContentSharingPicker.shared.present(using: .window)` and starts an `SCStream` from the returned filter. It does not use full-display capture, which is unavailable on tvOS. No cropping is applied: first establish access to the desired source.
- Only screen output is registered; audio is not stored. Valid, ready buffers with complete frame status (when present) are eligible for JPEG sampling. The first buffer and each distinct skip reason are logged once per session.
- Picker selection logs include filter style, content rectangle, and scale. The tvOS filter does not expose the source app identity, so the picker and saved images must establish that.
- JPEG sampling uses video presentation timestamps: first frame, then every 20 seconds, resetting at each start. The app now declares the audio background mode for the separate PiP experiment; this does not grant window capture permission.
- JPEGs (up to 100 total, including prior sessions) and events (up to 1,000) persist in `Caches/CaptureProbe`. tvOS can purge caches. The Frames and Event log screens load prior evidence on launch. The last-saved age resets each process/session.
- Capture errors are surfaced; duplicate starts are rejected. Start/stop control and UI updates run on the main queue; image processing is serialized with no full-rate buffer backlog.
- There are no LLM calls, sports-data API calls, or external mute controls. Networking is limited to the PiP connectivity test described above.
- A successful build is not proof of capture feasibility. Simulator or Mac developer screenshots do not establish standalone tvOS capture.

## Local verification

Use the full Xcode toolchain:

```sh
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
xcodebuild -project SkyboxProbe.xcodeproj -scheme SkyboxProbe \
  -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath /tmp/skybox-derived CODE_SIGNING_ALLOWED=NO build
xcrun swiftc -module-cache-path /tmp/skybox-module-cache \
  SkyboxProbe/FrameSampler.swift Tests/main.swift -o /tmp/skybox-sampler-tests
/tmp/skybox-sampler-tests
```

The sampling checks cover first frame, interval boundaries, invalid timestamps, stream timestamp rollback, and restarting capture. Picker cancellation, permission handling, stop/restart, interruption behavior, and third-party video must be verified on Apple TV.
