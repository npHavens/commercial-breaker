const { test } = require('node:test');
const assert = require('node:assert/strict');
const { existsSync, readdirSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const root = resolve(__dirname, '../../SafariExtension');
const dist = resolve(root, 'dist');
const read = (file) => readFileSync(resolve(root, file), 'utf8');

// Nothing links the extension's files together: the manifest, the popup page and script-injection
// calls name them only as strings. A wrong one fails quietly in Safari: the DIRECTV autoload logs a
// console warning and the handoff correction stops attaching.
function namedFiles() {
  const manifest = JSON.parse(read('manifest.json'));

  const named = [...manifest.background.scripts, manifest.action.default_popup]
    .map((file) => ({ by: 'manifest.json', file }));

  for (const [, file] of read('popup.html').matchAll(/(?:src|href)="([^"]+)"/g)) named.push({ by: 'popup.html', file });

  // The scripts Safari runs: any still at the extension root, and everything built into dist/.
  const scripts = [
    ...readdirSync(root).filter((name) => name.endsWith('.js')),
    ...readdirSync(dist).filter((name) => name.endsWith('.js')).map((name) => `dist/${name}`)
  ];

  for (const script of scripts) {
    for (const [, list] of read(script).matchAll(/files:\s*\[([^\]]*)\]/g)) {
      for (const [, file] of list.matchAll(/['"]([^'"]+)['"]/g)) named.push({ by: script, file });
    }
  }

  return named;
}

test('the extension has been built', () => {
  assert.ok(existsSync(dist), 'SafariExtension/dist is missing: run npm run build:extension (npm test does this first)');
});

test('every file the manifest, popup page and injection calls name exists', { skip: !existsSync(dist) }, () => {
  for (const { by, file } of namedFiles()) {
    assert.ok(existsSync(resolve(root, file)), `${by} names ${file}, which does not exist`);
  }
});

test('the injection scan finds the DIRECTV correction and the AirPlay panel', { skip: !existsSync(dist) }, () => {
  // Guards the scan itself: if the pattern stopped matching, the check above would pass on nothing.
  const named = namedFiles();
  assert.ok(named.some(({ by, file }) => by === 'dist/directv-autoload.js' && file === 'dist/directv-airplay-recovery.js'));
  assert.ok(named.some(({ by, file }) => by === 'popup.js' && file === 'dist/airplay-session.js'));
});
