# Detection comparison — October 4

Candidate prompts are offline only. The worker source now rejects digital
silence locally; existing worker processes are unchanged, and new workers
(including those started by a later capture handoff) load that fix. No app was
rebuilt/relaunched or extension reloaded, and no playback commands were sent.
Native v0.2.41 relaunch and extension v0.2.21 reload/automatic attachment remain
unverified.

## Comparison

`Tools/compare-detection.mjs` compares three football prompts using the same
eight-second tails of the seven previously evaluated recordings, plus one
synthetic silent WAV:

- Baseline: current shared sports prompt and seven-field output, frozen in
  `baseline-common.txt` with sport criteria from `Tools/sport-prompt.mjs`.
- Minimal: `program` and `decision_usable` booleans. A usable negative means a
  standalone ad/promo. Silence, masked audio, unrelated content and ambiguity
  map to unclear, never automatically to a break.
- Crowd: the same minimal schema, but combined crowd ambience and sportscaster
  commentary count as positive coverage evidence without explicit play details.
  An audible sales pitch or standalone promotion overrides those cues. This
  tests Nick's hypothesis that the combination is useful despite occasional ads.

All use Gemini 2.5 Flash, thinking disabled, the same 4096-token ceiling and
20-second request timeout. Requests are sequential, with rotating variant order
and no retries. Each clip is converted once and reused across variants; result
records include its hash. Only the blind ID, prompt and audio enter the request.
Prompts, schemas, hashes, token usage and request latency are saved per run.
The ceiling is held constant to isolate prompt/output differences; reducing it
does not itself guarantee lower latency.

Dry run (no credentials or uploads):

```sh
node Tools/compare-detection.mjs
node --test Tests/gemini-audio/*.test.mjs
```

Authorized upload command:

```sh
node --import /Users/nickhavens/Projects/interview-assistant/app/node_modules/tsx/dist/loader.mjs \
  --env-file=/Users/nickhavens/Projects/interview-assistant/app/.env \
  Tools/compare-detection.mjs --live
```

Results are marker agreement, not validated accuracy. There is only one marked
program clip, six marked ads, and synthetic silence. Labels are approximate
button presses, not independently reviewed audio boundaries. False-mute and
false-return counts are single-prediction candidates, not actual playback
actions: live actions also depend on temporal confirmation. Silence does not
represent all ambiguous audio. This corpus cannot establish representative
quality, UFC accuracy or behavior during AirPlay system capture.

## Transition timing

The current baseline requests `transition_heard`, but native code only logs it.
It does not carry a direction or offset and cannot locate a boundary within
the eight-second window. Break candidates already request a fresh-audio fast
follow-up. Program returns require two positives spanning five fresh seconds.
Those rules remain unchanged during prompt evaluation.

To test closer alignment, collect contiguous, independently marked break and
return windows. Compare confirmation delay against the marked boundary, plus
early false actions. A transition cue could request a faster follow-up while
leaving the current state unchanged; an estimated within-clip boundary could
be logged for scoring before controlling playback. Neither should count as a
second independent program/break prediction. Ordinary camera cuts, replays,
studio handoffs and sports-themed ads are necessary negative controls.

## Verification and checkpoint

- All 18 Gemini Node tests passed, including minimal response validation,
  metric denominators/abstentions, and local silence handling in both classifier
  modes. Swift confirmation checks passed, including unusable return resets.
  Dry run lists 24 requests.
- Initial restricted-environment attempt failed on the first request and
  produced no model result. Automatic approval review rejected the subsequent
  external upload pending explicit consent for these clips to Vertex Gemini.
  Nick then explicitly approved the comparison; all 24 requests completed.
- See [measured results](results.md). Minimal output was faster in this pass,
  but quality did not justify changing the live prompt. Review disagreements
  and collect representative labeled audio before calling detection complete.
- Computer/AirPlay mode and productization remain subsequent roadmap steps.
  Project is still not a Git repository.
