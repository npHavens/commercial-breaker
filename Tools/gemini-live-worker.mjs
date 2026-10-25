import { returnPrompt, returnSchema, parseReturnResult } from './return-classifier.mjs';
import { sportPrompt } from './sport-prompt.mjs';
import { minimalPrompt, minimalSchema, parseMinimalResult } from './minimal-classifier.mjs';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { makeContents } from './gemini-request.mjs';
import { parseResult, responseSchema } from './standard-classifier.mjs';
import { createVertexClient, setupFailure } from './vertex-client.mjs';

export const MODEL = 'gemini-3.8-flash';
export const MAX_LINE_BYTES = 540_000;
const WAV_BYTES = 44 + 8 * 16_000 * 2;

/** The recorder sends a canonical PCM WAV, avoiding ambiguous or oversized containers. */
export function parseRequest(line) {
  if (Buffer.byteLength(line) > MAX_LINE_BYTES) throw new Error('invalid-request');
  const request = JSON.parse(line);
  if (!request || !/^[a-f0-9]{12}$/.test(request.id) || typeof request.audio !== 'string'
      || request.audio.length !== Math.ceil(WAV_BYTES / 3) * 4
      || !/^[A-Za-z0-9+/]+={0,2}$/.test(request.audio)) throw new Error('invalid-request');
  const audio = Buffer.from(request.audio, 'base64');
  if (audio.length !== WAV_BYTES || audio.toString('base64') !== request.audio
      || audio.toString('ascii', 0, 4) !== 'RIFF' || audio.readUInt32LE(4) !== WAV_BYTES - 8
      || audio.toString('ascii', 8, 16) !== 'WAVEfmt ' || audio.readUInt32LE(16) !== 16
      || audio.readUInt16LE(20) !== 1 || audio.readUInt16LE(22) !== 1
      || audio.readUInt32LE(24) !== 16_000 || audio.readUInt32LE(28) !== 32_000
      || audio.readUInt16LE(32) !== 2 || audio.readUInt16LE(34) !== 16
      || audio.toString('ascii', 36, 40) !== 'data' || audio.readUInt32LE(40) !== WAV_BYTES - 44) {
    throw new Error('invalid-request');
  }
  return { id: request.id, audio };
}

function safeUsage(metadata) {
  return Object.fromEntries(['promptTokenCount', 'candidatesTokenCount', 'thoughtsTokenCount', 'totalTokenCount']
    .filter(key => Number.isSafeInteger(metadata?.[key]) && metadata[key] >= 0)
    .map(key => [key, metadata[key]]));
}

/** Only fixed categories and numeric HTTP status leave the worker. */
export function classifyFailure(error) {
  const status = Number.isInteger(error?.status) && error.status >= 100 && error.status <= 599 ? error.status : null;
  const code = error?.code ?? error?.cause?.code;
  const transient = status === 408 || status === 429 || (status !== null && status >= 500)
    || ['ECONNRESET', 'ETIMEDOUT', 'EAI_AGAIN', 'ENETUNREACH', 'UND_ERR_CONNECT_TIMEOUT', 'UND_ERR_SOCKET'].includes(code);
  return { error: transient ? 'temporary-failure' : 'request-failed', ...(status === null ? {} : { httpStatus: status }) };
}

