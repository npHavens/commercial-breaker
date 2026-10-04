# October 4 detection results

All 24 approved Vertex Gemini requests completed in
`results/2026-10-04T21-19-02.729Z/`. Eight-second audio, Flash 2.5, no thinking,
one request per clip/variant. No playback was changed.

| Metric | Baseline | Minimal | Crowd + commentary |
|---|---:|---:|---:|
| Median request latency | 1.930 s | 1.385 s | 1.338 s |
| Range | 1.669–10.017 s | 1.200–5.468 s | 1.206–1.610 s |
| Total output tokens, 8 requests | 615 | 96 | 96 |
| Agreement with seven provisional clip markers | 5/7 | 2/7 | 4/7 |
| Marked ads classified as program | 1/6 | 0/6 | 1/6 |
| Marked program classified as break | 0/1 | 0/1 | 0/1 |
| Abstentions on seven recorded clips | 1/7 | 5/7 | 2/7 |
| Synthetic silence | program | program | program |

Minimal medians were about 28% and 31% lower than baseline in this single run.
Request latency excludes audio accumulation, polling, confirmation and routing.
The sample set is too small and uneven to establish accuracy or a reliable
latency distribution. The 0/1 false-mute result is particularly uninformative.
`summary.json` includes silence in its 8-sample agreement denominator; the
table above separates recorded-clip marker agreement from the known silence
control. Counts describe raw classifications, not actual automated actions.

| Sample | Provisional marker | Baseline | Minimal | Crowd |
|---|---|---|---|---|
| 093936067ef3 | break | break | unclear | unclear |
| 1a795116a74c | program | program | program | program |
| 3938c2bb8030 | break | break | unclear | program |
| 4c27dd08cd01 | break | program | unclear | unclear |
| 527493504fd7 | break | break | unclear | break |
| 5d3357b47b9d | break | unclear | unclear | break |
| ed7dc1dfb44f | break | break | break | break |

Crowd cues are worth retaining as an experimental variant: they reduced
abstention relative to the strict minimal prompt. One marked ad became program,
however, and there is only one program sample on which to assess their benefit.
The baseline described that disputed sample as a standalone NFL promotion;
that description is a model claim, not independent ground truth. Review the
audio before calling this a confirmed false return.

## Deterministic silence fix

All three prompts hallucinated program on an exactly silent PCM WAV; baseline
even claimed clear announcer analysis with confidence 1. The synthetic payload
was zero-valued audio, so this disagreement does not depend on marker quality.

`Tools/gemini-live-worker.mjs` now checks the validated WAV's final five seconds
before uploading. If all samples are zero it emits unusable locally, with no
request, token usage or positive confirmation. Earlier audio cannot override
a silent decision region. This applies to the existing standard and AirPlay
return modes. It deliberately introduces no unmeasured amplitude threshold;
low-volume noise and speech still require classification. It does not solve
near-silence, room conversation, or a model mistaking an ad for commentary.

The 24 results above are raw provider results obtained before this guard.
They have not been rewritten to claim improved model accuracy. Local tests
verify the guard, fresh-audio recovery and native confirmation reset. Existing
workers were not restarted; newly spawned workers read the updated source.

## Transition follow-up

Baseline reported transition_heard=true on 093936067ef3 and 527493504fd7 only.
Neither has a reviewed within-clip boundary. A boolean alone cannot measure
timing error or tell whether the transition was program→ad, ad→program or
something within the broadcast. No scheduling/confirmation changes were made.

Next evidence needed: several ordinary football segments and contiguous,
reviewed break/return transitions, including quiet speech, studio coverage and
sports-themed promos. Score both false actions and confirmation delay. Use
transition evidence first to test faster resampling; do not let it bypass the
two-prediction rule based on these unreviewed samples.

## Handoff

- State: three-way evaluation complete; boolean candidates remain experimental.
  Source-level digital-silence fix implemented; active playback untouched.
- Verified: 18 Gemini Node tests; Swift confirmation checks; 24 live comparison
  requests. No live verification of the silence guard or packaged AirPlay reload.
- Next: review disagreements and label representative transition clips; then
  select a prompt and measure complete detection delay before viewing modes.
- Remaining roadmap: explicit Computer/AirPlay setting with audio isolation,
  followed by GitHub baseline, TypeScript/React extension and cleanup.
- Git state: still no repository. Native remains built v0.2.41, extension source
  v0.2.21; relaunch/reload statuses unchanged.
- Updated: October 4, 2026, Codex project session.
