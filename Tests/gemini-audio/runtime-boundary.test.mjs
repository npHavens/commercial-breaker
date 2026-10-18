import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const tools = new URL('../../Tools/', import.meta.url);
const evaluation = new Set(['evaluate-gemini-audio.mjs', 'compare-detection.mjs']);

/** Follows relative imports and file reads from the live worker through Tools/. */
function runtimeFiles(name, seen = new Set()) {
  if (seen.has(name)) return seen;
  seen.add(name);
  const source = readFileSync(fileURLToPath(new URL(name, tools)), 'utf8');
  for (const [, dependency] of source.matchAll(/from '\.\/([^']+)'|new URL\('\.\/([^']+)'/g).map(m => [m[0], m[1] ?? m[2]])) {
    if (dependency.endsWith('.mjs')) runtimeFiles(dependency, seen); else seen.add(dependency);
  }
  return seen;
}

test('live worker depends only on runtime modules, not evaluation tools or experiments', () => {
  const files = runtimeFiles('gemini-live-worker.mjs');
  assert.ok(files.has('prompt-common.txt') && files.has('standard-classifier.mjs'), 'walk must reach the moved runtime files');
  for (const name of files) {
    assert.ok(!evaluation.has(name), `runtime imports evaluation tool ${name}`);
    if (name.endsWith('.mjs')) {
      assert.doesNotMatch(readFileSync(fileURLToPath(new URL(name, tools)), 'utf8'), /Experiments\//, `${name} reads Experiments/`);
    }
  }
});
