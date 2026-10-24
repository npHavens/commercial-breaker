# Eight-second Gemini comparison

September 27, 2026. Fourteen additional requests used shortened versions of the same seven approved clips, through the same Interview Assistant Vertex authentication. No continuous recording uploads or playback changes. Original full-clip results remain unchanged.

| Condition | Median request time | Range |
|---|---:|---:|
| Pro · full clip | 8.29s | 7.68–9.89s |
| Pro · 8 seconds | 8.61s | 5.14–11.06s |
| Flash · 8 seconds · thinking off | 1.61s | 1.32–2.99s |

Latency measures the API call, not recording, polling phase, conversion, or broadcast-to-detection delay. Runs were single passes; Pro and Flash batches overlapped in wall-clock time.

| Sample | Provisional marker | Full Pro | 8s Pro | 8s Flash |
|---|---|---|---|---|
| 093936067ef3 | commercial | commercial | commercial | commercial |
| 1a795116a74c | football | football | football | football |
| 3938c2bb8030 | commercial | commercial | promo | promo |
| 4c27dd08cd01 | commercial | commercial | unclear | commercial |
| 527493504fd7 | commercial | commercial | football | commercial |
| 5d3357b47b9d | commercial | commercial | commercial | commercial |
| ed7dc1dfb44f | commercial | commercial | commercial | commercial |

## Interpretation

Flash distinguished the sole football sample from all six provisionally marked breaks, classifying one as a promo. Exact four-class agreement with commercial markers is therefore 6/7, or 7/7 only if commercial and promo are grouped as breaks. Pro on short samples returned unclear for one marked commercial and football for another. The latter described a return to broadcast that Flash did not report. Neither explanation has been independently verified by listening.

Shortening context materially changes results. Some explanations rely on music or absence of football sounds despite the prompt discouraging that inference. Nearby-voice and audibility judgments also vary. Confidence is uncalibrated. Seven selected examples, only one football example, approximate marker timing, and one request per condition cannot establish accuracy, false-positive rate, or reliable football return detection.

## Next bounded experiment

Use Flash as the latency baseline for an explicitly enabled live observation mode. Display and log suggestions while leaving mute and routing manual. Collect ordinary football, ad transitions, promos, quiet TV, room speech, and channel changes. Preserve unknown results; ignore stale results after a route/game change; allow only one request in flight and never queue old audio. Review disputed samples before adjusting prompts. Do not use either model to automatically unmute on this evidence.

The existing app has not been wired to continuous remote sampling. Consent for this experiment covered the seven saved clips, including nearby voices; live sampling needs a clear user-facing start/stop control and scope. Gemini 2.5 Flash is an experimental comparison model; check availability/lifecycle before a lasting default.

## Reproduce

Use the command in README with `--tail-seconds=8 --model=gemini-2.5-pro`, or `--tail-seconds=8 --model=gemini-2.5-flash --no-thinking`. `--live` transmits audio; omitting it performs a dry run. Model overrides do not modify Interview Assistant configuration. All seven converted tails were independently checked with the WAV reader: exactly 128,000 mono PCM16 frames at 16 kHz (8 seconds). The three Node validation/isolation/offset tests passed.
