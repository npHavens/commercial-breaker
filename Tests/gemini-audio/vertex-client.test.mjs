import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { cp, mkdtemp, realpath, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createVertexClient, setupFailure, vertexConfig } from '../../Tools/vertex-client.mjs';

const tools = fileURLToPath(new URL('../../Tools/', import.meta.url));
const installed = (() => { try { createRequire(import.meta.url).resolve('@google/genai'); return true; } catch { return false; } })();

/** Starts the real worker with only the given settings; no request is ever sent. */
function startWorker(script, env) {
  const child = spawn(process.execPath, [script], { env: { PATH: process.env.PATH, ...env }, stdio: ['pipe', 'pipe', 'ignore'] });
  const first = new Promise((resolve, reject) => {
    let text = '';
    child.stdout.on('data', chunk => {
      text += chunk;
      if (text.includes('\n')) resolve(JSON.parse(text.slice(0, text.indexOf('\n'))));
    });
    child.on('exit', () => reject(new Error('worker exited before reporting setup')));
  });
  const exited = new Promise(resolve => child.on('exit', code => resolve(code)));
  return { child, first, exited };
}

test('Vertex is the only destination; project is required and location defaults to global', () => {
  assert.deepEqual(vertexConfig({ GOOGLE_CLOUD_PROJECT: ' skybox-test ' }),
    { vertexai: true, project: 'skybox-test', location: 'global' });
  assert.deepEqual(vertexConfig({ GOOGLE_CLOUD_PROJECT: 'p', GOOGLE_CLOUD_LOCATION: 'us-central1' }).location, 'us-central1');
  assert.equal(vertexConfig({ GOOGLE_CLOUD_PROJECT: 'p', GOOGLE_CLOUD_LOCATION: '  ' }).location, 'global');
  // An API key never selects a different destination than the consent text names.
  for (const env of [{}, { GOOGLE_CLOUD_PROJECT: '  ' }, { GEMINI_API_KEY: 'k', GOOGLE_GENAI_USE_VERTEXAI: 'false' }]) {
    assert.throws(() => vertexConfig(env), { message: 'configuration-missing' });
  }
});

test('setup failures cross stdout only as fixed categories', () => {
  assert.equal(setupFailure(new Error('configuration-missing')), 'configuration-missing');
  assert.equal(setupFailure(new Error('dependencies-missing')), 'dependencies-missing');
  assert.equal(setupFailure(new Error('/Users/someone/.config/gcloud: permission denied')), 'setup-failed');
  assert.equal(setupFailure(undefined), 'setup-failed');
});

test('client is configured for Vertex with a single attempt', { skip: !installed && 'run npm ci' }, async () => {
  const ai = await createVertexClient({ vertexai: true, project: 'skybox-test', location: 'global' });
  assert.equal(ai.vertexai, true);
  assert.equal(typeof ai.models.generateContent, 'function');
});

test('worker reports missing configuration, then waits for the app to close input', async () => {
  const { child, first, exited } = startWorker(join(tools, 'gemini-live-worker.mjs'), {});
  assert.deepEqual(await first, { ready: false, error: 'configuration-missing' });
  // Staying alive lets the app read the reason before its termination handler runs.
  assert.equal(await Promise.race([exited, new Promise(resolve => setTimeout(() => resolve('running'), 200))]), 'running');
  child.stdin.end();
  assert.equal(await exited, 1);
});

test('worker outside an installed checkout reports missing dependencies', async () => {
  // The worker's entry check compares resolved paths; macOS tmpdir is a symlink.
  const copy = await realpath(await mkdtemp(join(tmpdir(), 'skybox-worker-')));
  try {
    await cp(tools, join(copy, 'Tools'), { recursive: true });
    const { child, first, exited } = startWorker(join(copy, 'Tools/gemini-live-worker.mjs'), { GOOGLE_CLOUD_PROJECT: 'skybox-test' });
    assert.deepEqual(await first, { ready: false, error: 'dependencies-missing' });
    child.stdin.end();
    assert.equal(await exited, 1);
  } finally { await rm(copy, { recursive: true, force: true }); }
});

test('configured worker becomes ready without contacting Vertex', { skip: !installed && 'run npm ci' }, async () => {
  // An empty HOME has no Application Default Credentials; readiness must not need them.
  const home = await mkdtemp(join(tmpdir(), 'skybox-home-'));
  try {
    const { child, first, exited } = startWorker(join(tools, 'gemini-live-worker.mjs'), { GOOGLE_CLOUD_PROJECT: 'skybox-test', HOME: home });
    const ready = await first;
    assert.equal(ready.ready, true);
    assert.equal(ready.classifier, 'crowd-minimal-v2');
    child.stdin.end();
    assert.equal(await exited, 0);
  } finally { await rm(home, { recursive: true, force: true }); }
});
