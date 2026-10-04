# Paramount native HLS investigation

## Evidence (2026-09-19)

- The extension's original-video AirPlay picker selects a wireless target and immediately returns to local playback. The selected video has a blob source and no network `<source>` alternatives. No attribute resets or player removal were logged in those attempts.
- A user-supplied HLS media playlist contains AES-128 encryption with identity key format, HTTPS MPEG-TS segments, and cue-out/cue-in commercial markers. These are candidates for direct playback and commercial timing, not verified functionality.
- A separate native HTML video test reached `loadedmetadata`, then reported media error code 3 (decode). A later wireless target selection did not result in TV playback. Selecting an Apple TV profile and retrying also failed.
- A Python request outside Safari's authenticated session successfully retrieved the live playlist (HTTP 200). Requesting its last referenced encryption-key URL returned HTTP 403. No key material was printed or saved. The key host is `cbsi.live.ott.irdeto.com`; its URL has contentId and keyId parameters.

## Interpretation and next check

Nick confirmed that the working Paramount key request includes bearer authorization and returns HTTP 200. This supports missing authorization as the standalone test's blocker. The Python 403 does not establish the response Safari's native player received, nor prove a codec issue. A [local relay](hls-relay.md) now tests authorized key delivery without putting the token into the native player's URL. Live playback remains to be tested.

Native AirPlay playback remains unverified. Repeated picker invocations cannot resolve the observed local playback error. Keep the existing Paramount player usable while investigating.

The session-specific standalone HTML and downloaded playlist are excluded in the root .gitignore. The original standalone test does not proxy keys. The new relay proxies authorized key requests but does not decrypt video or change the original Paramount player.
