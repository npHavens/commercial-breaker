# Vertex Gemini audio evaluation — September 27, 2026

Nick explicitly approved sending the seven saved Skybox clips, including nearby
voices, to Vertex Gemini. Seven requests completed, one per clip, with no retries.
The harness reused interview assistant's authentication resolver and installed
Google GenAI SDK, `gemini-2.5-pro`, ADC, project `interview-assistant-507123`, global
location. Interview assistant source and credentials were not modified.

Each request contained the same fixed prompt, a blind sample ID, and mono PCM16
16kHz audio converted locally without amplification. No filename, user marker,
expected state, or session history entered the model request. The model classified
the final five seconds of each roughly30-second clip. Local temporary converted
files were deleted. Provider results and usage remain in the local results folder.

## Result

All seven responses agreed with provisional click-based expectations: six
commercials and one football return. This is **marker agreement, not validated
accuracy**. The dataset is small, heavily biased, selected around transitions,
and lacks independently reviewed boundaries and challenging negative controls.

| Blind sample | Provisional expectation | Model result | Request latency | Model's TV audibility |
|---|---|---|---:|---|
| `093936067ef3` | commercial | commercial | 9.12s | faint |
| `1a795116a74c` | football | football | 8.06s | clear |
| `3938c2bb8030` | commercial | commercial | 8.08s | clear |
| `4c27dd08cd01` | commercial | commercial | 8.29s | clear |
| `527493504fd7` | commercial | commercial | 7.68s | clear |
| `5d3357b47b9d` | commercial | commercial | 9.89s | clear |
| `ed7dc1dfb44f` | commercial | commercial | 8.36s | clear |

Latency: median 8.29s; range 7.68–9.89s.
Measured around the model request, including authentication/network work as needed,
excluding local audio conversion. Sequential requests used default model thinking,
a4096-token output cap and180-second timeout. Thirty-second clip latency is not
proof of live detection delay or latency on shorter inputs.

The failed-heuristic sample `ed7dc1dfb44f` was classified commercial. Gemini described
a transition from a halftime report into a Verizon/iPhone advertisement. This is
the model's description, not a separate human verification of the audio.

All responses reported confidence1.0 and room speech overlap absent; one reported
faint TV audio. These self-reports are not calibrated reliability or proof that no
room conversation was present. Do not gate production decisions on them yet.

Token totals reported by Vertex: 8146 prompt,
558 visible response, 4516 thinking,
13220 total. No dollar-cost estimate is inferred here.

## Decision

Audio-language understanding merits further testing and handled the marked break
that the frozen acoustic rule missed. Playback remains unchanged. Next compare
short rolling windows and measure response latency, abstention, ordinary-football
false positives, and return recognition before integrating automatic actions.
A five-second polling schedule cannot be maintained with one request in flight
at these measured latencies; test shorter samples/model settings and avoid a stale
request queue. Only these seven saved-clip requests were authorized and executed;
continuous remote microphone streaming has not been enabled.
