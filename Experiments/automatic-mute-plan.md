# Extension and commercial muting

Requested scope: integrate the working native HLS relay with Skybox's Safari extension and automatically mute marked commercial breaks, restoring audio for programming.

## Evidence and timing design

- Nick confirmed moving video and sound locally, then native AirPlay video and sound. A reported tab-switch return to Mac later appeared resolved; long-running reliability remains unverified.
- The saved media playlist contains EXT-X-CUE-OUT, EXT-X-CUE-OUT-CONT, EXT-X-CUE-IN, and EXT-X-PROGRAM-DATE-TIME tags. These are candidate commercial boundaries; actual viewer-visible coverage still needs a real break test.
- Use the native video's getStartDate() plus currentTime for playback UTC, when available and finite. Compare that position with the parsed playlist timeline, not the current wall clock. Missing/ambiguous timing must remain unknown.
- Preserve user mute intent. Automatic mode may undo only a mute it owns. Disabling automation or losing timing restores an owned mute; manual control takes precedence. Do not change play/pause, playback position, volume, or AirPlay target.

## Implementation status

1. Implemented pure classification and timestamp/cue parsing in Tools/commercial_timing.py, including the feed's nanosecond date precision on Python 3.9. The saved real playlist yields 11 ad spans and 10 program spans, plus unknown coverage.
2. Added a session-protected commercial-state endpoint. It refreshes the timeline at most every three seconds for classification requests; native playlist requests also update it. Responses contain state, UTC bounds, and freshness, without source URLs, credentials, or keys.
3. Extension v0.2.0 recognizes private-LAN relay player URLs and verifies the page marker before operating controls. Manual mute and automatic mode act on the existing page controller, without another monitoring timer or new host permissions.
4. Tools/commercial-controller.js monitors the playback clock approximately once per second and on timeupdate events, with request throttling, a three-second request timeout, and stale/late-response checks. It changes only muted. Invalid timing, leaving an ad span, or disabling releases an owned mute; pre-existing mute is preserved. Manual volume/mute changes turn automatic mode off.
5. Pending: verify the native getStartDate mapping and TV audio across a real commercial break and return to programming, including a background-tab test. Browser suspension can delay JavaScript execution and mute transitions; no timer can guarantee unmute while the page is suspended.

The Mac helper remains required for authorized key delivery. This work does not yet automate copying session credentials or replace the helper with an extension-only playback path.

References: https://developer.apple.com/documentation/webkitjs/htmlmediaelement and https://www.rfc-editor.org/rfc/rfc8216.html#section-4.3.2.6

## First live break correction

Nick reported that automatic mute worked for the first commercial but audio returned too early. The current playlist reproduced a parser defect: a 180.013-second CUE-OUT break had timestamp/codec discontinuities between its individual ads. Resetting cue state at each discontinuity classified only the first 30.030 seconds as ad and the remaining 149.983 seconds as unknown, which released mute.

The parser now preserves cue scope and its original deadline across a discontinuity when a valid new UTC anchor follows. It normalizes sub-millisecond anchor rounding, rejects backwards-clock scope reuse, and still drops to unknown if segments lack a new timestamp or exceed the advertised deadline. Cue-in remains an explicit return to programming. Replaying the fetched playlist now produces one 180.013-second ad span for that break. Synthetic checks cover a six-ad break, early cue-in, missing cue-in/clock, backwards clocks, and anchor precision.

The player also retains the last 30 automatic-mute status transitions in a visible Commercial mute history box, so an early release can be diagnosed after it happens. This history resets on page refresh. The Python correction requires a relay restart; no extension reload is required for this fix. Live alignment still needs another break test.
