import { readFile, writeFile, mkdir, mkdtemp, rm, realpath, stat, appendFile } from 'node:fs/promises';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { join, resolve, sep } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createVertexClient, vertexConfig } from './vertex-client.mjs';
import { makeContents } from './gemini-request.mjs';
import { parseResult, responseSchema } from './standard-classifier.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));

/** The only directory saved clips may be read from. */
export function recordingsRoot(home = homedir()) {
  return join(home, 'Library/Application Support/CommercialBreaker/recordings');
}

/** Computes an exact input-frame offset for a bounded tail sample. */
export function tailOffsetFrames(metadata, seconds) {
  if (!Number.isInteger(seconds) || seconds < 5 || seconds > 30
      || !Number.isInteger(metadata.frames) || metadata.frames <= 0
      || !Number.isFinite(metadata.sampleRate) || metadata.sampleRate < 8000 || metadata.sampleRate > 192000) {
    throw new Error('Invalid tail format');
  }
  const frames = Math.round(seconds * metadata.sampleRate);
  if (frames > metadata.frames) throw new Error('Clip is shorter than requested tail');
  return metadata.frames - frames;
}

/** Runs only the explicitly selected, bounded saved-clip experiment. No recording or playback APIs. */
async function main() {
  const args = process.argv.slice(2);
  if (args.some(x => x !== '--live' && !/^--only=[a-f0-9]{12}$/.test(x) && !/^--limit=[1-7]$/.test(x) && !/^--tail-seconds=(?:[5-9]|[12][0-9]|30)$/.test(x) && !/^--model=gemini-2\.5-(?:pro|flash)$/.test(x) && x !== '--no-thinking')) throw new Error('Invalid arguments');
  const only = args.filter(x => x.startsWith('--only='));
  const limits = args.filter(x => x.startsWith('--limit='));
  if (only.length > 1 || limits.length > 1 || args.filter(x => x === '--live').length > 1) throw new Error('Duplicate arguments');
  const tails = args.filter(x => x.startsWith('--tail-seconds='));
  const models = args.filter(x => x.startsWith('--model='));
  if (tails.length > 1 || models.length > 1 || args.filter(x => x === '--no-thinking').length > 1) throw new Error('Duplicate experiment option');
  const tailSeconds = tails.length ? Number(tails[0].split('=')[1]) : null;
  const noThinking = args.includes('--no-thinking');
  const manifest = JSON.parse(await readFile(join(root, 'Experiments/audio-model-eval/manifest.json'), 'utf8'));
  let samples = manifest.samples;
  if (!Array.isArray(samples) || samples.length > 7 || samples.length === 0) throw new Error('Invalid manifest');
  if (only.length) samples = samples.filter(s => s.sample_id === only[0].slice(7));
  samples = samples.slice(0, Number(limits[0]?.slice(8) ?? 7));
  if (!samples.length) throw new Error('No matching sample');
  if (!args.includes('--live')) {
    console.log(JSON.stringify({ mode: 'dry-run', samples: samples.map(s => s.sample_id), tailSeconds, modelOverride: models[0]?.slice(8) ?? null, noThinking, note: 'No credentials resolved or audio transmitted. Use --live for the authorized experiment.' }));
    return;
  }
  const config = vertexConfig();
  const model = models[0]?.slice(8) ?? process.env.GEMINI_MODEL?.trim();
  if (noThinking && model !== 'gemini-2.5-flash') throw new Error('No-thinking experiment only supports Flash');
  if (!model || !/^[a-zA-Z0-9._-]+$/.test(model)) throw new Error('Configured GEMINI_MODEL is required');
  const ai = await createVertexClient(config);
  const prompt = await readFile(join(root, 'Experiments/audio-model-eval/prompt.txt'), 'utf8');
  const run = join(root, 'Experiments/audio-model-eval/results', new Date().toISOString().replaceAll(':', '-'));
  await mkdir(run, { recursive: true });
  await writeFile(join(run, 'run.json'), JSON.stringify({ model, provider: 'vertex',
    location: config.location, samples: samples.map(s => s.sample_id),
    promptSHA256: createHash('sha256').update(prompt).digest('hex'), maxOutputTokens: 4096, timeoutMs: 180000,
    requestAttempts: 1, tailSeconds, thinkingBudget: noThinking ? 0 : 'default', audioEncoding: 'mono PCM16 WAV at 16kHz; no gain adjustment', startedAt: new Date().toISOString() }, null, 2));
  console.log(JSON.stringify({ model, provider: 'vertex', samples: samples.length, output: run }));
  const allowed = await realpath(recordingsRoot());
  for (const sample of samples) {
    const source = await realpath(sample.local_audio);
    if (!source.startsWith(allowed + sep) || !source.endsWith('.wav') || (await stat(source)).size > 8_000_000) throw new Error('Audio outside approved scope');
    const temporary = await mkdtemp(join(tmpdir(), 'commercial-breaker-gemini-'));
    let started;
    try {
      const converted = join(temporary, 'sample.wav');
      const offset = tailSeconds === null ? [] : ['--offset', String(tailOffsetFrames(
        JSON.parse(await readFile(source.replace(/\.wav$/, '.json'), 'utf8')), tailSeconds))];
      execFileSync('/usr/bin/afconvert', [...offset, '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', source, converted], { stdio: 'pipe' });
      const audio = await readFile(converted);
      if (audio.length > 2_000_000) throw new Error('Converted audio exceeds bounded clip size');
      const contents = makeContents(sample.sample_id, prompt, audio);
      await appendFile(join(run, 'attempts.jsonl'), JSON.stringify({ sample: sample.sample_id, event: 'request-started', at: new Date().toISOString() }) + '\n');
      started = performance.now();
      const response = await ai.models.generateContent({ model, contents, config: {
        responseMimeType: 'application/json', responseSchema, maxOutputTokens: 4096,
        ...(noThinking ? { thinkingConfig: { thinkingBudget: 0 } } : {}),
        abortSignal: AbortSignal.timeout(180_000),
      } });
      const elapsedMs = performance.now() - started;
      const finishReason = response.candidates?.[0]?.finishReason;
      if (finishReason !== 'STOP') throw new Error('Incomplete provider response');
      const result = parseResult(response.text ?? '');
      const record = { sample_id: sample.sample_id, model, tailSeconds, thinkingBudget: noThinking ? 0 : 'default', elapsedMs, finishReason, result,
        usage: response.usageMetadata ?? null, provisional_tail_label: sample.provisional_tail_label,
        label_status: sample.label_status, receivedAt: new Date().toISOString() };
      await writeFile(join(run, sample.sample_id + '.json'), JSON.stringify(record, null, 2), { flag: 'wx' });
      console.log(JSON.stringify({ sample: sample.sample_id, elapsedMs: Math.round(elapsedMs), ...result }));
    } catch (error) {
      // Provider exceptions may contain request payloads. Never print their raw messages/bodies.
      const record = { sample: sample.sample_id, event: 'failed', errorType: error?.name ?? 'Error',
        status: typeof error?.status === 'number' ? error.status : null,
        code: typeof error?.code === 'number' ? error.code : null,
        elapsedMs: started === undefined ? null : performance.now() - started };
      await appendFile(join(run, 'attempts.jsonl'), JSON.stringify(record) + '\n');
      console.error(JSON.stringify(record));
      process.exitCode = 1;
      break; // No silent retries or repeated charges after an error.
    } finally { await rm(temporary, { recursive: true, force: true }); }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(() => { console.error('Evaluation setup failed; check local configuration. Sensitive provider details suppressed.'); process.exitCode = 1; });
}
