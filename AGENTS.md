# Commercial Breaker agent notes

Start with the README, CONTRIBUTING and `docs/handoff.md`. The repository is
public: keep secrets, recordings and stream URLs out of it.

## Code Review Rules

### Review standard

- Review this as a codebase that will be handed to a team, not a personal script repo. Missing tests for changed behavior, misleading comments, duplicated logic, dead code and speculative abstractions are findings, not nits.
- Report every finding you can tie to a concrete trigger and consequence; don't stop at the worst one.
- Leave formatting and lint to tooling.

### Acting in other apps

- Flag any change that lets automation click, type or press controls while an app other than Safari or Commercial Breaker is frontmost, or that weakens the check that stops a handoff when focus moves away. Acting in whatever app the user switched to can send input to the wrong place.
  Safe path: stop the handoff and report it. Retry only after focus is confirmed back in Safari or Commercial Breaker.
- Flag retries of an AirPlay selection whose outcome is unknown. A repeated selection can flip playback to the wrong device.
  Exception: picker rows that never appeared before any selection may be retried within a bounded limit.

### Break and return handoffs

- Flag changes that reorder the return from a break. The muted system capture must be released and the microphone listening before playback is sent back to the TV, with classifier context reset after. Requesting the TV first leaves a stretch with no detection, and a capture left in place keeps the Mac muted.
  Safe path: keep the order. If a step fails, stop with playback somewhere the user can hear it.
- Flag any path that can leave the Mac muted without a timeout. Both modes release the mute after three minutes.

### Detection behavior

- Flag changes to classifier prompts, sample length, cadence, the one-request-in-flight limit or confirmation thresholds that the PR description doesn't call out. Break and return accuracy is only measured live, so silent drift goes unnoticed.
  Safe path: refactors keep every prompt hash unchanged. A deliberate prompt change names the hashes that changed and why.
- Flag any change that treats exact digital silence as program or commercial. Silence is rejected locally.

### Public repository data

- Flag committed audio, recordings, logs, stream or session URLs, tokens, keys or `.env` values. The repository is public, recordings can capture voices in the room, and stream URLs grant access.
  Safe path: local evidence stays in the app's Application Support folder or ignored paths. Tests use synthetic audio and fake workers.
- Flag tests or tools that send audio to a provider without an explicit opt-in. Offline tests never authorize uploads; the default run is a dry run.

### macOS permissions and identity

- Flag changes to bundle identifiers, the signing team, entitlements, or how the app requests microphone, system audio or Accessibility access. macOS ties those grants to the bundle identifier and signature, so a change makes every user grant them again, and a lost grant shows up as silent capture or routing failure. The `com.nohandsstack.skybox.*` identifiers keep `skybox` permanently.
  Exception: an intended change says so in the PR and updates the upgrade steps that tell users what to re-grant.
