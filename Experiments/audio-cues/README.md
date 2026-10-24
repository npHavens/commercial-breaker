# Local microphone cue analysis — September 27, 2026

This is observation data, not a commercial detector. Original microphone recordings
stay in `~/Library/Application Support/SkyboxAudioProbe/recordings/`. Only numeric
sound-class scores and recorder metadata are stored here. No audio was uploaded.

## Method

`Tools/analyze-audio-cues.swift` uses Apple's built-in SoundAnalysis `version1`
classifier with its default three-second windows and 50% overlap (one result every
1.5 seconds). Original WAV amplitude is preserved; no normalization or denoising.
Each result includes all class scores, the window's audio time, and original marker
metadata. It uses synchronous file analysis, retains the observer, and fails if the
request fails or completes without results.

Apple documents the API at:
https://developer.apple.com/documentation/soundanalysis/classifying-sounds-in-an-audio-file

These scores indicate sound classes, not commercial probabilities. Overlapping
windows are correlated. Speech may come from the television or people in the room.
The model also produces implausible labels; individual top labels are not verified
sound identifications. No human listening review or transcription has been done.

## Latest session: 301064C5

Five clips produced 87 analysis windows. The microphone was at 50% system input
volume. Four clips contain roughly 30 seconds; the first return clip is partial
because a game change cleared prior audio.

| Clip suffix | User marker | Peak music score | Peak speech score | Observation |
|---|---|---:|---:|---|
| 1473570-1 | Commercial started | 0.64 | 0.60 | Crowd/speech first, then sustained music before the click |
| 1583501-2 | Commercial started | 0.69 | 0.48 | Early crowd, then music; later crowd/shout-like scores also occur |
| 1613836-3 | Football returned (partial) | 0.46 | 0.65 | Several speech-heavy windows; no direct comparison with a 20-second click position |
| 1774115-4 | Commercial started | 0.71 | 0.68 | Speech-heavy lead-in, then music near the click |
| 1805987-5 | Football returned | 0.62 | 0.73 | Music also occurs around return; it cannot indicate direction alone |

In complete clips, the marker is approximately 20 seconds into the file. A window
starting at 18 seconds includes sound through 21 seconds, so it straddles the marker.
The user's clicks are approximate, not adjudicated event boundaries. Do not report
classifier latency relative to these clicks as true commercial detection latency.

The partial return omits 11.741 seconds of preceding context. WAVs concatenate
available audio: their timestamps must not be treated as original monotonic time
without accounting for omissions. The older session (233E4D72) additionally has the
known callback-jitter timing defect and is not suitable for precise timing analysis.

## Decision

Quiet input does contain sound patterns the model can classify. This does not
establish that TV speech is intelligible, or separated from nearby conversation.
Do not raise input gain further based on level measurements alone.

Music onset remains a candidate feature across games. It cannot be the mute or
unmute trigger by itself: music is present at both starts and returns. Crowd and
speech also overlap both states and can be affected by room voices or ad content.

Next useful evidence is ordinary football containing replays/music and room
conversation, plus more complete start/return pairs. Evaluate sustained sequences
and false alarms before coupling results to automatic routing. Current clips alone
cannot establish false alarms per hour or reliable detection accuracy.

## Reproduce

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -module-cache-path /tmp/skybox-module-cache \
  Tools/analyze-audio-cues.swift -o /tmp/skybox-analyze-cues
/tmp/skybox-analyze-cues '<recording-session-directory>' '<analysis-output-directory>'
```

Output JSON files are replaced atomically on a repeated run. Existing audio is never
modified. All eight saved clips across both sessions completed analysis successfully.
