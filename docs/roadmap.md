# From prototype to maintained community project

Agreed October 18, 2026: preserve the working experience, establish GitHub/PR
workflow, then remove obsolete experiment surfaces. This is not a production
readiness claim.

1. **Baseline PR:** current detection and AirPlay improvements, startup retry,
   accurate README, contributor workflow and MIT license. Keep live-verification
   gaps explicit. Merge after review; use focused branches for subsequent work.
2. **Standalone configuration:** remove the Interview Assistant dependency;
   declare Node/SDK dependencies, document Vertex authentication and local config,
   and verify a fresh clone can build and start detection without another repo.
3. **Runtime versus experiments:** move active prompts and runtime helpers out of
   experiment/evaluation modules, updating imports and tests together. Then
   remove the unused tvOS target, PiP asset/generator and obsolete diagnostics
   from the active project in a dedicated PR. Preserve findings in the archive.
   Audit references before deletion: Experiments and Tools are not all unused.
4. **App presentation:** make Automatic the normal viewing flow, with explicit
   Computer/AirPlay settings; move useful probes behind diagnostics. Decide and
   test audio isolation before promising app-specific muting while working.
5. **Extension migration:** TypeScript for background/content logic and React for
   popup UI, preserving DIRECTV handoff correction and regression coverage.
   Validate packaged reload/automatic attachment on a live stream.

## Outstanding behavior checks

- v0.2.44: start from Skybox once; verify bounded retry, cancel, other-app focus,
  wrong initial route and missing extension panel.
- Mac playback: complete a break/return while using another app; stop restores
  sound; three-minute release does not remute the same break.
- AirPlay: preserve the accepted short rewind; test screen saver/lock behavior.
  Viewing activity refresh is implemented, but screen saver prevention is not
  established. Earlier zero system capture remains an unresolved intermittent
  observation, despite recent successful sessions.
- Sports betting ads: improve false returns without a manual labeling burden.
  Automatic commercial recognition is a future idea, not implemented.

## Evidence

See `Experiments/detection-oct4/results.md`, `Experiments/airplay-return-oct4.md`
and `Experiments/oct11-automatic-stop.md`. The small detection comparison measured
request latency, not end-to-end accuracy. October 18 AirPlay logs show repeated
successful cycles and a recovered picker-unavailable event. Nick reports AirPlay
working well; Mac-only testing has begun but its latest outcome is not confirmed.
