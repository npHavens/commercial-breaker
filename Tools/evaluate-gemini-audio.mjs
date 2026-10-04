import { readFile, writeFile, mkdir, mkdtemp, rm, realpath, stat, appendFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { join, resolve, sep } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = fileURLToPath(new URL('../', import.meta.url));
export const responseSchema = {
  type: 'OBJECT',
  properties: {
    state_at_end: { type: 'STRING', enum: ['program', 'commercial', 'promo', 'unclear'] },
    tv_audibility: { type: 'STRING', enum: ['clear', 'faint', 'unusable'] },
    room_speech_overlap: { type: 'STRING', enum: ['present', 'absent', 'uncertain'] },
    transition_heard: { type: 'BOOLEAN' }, evidence: { type: 'STRING' },
    confidence: { type: 'NUMBER', minimum: 0, maximum: 1 },
  },
  required: ['state_at_end', 'tv_audibility', 'room_speech_overlap', 'transition_heard', 'evidence', 'confidence'],
};

/** Validates provider output without treating model confidence as calibrated truth. */
export function parseResult(text) {
  const value = JSON.parse(text);
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid response object');
  for (const field of ['state_at_end', 'tv_audibility', 'room_speech_overlap']) {
    if (!responseSchema.properties[field].enum.includes(value[field])) throw new Error(`Invalid ${field}`);
  }
  if (typeof value.transition_heard !== 'boolean' || typeof value.evidence !== 'string' || value.evidence.length > 2000
      || !Number.isFinite(value.confidence) || value.confidence < 0 || value.confidence > 1) throw new Error('Invalid response fields');
  return Object.fromEntries(responseSchema.required.map(key => [key, value[key]]));
}

/** Only the blind ID, prompt, and audio enter the request; marker labels stay local. */
export function makeContents(sampleId, prompt, audio) {
  if (!/^[a-f0-9]{12}$/.test(sampleId) || !Buffer.isBuffer(audio) || audio.length === 0) throw new Error('Invalid sample input');
  return [{ role: 'user', parts: [{ text: `${prompt}\nBlind sample ID: ${sampleId}` },
    { inlineData: { mimeType: 'audio/wav', data: audio.toString('base64') } }] }];
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
  const app = resolve(process.env.SKYBOX_INTERVIEW_APP ?? join(homedir(), 'Projects/interview-assistant/app'));
  const require = createRequire(join(app, 'package.json'));
  const { GoogleGenAI } = require('@google/genai');
  // Node's tsx loader resolves this existing TypeScript integration, including Keychain fallback.
  const { getGenAIConfig } = await import(pathToFileURL(join(app, 'backend/src/providers/gemini/config.ts')).href);
  const config = getGenAIConfig();
  const model = models[0]?.slice(8) ?? process.env.GEMINI_MODEL?.trim();
  if (noThinking && model !== 'gemini-2.5-flash') throw new Error('No-thinking experiment only supports Flash');
  if (!model || !/^[a-zA-Z0-9._-]+$/.test(model)) throw new Error('Configured GEMINI_MODEL is required');
  const ai = new GoogleGenAI({ ...config, httpOptions: { retryOptions: { attempts: 1 } } });
  const prompt = await readFile(join(root, 'Experiments/audio-model-eval/prompt.txt'), 'utf8');
  const run = join(root, 'Experiments/audio-model-eval/results', new Date().toISOString().replaceAll(':', '-'));
  await mkdir(run, { recursive: true });
  await writeFile(join(run, 'run.json'), JSON.stringify({ model, provider: 'vertexai' in config ? 'vertex' : 'developer-api',
    location: 'vertexai' in config ? config.location : null, samples: samples.map(s => s.sample_id),
    promptSHA256: createHash('sha256').update(prompt).digest('hex'), maxOutputTokens: 4096, timeoutMs: 180000,
    requestAttempts: 1, tailSeconds, thinkingBudget: noThinking ? 0 : 'default', audioEncoding: 'mono PCM16 WAV at 16kHz; no gain adjustment', startedAt: new Date().toISOString() }, null, 2));
  console.log(JSON.stringify({ model, provider: 'vertexai' in config ? 'vertex' : 'developer-api', samples: samples.length, output: run }));
  const allowed = await realpath(join(homedir(), 'Library/Application Support/SkyboxAudioProbe/recordings'));
  for (const sample of samples) {
    const source = await realpath(sample.local_audio);
    if (!source.startsWith(allowed + sep) || !source.endsWith('.wav') || (await stat(source)).size > 8_000_000) throw new Error('Audio outside approved scope');
    const temporary = await mkdtemp(join(tmpdir(), 'skybox-gemini-'));
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
