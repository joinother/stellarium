import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

const mediaSource = readFileSync(new URL('../harmonyos/ets-source/common/derive/media.ets', import.meta.url), 'utf8');
const controllerSource = readFileSync(
  new URL('../harmonyos/ets-source/capability/ObjectInspectorMediaController.ets', import.meta.url), 'utf8');

function extractFunction(name) {
  const start = mediaSource.indexOf('export function ' + name + '(');
  assert.ok(start >= 0, name + ' is missing');
  const end = mediaSource.indexOf('\n}', start) + 2;
  const body = mediaSource.slice(start, end).replace('export ', '');
  return new Function(stripTypeScriptTypes(body) + '\nreturn ' + name + ';')();
}

const imageName = extractFunction('objectInspectorDeepSkyImageName');

test('the Magellanic Clouds resolve to their own packaged images', () => {
  assert.equal(imageName('galaxy', 'pgc 17223 large magellanic cloud 大麦哲伦云'), 'lmc.png');
  assert.equal(imageName('galaxy', '大麦哲伦云'), 'lmc.png');
  assert.equal(imageName('galaxy', 'ngc 292 small magellanic cloud 小麦哲伦云'), 'smc.png');
  assert.equal(imageName('galaxy', 'ngc 292'), 'smc.png');
  assert.ok(existsSync(new URL('../nebulae/default/lmc.png', import.meta.url)));
  assert.ok(existsSync(new URL('../nebulae/default/smc.png', import.meta.url)));
});

test('unknown deep-sky objects do not borrow another object image', () => {
  assert.equal(imageName('galaxy', 'pgc 999999 unnamed galaxy'), '');
  assert.equal(imageName('nebula', 'unknown dark nebula'), '');
  assert.equal(imageName('galaxy', 'no catalogue identifier'), '');
  // Horsehead/Barnard 33 and M43 are distinct objects from M42; never reuse M42.
  assert.equal(imageName('nebula', 'horsehead nebula barnard 33'), 'barnard33.png');
  assert.equal(imageName('nebula', 'm 43'), 'm43.png');
  assert.equal(imageName('galaxy', 'ngc 224'), 'm31.png');
  assert.doesNotMatch(mediaSource, /objectInspectorFallbackImageName/);
  assert.doesNotMatch(mediaSource, /'horsehead'|'barnard 33'|'b33': 'm42\.png'/);
  assert.doesNotMatch(controllerSource, /objectInspectorFallbackImageName|fallbackImageName/);
});
