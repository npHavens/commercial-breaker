const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const read = (file) => readFileSync(resolve(__dirname, '../..', file), 'utf8');
const legacy = (name) => `skybox${name}`;

// Each contract is a name shared by files that never import each other, so a
// half-rename fails silently at runtime. These checks pin both sides.
const contracts = [
  ['relay playback history key', 'commercial-breaker.relay.playback-history', ['Tools/hls_player.html']],
  ['AirPlay panel close event', 'commercial-breaker-airplay-trace-stop',
    ['SafariExtension/airplay-session.js', 'SafariExtension/directv-airplay-recovery.js']],
  ['popup AirPlay attempt log key', 'commercial-breaker.airplay-attempt', ['SafariExtension/popup.js']]
];

for (const [label, name, files] of contracts) {
  test(`${label} is ${name} on every side`, () => {
    // The old name is the new one with its leading product word swapped back.
    const old = name.replace('commercial-breaker', legacy(''));

    for (const file of files) {
      const source = read(file);
      assert.ok(source.includes(name), `${file} must use ${name}`);
      assert.ok(!source.includes(old), `${file} must not use ${old}`);
    }
  });
}

test('no source file under SafariExtension or Tools keeps a legacy kebab or dotted skybox name', () => {
  const { execFileSync } = require('node:child_process');

  const files = execFileSync('git', ['ls-files', 'SafariExtension', 'Tools'], { cwd: resolve(__dirname, '../..'), encoding: 'utf8' })
    .split('\n').filter((file) => /\.(js|html|md|json)$/.test(file));

  const pattern = new RegExp(`${legacy('')}[-.][a-z]`);
  for (const file of files) assert.doesNotMatch(read(file), pattern, `${file} still has a legacy name`);
});
