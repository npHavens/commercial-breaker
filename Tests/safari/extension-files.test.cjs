const { test } = require('node:test');
const assert = require('node:assert/strict');
const { existsSync, readdirSync, readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const root = resolve(__dirname, '../../SafariExtension');
const read = (file) => readFileSync(resolve(root, file), 'utf8');

// The extension has no build step, so a file named by the manifest, the popup page or a
// script-injection call is only a string. A wrong one fails quietly in Safari: the DIRECTV
// autoload logs a console warning and the handoff correction stops attaching.
function namedFiles() {
  const manifest = JSON.parse(read('manifest.json'));

  const named = [...manifest.background.scripts, manifest.action.default_popup]
    .map((file) => ({ by: 'manifest.json', file }));

  for (const [, file] of read('popup.html').matchAll(/(?:src|href)="([^"]+)"/g)) named.push({ by: 'popup.html', file });

  for (const script of readdirSync(root).filter((name) => name.endsWith('.js'))) {
    for (const [, list] of read(script).matchAll(/files:\s*\[([^\]]*)\]/g)) {
      for (const [, file] of list.matchAll(/['"]([^'"]+)['"]/g)) named.push({ by: script, file });
    }
  }

  return named;
}

test('every file the manifest, popup page and injection calls name exists', () => {
  for (const { by, file } of namedFiles()) {
    assert.ok(existsSync(resolve(root, file)), `${by} names ${file}, which does not exist`);
  }
});

test('the injection scan finds the DIRECTV correction and the AirPlay panel', () => {
  // Guards the scan itself: if the pattern stopped matching, the check above would pass on nothing.
  const named = namedFiles();
  assert.ok(named.some(({ by, file }) => by === 'directv-autoload.js' && file === 'directv-airplay-recovery.js'));
  assert.ok(named.some(({ by, file }) => by === 'popup.js' && file === 'airplay-session.js'));
});
