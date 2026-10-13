import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import assert from 'node:assert/strict'
import { buildAstronomyCard, normalizeAstronomyCard, moonSilhouette } from '../harmonyos/ets-source/form/AstronomyCardData.ts'

const root = process.cwd()
const formConfigPath = path.join(root, 'harmonyos/resources/base/profile/form_config.json')
const syncScriptPath = path.join(root, 'scripts/sync-ohos-build-sources.sh')
const formAbilityPath = path.join(root, 'harmonyos/ets-source/form/SkyInstrumentFormAbility.ets')
const cardDataPath = path.join(root, 'harmonyos/ets-source/form/AstronomyCardData.ts')

const formConfig = JSON.parse(fs.readFileSync(formConfigPath, 'utf8'))
const forms = Array.isArray(formConfig.forms) ? formConfig.forms : []
const expectedForms = [
  { name: 'sky_instrument_card', source: 'SkyInstrumentCard.ets', route: "kind: 'overview'" },
  { name: 'sky_instrument_tonight_card', source: 'SkyInstrumentTonightCard.ets', route: "kind: 'tonight'" },
  { name: 'sky_instrument_satellite_card', source: 'SkyInstrumentSatelliteCard.ets', route: "kind: 'satellite'" },
  { name: 'sky_instrument_moon_card', source: 'SkyInstrumentMoonCard.ets', route: "kind: 'moon'" },
  { name: 'sky_instrument_meteor_card', source: 'SkyInstrumentMeteorCard.ets', route: "kind: 'meteor'" },
  { name: 'sky_instrument_compact_card', source: 'SkyInstrumentCompactCard.ets', route: "kind: 'compact'" }
]

if (forms.filter((form) => form.isDefault === true).length !== 1) {
  throw new Error('service card configuration must have exactly one default form')
}

const syncScript = fs.readFileSync(syncScriptPath, 'utf8')
const formAbility = fs.readFileSync(formAbilityPath, 'utf8')
const cardData = fs.readFileSync(cardDataPath, 'utf8')
for (const expected of expectedForms) {
  const form = forms.find((candidate) => candidate.name === expected.name)
  if (!form || form.src !== `./ets/form/${expected.source}`) {
    throw new Error(`missing or mismatched form configuration: ${expected.name}`)
  }
  const sourcePath = path.join(root, 'harmonyos/ets-source/form', expected.source)
  if (!fs.existsSync(sourcePath)) throw new Error(`missing form source: ${sourcePath}`)
  if (!syncScript.includes('harmonyos/ets-source')) throw new Error(`sync script does not mirror the ets-source tree (needed for ${expected.source})`)
  const cardSource = fs.readFileSync(sourcePath, 'utf8')
  if (!cardSource.includes(expected.route)) throw new Error(`missing card route: ${expected.name}`)
  for (const key of ['moonSummary', 'planetSummary', 'observationSummary', 'satelliteSummary', 'updatedAt']) {
    assert.ok(cardSource.includes(`@Provider() ${key}:`), `missing entry data provider: ${expected.name}/${key}`)
  }
}

for (const key of ['moonSummary', 'planetSummary', 'meteorSummary', 'satelliteSummary', 'observationSummary', 'updatedAt']) {
  if (!cardData.includes(`${key}:`) && !cardData.includes(`${key}'`)) throw new Error(`snapshot field is not bound: ${key}`)
}
for (const token of ['defaultAstronomyCard', 'normalizeAstronomyCard']) {
  if (!formAbility.includes(token)) throw new Error(`shared card snapshot normalization is missing: ${token}`)
}

const primaryForm = forms.find((form) => form.name === 'sky_instrument_card')
if (!primaryForm || primaryForm.defaultDimension !== '2*4' || primaryForm.description.includes('二十四节气')) {
  throw new Error('primary form must be an astronomy summary card, not a solar-term-only card')
}
const primarySource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/form/SkyInstrumentCard.ets'), 'utf8')
const surfaceSource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/form/AstronomyCardSurface.ets'), 'utf8')
assert.ok(surfaceSource.includes('@Consumer() observationSummary:'), 'shared surface must receive provider updates')
for (const token of ['月相', '行星', '流星雨', '卫星', '观测', 'AstronomyCardSurface', 'borderRadius', '@ComponentV2', '@Local']) {
  if (!primarySource.includes(token) && !surfaceSource.includes(token)) throw new Error(`primary form is missing visual/content token: ${token}`)
}
for (const token of ['cardWidth', 'compact()', 'factGrid()', 'linearGradient', 'onSizeChange']) {
  if (!surfaceSource.includes(token)) throw new Error(`responsive card visual contract is missing: ${token}`)
}
for (const token of ['struct AstronomyFact', '@Param value:', 'AstronomyFact({ label:']) {
  if (!surfaceSource.includes(token)) throw new Error(`reactive fact component contract is missing: ${token}`)
}
if (surfaceSource.includes('private fact(label: string, value: string)')) {
  throw new Error('facts must not use a multi-parameter by-value Builder, which freezes snapshot updates')
}
if (primarySource.includes('二十四节气')) throw new Error('primary form still hard-codes a solar-term-only subtitle')
const mainWindowSource = fs.readFileSync(path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets'), 'utf8')
if (mainWindowSource.includes("'summary': '今夜观测摘要已准备 · 下一节气：")) {
  throw new Error('primary snapshot still gives the next solar term the main summary slot')
}
for (const token of ['publishAstronomyCard', 'persistAlmanacCardSnapshot']) {
  if (!mainWindowSource.includes(token)) throw new Error(`primary snapshot builder is not wired: ${token}`)
}

const now = Date.UTC(2026, 9, 1, 12)
const snapshot = buildAstronomyCard({
  date: '2026-10-01',
  moon: { phaseName: '亏凸月', illumination: 77, age: 20, rise: '2026-10-01T21:15', set: '2026-10-02T10:05' },
  sun: { darkWindowHours: 9.5, astroTwilightEnd: '2026-10-01T19:05', astroTwilightStart: '2026-10-02T04:33' },
  planets: [{ name: '木星', visible: true }, { name: '金星', visible: false }],
  meteorShowers: [{ name: '弱流星雨', zhr: 2 }, { name: '主流星雨', zhr: 20 }],
  satellites: { enabled: true, count: 2915 }
}, now)
assert.equal(snapshot.planetSummary, '1 颗在地平线上')
assert.equal(snapshot.planetNames, '木星')
assert.equal(snapshot.observationSummary, '9.5 小时暗夜')
assert.equal(snapshot.moonRise, '21:15')
assert.equal(snapshot.meteorSummary, '主流星雨')
assert.equal(snapshot.satelliteSummary, '2915 颗本地卫星')
assert.deepEqual(normalizeAstronomyCard(JSON.stringify(snapshot), now), snapshot)
assert.equal(normalizeAstronomyCard(JSON.stringify(snapshot), now + 7 * 3600000).dataStatus, '旧快照')
assert.equal(normalizeAstronomyCard('{bad', now).moonIllumination, '-1')
assert.equal(normalizeAstronomyCard('{"schemaVersion":"2"}', now).dataStatus, '本地快照')
assert.equal(buildAstronomyCard({}, now).satelliteSummary, '目录未启用')
for (const illumination of [0, 25, 50, 75, 100]) {
  assert.ok(!moonSilhouette(112, illumination, 20).includes('NaN'))
}
console.log(`HarmonyOS form card contract and data tests passed: ${expectedForms.length} forms`)
