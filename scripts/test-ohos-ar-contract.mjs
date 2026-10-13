import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const source = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets');
const arPanel = read('harmonyos/ets-source/panels/ar/ARPreviewPanel.ets');
const arController = read('harmonyos/ets-source/capability/ARController.ets');
const catalog = read('src/StelOhosCommandCatalog.hpp');
const native = read('src/StelMainView.cpp');
const roadmap = read('docs/harmonyos/research/AR-ENGINE-PORTAL-ROADMAP-2026-09-23.md');
const cli = read('docs/harmonyos/CLI.md');

// The AR preview panel is now a standalone component (panels/ar/ARPreviewPanel.ets)
// driven by capability/ARController.ets; the host only routes activePanel==='ar'.
for (const token of ['ARPreviewPanel', "activePanel === 'ar'"]) {
  assert.match(source, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `${token} missing from ArkUI source`);
}
for (const token of ['setRevealProgress', 'loadCapabilities', "'setARRevealProgress'", "'getARCapabilities'"]) {
  assert.match(arController, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `${token} missing from ARController`);
}

for (const token of ['getARCapabilities', 'getARState', 'setARMode', 'setARRevealProgress']) {
  assert.match(catalog, new RegExp(token), `${token} missing from command catalog`);
  assert.match(native, new RegExp(token), `${token} missing from native command bridge`);
  assert.match(cli, new RegExp(token), `${token} missing from CLI documentation`);
}

assert.match(arPanel, /不会打开摄像头/);
assert.match(arPanel, /sky-only/);
assert.match(roadmap, /相机背景/);
assert.match(roadmap, /环境 Mesh/);
assert.match(roadmap, /抠除地景/);
assert.match(roadmap, /不新增 `INTERNET`/);
console.log('HarmonyOS AR contract passed.');
