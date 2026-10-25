import { readFile, writeFile, mkdir, mkdtemp, rm, realpath, stat } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { join, resolve, sep } from 'node:path';
import { homedir, tmpdir } from 'node:os';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { tailOffsetFrames } from './evaluate-gemini-audio.mjs';
import { makeContents } from './gemini-request.mjs';
import { parseResult, responseSchema } from './standard-classifier.mjs';
import { sportPrompt } from './sport-prompt.mjs';
import { minimalPrompt, minimalSchema, parseMinimalResult } from './minimal-classifier.mjs';
import { createVertexClient } from './vertex-client.mjs';

const root = new URL('../', import.meta.url);
const model = 'gemini-3.8-flash';
let phase = 'setup';

export function summarize(records) {
  return Object.fromEntries(['baseline', 'minimal', 'crowd'].map(variant => {
    const rows = records.filter(row => row.variant === variant);
    const times = rows.map(row => row.elapsedMs).sort((a, b) => a - b);
    const middle = Math.floor(times.length / 2);
    const marked = rows.filter(row => row.expected !== null);
    const counts = expected => marked.filter(row => row.expected === expected).length;
    return [variant, {
      samples: rows.length,
      medianMs: times.length ? (times[middle] + times[Math.floor((times.length - 1) / 2)]) / 2 : null,
      minMs: times[0] ?? null, maxMs: times.at(-1) ?? null,
      outputTokens: rows.reduce((sum, row) => sum + (row.usage.candidatesTokenCount ?? 0), 0),
      markerAgreement: marked.filter(row => row.expected === row.actual).length,
      markedSamples: marked.length,
      programSamples: counts('program'), breakSamples: counts('break'), unclearSamples: counts('unclear'),
      falseMuteCandidates: marked.filter(row => row.expected === 'program' && row.actual === 'break').length,
      falseReturnCandidates: marked.filter(row => row.expected === 'break' && row.actual === 'program').length,
      abstentions: rows.filter(row => row.actual === 'unclear').length,
    }];
  }));
}

