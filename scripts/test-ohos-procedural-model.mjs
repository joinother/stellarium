import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';

async function sourceModule(name) {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/' + name + '.ets', import.meta.url), 'utf8');
  return import('data:text/javascript,' + encodeURIComponent(stripTypeScriptTypes(source)));
}
const { proceduralModelKind, proceduralStarColor, proceduralParticles, renderProceduralModel } = await sourceModule('ProceduralDetailModel');
const { modelIdentity, modelDrag } = await sourceModule('DetailModelGeometry');
const kinds = ['star', 'quasar', 'pulsar', 'globular-cluster', 'open-cluster'];

test('catalog types are discriminated without inventing models for unsupported classes', () => {
  const cases = [['Star 恒星', 'star'], ['double star 双星', 'star'], ['variable star 变星', 'star'],
    ['Quasar 类星体', 'quasar'], ['Pulsar 脉冲星', 'pulsar'],
    ['Nebula globular star cluster', 'globular-cluster'], ['Nebula open star cluster', 'open-cluster'],
    ['Exoplanet', ''], ['Planet', ''], ['Satellite', ''], ['Supernova', ''], ['Galaxy', ''], ['Nebula', ''], ['', '']];
  for (const [input, expected] of cases) assert.equal(proceduralModelKind(input), expected, input);
});

test('temperature controls approximate colour; missing values remain neutral', () => {
  assert.deepEqual(proceduralStarColor(NaN), proceduralStarColor(0));
  assert.deepEqual(proceduralStarColor(Infinity), proceduralStarColor(0));
  assert.ok(proceduralStarColor(3000)[0] > proceduralStarColor(3000)[2]);
  assert.ok(proceduralStarColor(15000)[2] > proceduralStarColor(15000)[0]);
});

test('satellite fallback reuses the catalogue icon without lunar or orbit decorations', () => {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  const start = source.indexOf('  private objectInspectorFallbackVisualKind(');
  const method = source.slice(start, source.indexOf('\n  }', start) + 4);
  const Controller = new Function('proceduralModelKind', stripTypeScriptTypes('class Controller {\n' + method + '\n}') + ';return Controller;')(proceduralModelKind);
  for (const [type, objectType, expected] of [['artificial satellite', 'Satellite', 'satellite'],
    ['人造卫星', 'Satellite', 'satellite'], ['artificial', 'Planet', 'satellite'],
    ['moon', 'Planet', 'moon'], ['卫星', 'Planet moon', 'moon'], ['double star', 'Star', 'star']]) {
    const controller = new Controller();
    Object.assign(controller, { selectedType: type, selectedObjectType: objectType });
    assert.equal(controller.objectInspectorFallbackVisualKind(), expected);
  }
  const visual = source.slice(source.indexOf('  tabletInspectorFallbackVisual()'), source.indexOf('  private selectedDisplayValue('));
  const satellite = visual.slice(visual.indexOf("} else if (this.objectInspectorFallbackVisualKind() === 'satellite')"),
    visual.indexOf("} else if (this.objectInspectorFallbackVisualKind() === 'moon')"));
  assert.match(satellite, /getIcon\('catalog_satellite', false\)/);
  assert.match(satellite, /objectFit\(ImageFit.Contain\)/);
  assert.match(satellite, /HitTestMode.None/);
  assert.doesNotMatch(satellite, /Circle\(|Ellipse\(|catalog_moon|onTouch|onClick/);
  assert.match(visual, /!== 'satellite'\) \{\s*Circle\(\)/);
  assert.match(visual, /=== 'satellite' \? Color.Transparent/);
  assert.match(visual, /detail_category_icon_notice/);
});

test('particle realizations stay stable and differ by object identity', () => {
  for (const kind of ['pulsar', 'globular-cluster', 'open-cluster']) {
    const particles = proceduralParticles(kind, 'first');
    assert.deepEqual(particles, proceduralParticles(kind, 'first'));
    assert.notDeepEqual(particles, proceduralParticles(kind, 'second'));
    assert.ok(particles.flat().every(Number.isFinite));
  }
  const globular = proceduralParticles('globular-cluster', 'cluster');
  const open = proceduralParticles('open-cluster', 'cluster');
  const meanRadius = points => points.reduce((sum, point) => sum + Math.hypot(...point.slice(0, 3)), 0) / points.length;
  assert.ok(globular.length > open.length);
  assert.ok(meanRadius(globular) < meanRadius(open));
});

for (const kind of kinds) {
  test(kind + ' renders transparent surroundings and responds to 3D rotation', () => {
    const particles = proceduralParticles(kind, 'catalog-object');
    const initial = modelDrag(modelIdentity(), 0, -100);
    const render = matrix => new Uint8Array(renderProceduralModel(kind, 6000, particles, matrix, 128, 1));
    const frame = render(initial);
    assert.equal(frame.length, 128 * 128 * 4);
    assert.equal(frame[3], 0);
    assert.equal(frame[frame.length - 1], 0);
    const alpha = frame.filter((value, index) => index % 4 === 3);
    assert.ok(alpha.some(value => value > 100));
    assert.ok(alpha.some(value => value === 0));
    assert.notDeepEqual(frame, render(modelDrag(initial, 70, -40)));
  });
}

test('procedural models never install timers or fetch remote resources', () => {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/ProceduralDetailModel.ets', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /setInterval|setTimeout|fetch\(|https?:\/\//);
});

test('missing local media follows resolution instead of attempting to decode a nonexistent file', () => {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  const match = source.match(/private objectInspectorFilePath\(relativePath: string\): string \{([\s\S]*?)\n  \}/);
  assert.ok(match);
  const execute = new Function('fileIo', 'relativePath', match[1]);
  const context = { stellariumFilesDir: () => '/sandbox' };
  assert.equal(execute.call(context, { accessSync: () => false }, 'nebulae/default/n7006.png'), '');
  assert.equal(execute.call(context, { accessSync: () => true }, 'textures/moon.png'), '/sandbox/stellarium/textures/moon.png');
  assert.equal(execute.call(context, { accessSync: () => { throw new Error('denied'); } }, 'textures/moon.png'), '');
});

test('immersive modal blocks underlying sky hit tests without suppressing its controls', () => {
  const source = readFileSync(new URL('../harmonyos/ets-source/pages/MainWindowNativeNode.ets', import.meta.url), 'utf8');
  const overlay = source.split('private objectInspectorModelOverlay()')[1].split('private handleObjectInspectorModelTouch')[0];
  assert.match(overlay, /HitTestMode.BLOCK_HIERARCHY/);
  assert.doesNotMatch(overlay, /HitTestMode.Transparent/);
  assert.match(overlay, /id\('object-model-close'\)/);
  assert.match(source, /id\('object-model-inline-stage'\)\s*\.hitTestBehavior\(HitTestMode.BLOCK_HIERARCHY\)/);
  assert.match(source, /width\(this.objectInspectorInlineModelSize\(\)\).height\(this.objectInspectorInlineModelSize\(\)\)/);
  assert.doesNotMatch(overlay, /modelNotice\(\).*maxLines/);
});
