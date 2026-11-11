import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

const read = path => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const panel = read('harmonyos/ets-source/panels/panels/AstronomyCalendarPanel.ets');
const selector = panel.slice(panel.indexOf('  private art('), panel.indexOf('  private date('))
  .replace('private art(', 'function art(');
const selectArt = new Function('$r', `${stripTypeScriptTypes(selector)}; return art;`)(name => name);
const artwork = resource => read(`harmonyos/resources/base/media/${resource.replace('app.media.', '')}.svg`);
const cases = [
  ...[0, 1, 2, 3].map(phaseIndex => ({ kind: 'moon-phase', phaseIndex })),
  { kind: 'meteor-peak' }, { kind: 'solar-term' },
  ...['Mercury', 'Venus', 'Mars', 'Saturn', 'Uranus', 'Neptune', 'Jupiter'].map(target => ({ kind: 'planetary-event', target }))
];

test('all event artwork routes resolve to separate proportional detail and timeline assets', () => {
  for (const event of cases) {
    const timeline = selectArt(event, false);
    const detail = selectArt(event, true);
    assert.equal(detail, `${timeline}_detail`);
    assert.match(artwork(timeline), /width="720" height="240" viewBox="0 0 720 240"/);
    assert.match(artwork(detail), /width="396" height="240" viewBox="0 0 396 240"/);
  }
  assert.equal(selectArt({ kind: 'moon-phase', phaseIndex: 2 }, true), 'app.media.calendar_moon_2_detail');
  assert.match(panel, /Image\(this\.art\(event, true\)\)\.width\('100%'\)\.aspectRatio\(1\.65\)\.objectFit\(ImageFit\.Contain\)/);
  assert.match(panel, /Image\(this\.art\(event, false\)\)\.width\('100%'\)\.height\(108\)\.objectFit\(ImageFit\.Cover\)/);
  assert.match(panel, /Row\(\)\.width\('100%'\)\.aspectRatio\(1\.65\)\.backgroundColor\(this\.c\.nightMask\)/);
  assert.doesNotMatch(panel, /height\(detail \? 196/);
});

test('full moon remains a complete circular disc inside detail artwork at narrow and wide widths', () => {
  const svg = artwork('app.media.calendar_moon_2_detail');
  const transform = svg.match(/transform="translate\(([\d.]+) ([\d.]+)\) scale\(([\d.]+)\) translate\((-?[\d.]+) (-?[\d.]+)\)"/);
  assert.ok(transform);
  const [centerX, centerY, scale, offsetX, offsetY] = transform.slice(1).map(Number);
  const disc = svg.match(/<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)" fill="url\(#moon\)"\/>/);
  assert.ok(disc);
  const [discX, discY, radius] = disc.slice(1).map(Number);
  for (const width of [260, 324, 420, 600]) {
    const imageScale = width / 396;
    const height = width / 1.65;
    const actualX = (centerX + (discX + offsetX) * scale) * imageScale;
    const actualY = (centerY + (discY + offsetY) * scale) * imageScale;
    const actualRadius = radius * scale * imageScale;
    assert.ok(actualX - actualRadius > 0 && actualX + actualRadius < width);
    assert.ok(actualY - actualRadius > 0 && actualY + actualRadius < height * 0.6);
    assert.ok(Math.abs(width / 396 - height / 240) < 1e-12);
  }
  assert.doesNotMatch(svg, /fill="#111c2c"/);
});

test('Mercury craters and shade are clipped to its disc in both artwork variants', () => {
  for (const detail of [false, true]) {
    const svg = artwork(selectArt({ target: 'Mercury' }, detail));
    const clip = svg.match(/<clipPath id="mercury-disc">(<circle[^>]+\/>)/);
    assert.ok(clip);
    assert.match(clip[1], /cx="560" cy="120" r="55"/);
    const clipped = svg.match(/<g clip-path="url\(#mercury-disc\)">([\s\S]*?)<\/g>/);
    assert.ok(clipped);
    assert.equal((clipped[1].match(/fill="#73869f"/g) || []).length, 22);
    assert.equal((svg.match(/fill="#73869f"/g) || []).length, 22);
    assert.match(clipped[1], /fill="#141c2b"/);
  }
});