function silence() {
  const wav = Buffer.alloc(44 + 8 * 16000 * 2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(16000, 24); wav.writeUInt32LE(32000, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36);
  wav.writeUInt32LE(wav.length - 44, 40);
  return wav;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some(arg => arg !== '--live') || args.length > 1) throw new Error('Invalid arguments');
  const manifest = JSON.parse(await readFile(new URL('Experiments/audio-model-eval/manifest.json', root), 'utf8'));
  if (!Array.isArray(manifest.samples) || manifest.samples.length !== 7) throw new Error('Unexpected corpus');
  const samples = [...manifest.samples, { sample_id: '000000000000', synthetic: true, provisional_tail_label: 'unclear' }];
  if (new Set(samples.map(sample => sample.sample_id)).size !== samples.length
      || samples.some(sample => !/^[a-f0-9]{12}$/.test(sample.sample_id))) throw new Error('Invalid sample IDs');
  const variants = {
    baseline: { prompt: sportPrompt(await readFile(new URL('Experiments/detection-oct4/baseline-common.txt', root), 'utf8'), 'football'), schema: responseSchema, parse: parseResult },
    minimal: { prompt: minimalPrompt('football'), schema: minimalSchema, parse: parseMinimalResult },
    crowd: { prompt: minimalPrompt('football', { crowdCues: true }), schema: minimalSchema, parse: parseMinimalResult },
  };
  if (!args.includes('--live')) {
    console.log(JSON.stringify({ mode: 'dry-run', requests: samples.length * Object.keys(variants).length, model,
      samples: samples.map(sample => sample.sample_id), tailSeconds: 8, variants: Object.keys(variants) }));
    return;
  }
  // Validate and convert the entire approved corpus before credentials or requests.
  const allowed = await realpath(join(homedir(), 'Library/Application Support/SkyboxAudioProbe/recordings'));
  const temporary = await mkdtemp(join(tmpdir(), 'skybox-compare-'));
  try {
    const audio = [];
    for (const sample of samples) {
      if (sample.synthetic) { audio.push(silence()); continue; }
      const source = await realpath(sample.local_audio);
      if (!source.startsWith(allowed + sep) || !source.endsWith('.wav') || (await stat(source)).size > 8_000_000) throw new Error('Invalid source');
      const metadata = JSON.parse(await readFile(source.replace(/\.wav$/, '.json'), 'utf8'));
      const output = join(temporary, sample.sample_id + '.wav');
      execFileSync('/usr/bin/afconvert', ['--offset', String(tailOffsetFrames(metadata, 8)), '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', source, output], { stdio: 'pipe' });
      const bytes = await readFile(output);
      if (bytes.length > 300_000 || bytes.length < 256_044) throw new Error('Unexpected converted size');
      audio.push(bytes);
    }
    const ai = await createVertexClient();
    const run = new URL(`Experiments/detection-oct4/results/${new Date().toISOString().replaceAll(':', '-')}/`, root);
    await mkdir(run, { recursive: true });
    const records = [];
    await writeFile(new URL('run.json', run), JSON.stringify({ model, provider: 'vertex', tailSeconds: 8,
      thinkingLevel: 'LOW', maxOutputTokens: 4096, timeoutMs: 20000, attempts: 1,
      note: 'Rotating variant order; provisional markers, not reviewed ground truth. Silence is synthetic.',
      variants: Object.fromEntries(Object.entries(variants).map(([name, value]) => [name, {
        prompt: value.prompt, schema: value.schema, promptSHA256: createHash('sha256').update(value.prompt).digest('hex'),
      }])) }, null, 2));
    for (const [index, sample] of samples.entries()) {
      const names = Object.keys(variants);
      const offset = index % names.length;
      for (const variant of [...names.slice(offset), ...names.slice(0, offset)]) {
        const settings = variants[variant];
        await writeFile(new URL('progress.json', run), JSON.stringify({ sample_id: sample.sample_id, variant, event: 'request-started' }));
        const started = performance.now();
        phase = 'request';
        const response = await ai.models.generateContent({ model, contents: makeContents(sample.sample_id, settings.prompt, audio[index]), config: {
          responseMimeType: 'application/json', responseSchema: settings.schema, maxOutputTokens: 4096,
          thinkingConfig: { thinkingLevel: 'LOW' }, abortSignal: AbortSignal.timeout(20000),
        } });
        const elapsedMs = performance.now() - started;
        phase = 'validation';
        if (response.candidates?.[0]?.finishReason !== 'STOP') throw new Error('Incomplete response');
        const result = settings.parse(response.text ?? '');
        const actual = ['commercial', 'promo'].includes(result.state_at_end) ? 'break' : result.state_at_end;
        const label = sample.provisional_tail_label;
        const expected = label === 'football' ? 'program' : ['commercial', 'promo'].includes(label) ? 'break' : label === 'unclear' ? 'unclear' : null;
        const usage = Object.fromEntries(['promptTokenCount', 'candidatesTokenCount', 'thoughtsTokenCount', 'totalTokenCount']
          .filter(key => Number.isSafeInteger(response.usageMetadata?.[key]) && response.usageMetadata[key] >= 0)
          .map(key => [key, response.usageMetadata[key]]));
        const record = { sample_id: sample.sample_id, variant, expected, actual, result, elapsedMs, usage,
          audioSHA256: createHash('sha256').update(audio[index]).digest('hex'),
          labelStatus: sample.synthetic ? 'synthetic silence' : sample.label_status };
        records.push(record);
        await writeFile(new URL(`${sample.sample_id}-${variant}.json`, run), JSON.stringify(record, null, 2), { flag: 'wx' });
        console.log(JSON.stringify({ sample: sample.sample_id, variant, actual, elapsedMs: Math.round(elapsedMs) }));
      }
    }
    const summary = summarize(records);
    await writeFile(new URL('summary.json', run), JSON.stringify(summary, null, 2));
    await writeFile(new URL('progress.json', run), JSON.stringify({ event: 'completed', requests: records.length }));
    console.log(JSON.stringify({ output: run.pathname, summary }));
  } finally { await rm(temporary, { recursive: true, force: true }); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => {
    const code = error?.code ?? error?.cause?.code;
    console.error(JSON.stringify({ error: 'comparison-failed', phase,
      status: Number.isInteger(error?.status) ? error.status : null,
      code: ['ENOTFOUND', 'EPERM', 'EACCES', 'ECONNREFUSED', 'ETIMEDOUT'].includes(code) ? code : null }));
    process.exitCode = 1;
  });
}
