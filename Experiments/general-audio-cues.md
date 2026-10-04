# General audio cues for commercial transitions

Research and experiment proposal, 2026-09-27. No commercial detector accuracy is established by this document. Start with one detector across games and networks; do not collect network-specific songs or add CBS/Fox rules initially.

## Useful native building blocks

Apple's Sound Analysis framework classifies files or live streams using a built-in classifier or a custom Core ML model. The built-in model recognizes more than 300 kinds of sound; it is not documented as an NFL program/commercial classifier. [Framework overview](https://developer.apple.com/documentation/soundanalysis/)

Apple demonstrates speech, music and singing detection from microphone input, with processing performed locally on-device. These are useful time-varying features, not evidence that a commercial is starting or ending. [Apple's SoundAnalysis presentation](https://developer.apple.com/videos/play/wwdc2021/10036/)

Start with the default 50% analysis-window overlap. Apple notes that no overlap can miss sounds spanning windows; increasing overlap above 50% increases computation. Timestamp predictions using their audio time ranges, not callback arrival time. [Overlap configuration](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest/overlapfactor)

For phrase detection later, macOS 26's SpeechAnalyzer/SpeechTranscriber is an on-device transcription option designed for longer and distant audio. It manages model assets and produces provisional and finalized results; model availability/download and supported locale must be checked. This is a better research direction for continuous TV listening than assuming short dictation requests will run indefinitely. Apple's capabilities do not establish recognition accuracy for a noisy room or NFL commentary. [Apple's SpeechAnalyzer presentation](https://developer.apple.com/videos/play/wwdc2025/277/)

If using older SFSpeechRecognizer, require `supportsOnDeviceRecognition == true` before starting, and set `requiresOnDeviceRecognition = true`. If unavailable, disable transcription rather than silently switching to network recognition. [On-device support](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [request requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)

## Hypotheses to evaluate

These are proposed heuristics, not findings from collected Skybox audio:

| Cue | Possible use | Important counterexample |
| --- | --- | --- |
| Sign-off phrase, such as “we'll be right back” | Candidate outgoing transition | Promo dialogue, quoted speech, partial transcription error; breaks without a sign-off |
| Music onset under commentary | Candidate transition window | Replays, highlights, intros, halftime, stadium music, and music within ads |
| Sustained commentary plus field/crowd ambience after an ad | Candidate program return | Football-themed ads and network promos; music can bridge back into a game |
| Abrupt change in sound mix or level | Locate a possible boundary | Channel switching, replay edits, room noise, volume changes, and audio-route changes |
| Silence or no samples | Capture-health signal only | Muting, buffering, route handoff, permission failure; not proof of an ad |

Music alone gives neither transition direction nor a commercial label. A fixed break duration is also not reliable evidence of program return. The microphone hears nearby speech and other devices; a system tap and room microphone have different acoustics. Keep input source and route changes in the recording metadata and evaluate both sources separately.

## Smallest useful observation experiment

1. Preserve a bounded rolling audio buffer, with explicit start/stop and local files. Save a clip around each **Commercial started**, **Football returned**, or **Channel changed** marker. A proposed useful clip is 30 seconds before and 15 seconds after the click. Delayed marking is expected: store click time separately from any subsequently reviewed boundary time, and retain corrections without overwriting the original marker.
2. Save capture source, sample rate, monotonic audio position, wall-clock time, dropped-buffer/gap indicators and route changes. Do not normalize timestamps across input switches without recording that discontinuity. Record channel changes without requiring a network name; reset pending candidate state on every change.
3. Analyze saved clips offline first. Log sound-class scores and candidate transitions beside the manual markers. Keep playback/muting unchanged in this observation mode. A speech feature can be added after microphone capture quality is verified.
4. Initial review target: at least 10 complete breaks (20 boundaries), across more than one game, plus 20 non-break examples containing replays/music/promos and some uninterrupted football. Include microphone and system-audio samples. These numbers are a practical pilot target, not a statistically sufficient training set or production acceptance threshold; a first few clips can already expose a bad hypothesis.
5. Keep later complete breaks/games out of threshold tuning. Do not split adjacent overlapping windows from the same break across tuning and evaluation. Report false candidates per hour, missed starts/returns, signed boundary delay and premature-return count. A high per-window accuracy can hide unacceptable missed returns or false muting.

## First baseline after recording works

Use explicit states `unknown`, `program`, and `break`, initialized by a user marker for early experiments. Emit a candidate with its contributing cues rather than changing state on a single music prediction. An outgoing candidate might require a sign-off and a nearby sustained music/mix change; a return candidate needs independent return evidence while in `break`. Persistence and thresholds must be chosen from recordings, with an abstain result when evidence conflicts. Keep source handoffs and channel changes out of the evidence window.

If speech is not integrated yet, simply plot/log music, speech and level changes and compare them to markers; do not label them “commercial detected.” SoundAnalysis confidence in “music” is not confidence in “commercial.”

Only connect candidates to automatic AirPlay switching after observation demonstrates useful behavior on held-out clips and live breaks. The existing route experiment establishes capture feasibility, not content detection. Network-specific tuning remains a fallback if the shared cues prove insufficient.
