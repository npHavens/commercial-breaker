# Audio-language-model experiment

Prepared September 27, 2026. After explicit approval, seven saved-clip requests
completed through the interview assistant's Vertex Gemini integration. No continuous
remote recording or playback-control changes were enabled. See [results](results.md). `manifest.json` references seven
existing complete clips; the partial return and old timing-defect recordings are
excluded. Labels are provisional click-based expectations, not ground truth.

## Why test it

The fixed music-rise/crowd-drop rule missed a prospectively marked break because
crowd confidence was already low. Audio-language understanding may recognize
advertising content or game discussion without requiring crowd sound. This is a
hypothesis to test; weak TV audio and competing room voices can defeat these models
too. Do not treat persuasive explanations or model confidence as correctness.

## First experiment

Use `prompt.txt` unchanged with each selected audio clip. The model sees only a
blind sample ID and audio, not the label/marker/filename. It classifies content at
the end and may abstain. Review apparent disagreements against the actual audio;
manual markers are approximate and the seven clips have little ordinary-football
coverage. Record provider, exact model ID, prompt revision, response, duration,
usage, and elapsed request time. Do not call this tiny set an accuracy benchmark.

A remote audio model is the quickest capability check; a local audio-language
model is a separate deployment/latency experiment. Remote upload requires Nick's
choice and approval because these recordings include room conversation. Check
account availability, retention settings, current pricing, and credentials before
implementing remote calls. No API key needs to be pasted into chat.

## If the clip test is useful

Try the most recent eight seconds every five seconds in observation mode. These
are initial experiment settings, not validated detection timing. Use fixed polling
as a backstop: gating only on the old crowd/music heuristic would reproduce its
miss. Keep at most one inference in flight, skip queued stale samples, and associate
responses with the capture route/game generation. A game change invalidates old
responses. Output football/commercial/promo/unclear; never force every sample into
two classes. Model audio is untrusted content, never an instruction to control the
app. The app owns route/mute decisions.

Overlapping eight-second clips every five seconds reprocess 1.6 times the elapsed
audio: a three-hour game submits 4.8 hours before retries. Polling phase, model
latency, and the amount of post-transition evidence all contribute to delay. Two
confirmations add further delay and correlated evidence, not independent proof.
Measure costs and timing before committing to continuous operation.

The microphone path still cannot hear the TV after the TV is muted. The existing
Mac route plus system-audio tap is the proposed observation source during breaks;
LLM inference does not solve that route/capture handoff. Validate return recognition
and handoff independently before enabling any automatic mute/unmute.

## Primary sources checked

- Gemini native audio understanding, including non-speech sounds:
  https://ai.google.dev/gemini-api/docs/audio
- OpenAI audio-input/text-output guide:
  https://developers.openai.com/api/docs/guides/audio-chat-completions
- OpenAI GPT-Audio-1.5 model:
  https://developers.openai.com/api/docs/models/gpt-audio-1.5
- Qwen2-Audio official local model repository:
  https://github.com/QwenLM/Qwen2-Audio

No source establishes accuracy for quiet room recordings of NFL commercials.
Local Apple Silicon runtime compatibility and real-time speed are unmeasured.

## Interview assistant integration

`Tools/evaluate-gemini-audio.mjs` now imports the interview assistant's existing
`getGenAIConfig()` and installed `@google/genai` SDK. It does not modify that project
or copy its credentials. The current configuration resolves to Vertex AI,
`gemini-2.5-pro`, project `interview-assistant-507123`, location `global`, using ADC.
The existing Developer API/Keychain authentication path is preserved by reusing
the resolver. Run from Skybox with Node24 and the existing TypeScript loader:

```sh
node --import /Users/nickhavens/Projects/interview-assistant/app/node_modules/tsx/dist/loader.mjs \
  --env-file=/Users/nickhavens/Projects/interview-assistant/app/.env \
  Tools/evaluate-gemini-audio.mjs --live --limit=1
```

Without `--live`, the runner only lists sample IDs; no credential resolution or
network calls occur. `--only=<sample-id>` selects a specific manifest entry.
At most seven selected clips run sequentially, one request attempt per clip,
with a180-second timeout. Failures stop the batch without retries. Local temporary
mono16kHz PCM16 WAVs are deleted after each request; originals remain untouched.
Only the fixed prompt, blind sampleID, and audio enter the request. Source paths,
marker labels, and filenames stay local. Results include model, usage, latency,
prompt hash, and schema-validated response; exceptions suppress provider payloads.

Local verification passed: SDK/auth resolver loads correctly; request-isolation
and response-validation tests pass; all seven WAV conversions preserve duration.
On September27 automatic approval review rejected the initial upload, requiring
explicit authorization for room microphone audio (including nearby voices) to
Vertex Gemini. That first attempt sent no audio. Nick subsequently approved the exact audio and
destination; all seven requests completed. See [results](results.md).

## Short-sample follow-up

See [eight-second comparison](short-sample-comparison.md) for Pro versus Flash,
measured latency, and disagreements. The harness accepts `--tail-seconds=5..30`,
`--model=gemini-2.5-pro` or `--model=gemini-2.5-flash`, and Flash-only
`--no-thinking`. Defaults retain full clips and the Interview Assistant model.