/** No queue or retry: a slow request never creates a backlog of stale predictions. */
export function createWorker({ generateContent, prompt, emit, timeoutMs = 20_000, returnDetection = false, crowdDetection = false }) {
  let active = null;
  let closed = false;
  return {
    async accept(line) {
      if (closed) return;
      let request;
      try { request = parseRequest(line); }
      catch { emit({ id: null, error: 'invalid-request' }); return; }
      if (active) { emit({ id: request.id, error: 'busy' }); return; }
      // The validated PCM16 payload's decision region is exactly five seconds.
      // Gemini can hallucinate commentary on zero samples; do not upload silence.
      // No amplitude threshold: quiet but nonzero audio still reaches the model.
      if (!request.audio.subarray(request.audio.length - 5 * 16_000 * 2).some(byte => byte !== 0)) {
        emit({ id: request.id, result: { state_at_end: 'unusable', audio_usable: false },
          elapsedMs: 0, usage: {}, source: 'local-digital-silence' });
        return;
      }
      const controller = new AbortController();
      active = controller;
      const started = performance.now();
      let timedOut = false;
      const timer = setTimeout(() => { timedOut = true; controller.abort(); }, timeoutMs);
      try {
        const response = await generateContent({ model: MODEL,
          contents: makeContents(request.id, prompt, request.audio), config: {
            responseMimeType: 'application/json', responseSchema: crowdDetection ? minimalSchema : returnDetection ? returnSchema : responseSchema, maxOutputTokens: 4096,
            // Gemini 3 deprecates thinkingBudget (intermittent 400s); LOW is 3.8 Flash's lowest level.
            thinkingConfig: { thinkingLevel: 'LOW' }, abortSignal: controller.signal,
          } });
        if (closed) return;
        if (timedOut) { emit({ id: request.id, error: 'timeout' }); return; }
        if (response.candidates?.[0]?.finishReason !== 'STOP') {
          emit({ id: request.id, error: 'incomplete-response' }); return;
        }
        let result;
        try {
          result = (crowdDetection ? parseMinimalResult : returnDetection ? parseReturnResult : parseResult)(response.text ?? '');
          // The AirPlay system-audio leg only supplies return evidence, never a new break.
          if (crowdDetection && returnDetection) {
            result.state_at_end = !result.decision_usable ? 'unusable' : result.program ? 'program' : 'not_program';
          }
        }
        catch { emit({ id: request.id, error: 'invalid-response' }); return; }
        emit({ id: request.id, result, elapsedMs: Math.round(performance.now() - started), usage: safeUsage(response.usageMetadata) });
      } catch (error) {
        // Provider errors can contain credentials or audio. Only fixed codes cross stdout.
        if (!closed) emit({ id: request.id, ...(timedOut ? { error: 'timeout' } : classifyFailure(error)) });
      } finally { clearTimeout(timer); active = null; }
    },
    close() { closed = true; active?.abort(); },
  };
}

/** Bounded framing avoids readline buffering arbitrarily large malformed input. */
export function createLineReader(onLine, onInvalid) {
  let pending = Buffer.alloc(0);
  let discarding = false;
  return chunk => {
    for (let start = 0; start < chunk.length;) {
      const newline = chunk.indexOf(10, start);
      const end = newline < 0 ? chunk.length : newline;
      if (!discarding && pending.length + end - start > MAX_LINE_BYTES) {
        pending = Buffer.alloc(0); discarding = true; onInvalid();
      }
      if (!discarding) pending = Buffer.concat([pending, chunk.subarray(start, end)]);
      if (newline >= 0) {
        if (!discarding) onLine(pending.toString('utf8'));
        pending = Buffer.alloc(0); discarding = false;
      }
      start = newline < 0 ? chunk.length : newline + 1;
    }
  };
}

async function main() {
  const ai = await createVertexClient();
  const sport = process.env.SKYBOX_SPORT || 'football';
  const returnDetection = process.env.SKYBOX_RETURN_DETECTION === '1';
  const crowdDetection = sport === 'football';
  const prompt = crowdDetection ? minimalPrompt(sport, { crowdCues: true })
    : returnDetection ? returnPrompt(sport) : sportPrompt(await readFile(new URL('./prompt-common.txt', import.meta.url), 'utf8'), sport);
  const emit = record => process.stdout.write(JSON.stringify(record) + '\n');
  const worker = createWorker({ generateContent: args => ai.models.generateContent(args), prompt, emit, returnDetection, crowdDetection });
  process.stdin.on('data', createLineReader(line => { void worker.accept(line); }, () => emit({ id: null, error: 'invalid-request' })));
  const close = () => { worker.close(); process.exit(0); };
  process.stdin.on('end', close);
  process.stdin.on('error', close);
  process.on('SIGTERM', close);
  process.on('SIGINT', close);
  process.stdout.on('error', close);
  emit({ ready: true, model: MODEL, sport, returnDetection,
    classifier: crowdDetection ? 'crowd-minimal-v2' : returnDetection ? 'sport-return' : 'sport-standard',
    promptSHA256: createHash('sha256').update(prompt).digest('hex') });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    process.stdout.write(JSON.stringify({ ready: false, error: setupFailure(error) }) + '\n');
    process.exitCode = 1;
    // Exiting now would race the app's termination handler and lose the reason.
    process.stdin.resume();
  });
}
