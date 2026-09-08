import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const hash = path => createHash('sha256').update(readFileSync(path)).digest('hex');
const manifest = JSON.parse(readFileSync(root + 'build/qt-platform-patch/manifest.json', 'utf8'));
const library = root + 'build/qt-platform-patch/compiled/plugins/platforms/libqohos.so';
const target = root + 'build/libstellarium-harmonyos/entry/libs/arm64-v8a/';
assert.equal(manifest.revision, '97575d35c0cecdc0fb4e12fc3575afaa9fd9d3f1');
assert.equal(manifest.patch, 'clipboard-notification-20260908');
assert.equal(hash(root + 'harmonyos/qt-platform-patch/clipboard-notification.patch'), manifest.patchSha256, 'rebuild Qt platform after changing its patch');
assert.equal(hash(library), manifest.librarySha256, 'patched library checksum mismatch');
for (const [name, expected] of Object.entries(manifest.sdkLibraries)) {
  assert.ok(['libQt6Core.so', 'libQt6Gui.so', 'libQt6OpenGL.so'].includes(name));
  assert.equal(hash(target + name), expected, 'Qt dependency mismatch: ' + name);
}
assert.equal(Object.keys(manifest.sdkLibraries).length, 3);
if (process.argv.includes('--sync')) copyFileSync(library, target + 'libqohos.so');
assert.equal(hash(target + 'libqohos.so'), manifest.librarySha256, 'generated project contains an unpatched Qt platform');
console.log('Qt clipboard notification patch and three SDK dependencies verified.');
