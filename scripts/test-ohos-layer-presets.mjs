import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const plain = source => stripTypeScriptTypes(source
  .replace(/^import[\s\S]*?from\s+'[^']+'\r?\n/gm, '')
  .replace(/^@Observed\r?\n/gm, '')
  .replaceAll('export ', ''))

const models = read('harmonyos/ets-source/common/types/MainWindowModels.ets')
const storeSource = read('harmonyos/ets-source/state/LayerPresetStore.ets')
const bar = read('harmonyos/ets-source/panels/layers/LayerPresetBar.ets')
const tab = read('harmonyos/ets-source/panels/layers/LayerPresetTab.ets')
const layersPanel = read('harmonyos/ets-source/panels/panels/LayersPanel.ets')
const layerController = read('harmonyos/ets-source/capability/LayerController.ets')
const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets')
const i18n = read('harmonyos/ets-source/capability/I18n.ets')

function extractArray(name) {
  const start = models.indexOf(`export const ${name}`)
  assert.ok(start >= 0, `missing ${name}`)
  const arrayStart = models.indexOf('= [', start)
  assert.ok(arrayStart > start, `missing ${name} array`)
  const end = models.indexOf(']', arrayStart)
  return [...models.slice(arrayStart, end).matchAll(/'([^']+)'/g)].map(match => match[1])
}

const marking = extractArray('MARKING_LAYER_ACTION_IDS')
const content = extractArray('CONTENT_LAYER_ACTION_IDS')

const Store = new Function('I18n', 'MARKING_LAYER_ACTION_IDS', 'CONTENT_LAYER_ACTION_IDS', 'LAYER_PRESET_CUSTOM_LIMIT',
  `${plain(storeSource)}; return LayerPresetStore;`)(
  { t: key => key, getLanguage: () => 'zh_CN' }, marking, content, 3)

function makeSnapshot(overrides = {}) {
  const actions = {}
  for (const id of marking.concat(content)) actions[id] = false
  for (const id of ['actionShow_Stars', 'actionShow_Atmosphere', 'actionShow_Ground']) actions[id] = true
  return {
    actions,
    vividAtmosphere: false,
    milkyWayBright: 3,
    realisticStarVisibility: true,
    nightMode: false,
    equatorialMount: false,
    telrad: false,
    ccd: false,
    dsoLabels: true,
    constellationArt3d: false,
    starMagLimit: 6,
    ...overrides
  }
}

function fixture() {
  let persisted = ''
  let applied = undefined
  const hints = []
  let current = makeSnapshot()
  const store = new Store()
  store.attachHooks({
    loadPresetJson: done => done(''),
    persistPresetJson: json => { persisted = json },
    captureSnapshot: done => done(current),
    applySnapshot: (snapshot, done) => { applied = snapshot; done() },
    flashHint: text => hints.push(text),
    refreshState: () => {}
  })
  store.load()
  return {
    store, hints,
    current: value => { current = value },
    applied: () => applied,
    persisted: () => persisted
  }
}

test('five built-in presets keep vivid last and carry the requested scene settings', () => {
  const { store } = fixture()
  assert.deepEqual(store.presets.map(preset => preset.id), ['clean', 'observe', 'photo', 'study', 'vivid'])
  const byId = id => store.presets.find(preset => preset.id === id)
  const clean = byId('clean').snapshot
  assert.equal(clean.actions.actionShow_Atmosphere, true)
  assert.equal(clean.actions.actionShow_Ground, true)
  assert.equal(clean.actions.actionShow_MilkyWay, true)
  assert.equal(clean.milkyWayBright, 6)
  assert.equal(clean.vividAtmosphere, false)

  const observe = byId('observe').snapshot
  assert.equal(observe.actions.actionShow_Atmosphere, true)
  assert.equal(observe.actions.actionShow_Ground, true)
  assert.equal(observe.actions.actionShow_Constellation_Labels, true)
  assert.equal(observe.actions.actionShow_Equatorial_Grid, true)
  assert.equal(observe.realisticStarVisibility, true)
  assert.equal(observe.nightMode, true)
  assert.equal(observe.equatorialMount, true)
  assert.equal(observe.telrad, true)
  assert.equal(observe.starMagLimit, 21)
  assert.equal(observe.actions.actionShow_FOV_Center_Marker, false, 'observation-aid preset must not enable the FOV centre marker')

  const photo = byId('photo').snapshot
  assert.equal(photo.actions.actionShow_Atmosphere, true)
  assert.equal(photo.actions.actionShow_Ground, true)
  assert.equal(photo.actions.actionShow_Equatorial_Grid, true)
  assert.equal(photo.actions.actionShow_Asterism_Labels, true)
  assert.equal(photo.realisticStarVisibility, true)
  assert.equal(photo.ccd, true)
  assert.equal(photo.starMagLimit, 21)

  const study = byId('study').snapshot
  assert.equal(study.actions.actionShow_Atmosphere, false)
  assert.equal(study.actions.actionShow_Ground, false)
  assert.equal(study.actions.actionShow_MistHorizon, false)
  assert.equal(study.starMagLimit, undefined)

  const vivid = byId('vivid').snapshot
  assert.equal(vivid.actions.actionShow_Atmosphere, true)
  assert.equal(vivid.actions.actionShow_Ground, false)
  assert.equal(vivid.actions.actionShow_MistHorizon, true)
  assert.equal(vivid.actions.actionShow_Constellation_Art, true)
  assert.equal(vivid.actions.actionShow_Constellation_Lines, true)
  assert.equal(vivid.actions.actionShow_Constellation_Labels, true)
  assert.equal(vivid.vividAtmosphere, true)
  assert.equal(vivid.realisticStarVisibility, false)
  assert.equal(vivid.constellationArt3d, true)
  assert.equal(vivid.starMagLimit, undefined)
  assert.equal(vivid.milkyWayBright, 6)
})

test('manual edits keep the selected preset marked with an asterisk', () => {
  const context = fixture()
  const { store } = context
  store.applyPreset('clean')
  assert.equal(store.selectedId, 'clean')
  assert.equal(context.applied().milkyWayBright, 6)
  store.noteManualChange()
  assert.equal(store.selectedId, 'clean')
  assert.equal(store.selectedDirty, true)
  assert.match(store.labelWithMarker(store.presets[0]), /\*$/)
  assert.equal(JSON.parse(context.persisted()).selectedDirty, true)
})

test('dirty selected preset details compare the live scene with the preset snapshot', () => {
  const context = fixture()
  const { store } = context
  store.applyPreset('observe')
  assert.equal(store.selectedDirty, false)
  context.current(makeSnapshot({ nightMode: false }))
  store.noteManualChange()
  assert.equal(store.selectedDirty, true)
  store.showDetails('observe')
  assert.equal(store.detailsLoading, false)
  assert.ok(store.detailsItems.some(item =>
    (item.label.includes('夜间模式') || item.label.includes('Night mode')) &&
    item.before === '开' && item.after === '关'))
})

test('saving current settings updates a preset, details list the delta, and restore resets it', () => {
  const context = fixture()
  const { store } = context
  store.selectOnly('observe')
  context.current(makeSnapshot({ actions: { ...makeSnapshot().actions, actionShow_Ground: true, actionShow_Atmosphere: false } }))
  store.saveCurrentToSelected()
  const observe = store.presets.find(preset => preset.id === 'observe')
  assert.equal(store.isModified(observe), true)
  assert.equal(observe.snapshot.actions.actionShow_Atmosphere, false)
  store.showDetails('observe')
  assert.ok(store.detailsItems.some(item => item.label.includes('大气') || item.label.includes('Atmosphere')))
  assert.ok(store.detailsItems.some(item => item.before === '开' && item.after === '关'))
  assert.ok(store.detailsItems.some(item => item.label.includes('星等限制') || item.label.includes('magnitude')))
  assert.equal(observe.snapshot.starMagLimit, 6)

  store.restoreSelected()
  assert.equal(store.isModified(store.presets.find(preset => preset.id === 'observe')), false)
  assert.equal(context.applied().actions.actionShow_Atmosphere, true)
  assert.equal(context.applied().starMagLimit, 21)
})

test('saving a dirty built-in preset preserves the modified marker', () => {
  const context = fixture()
  const { store } = context
  store.applyPreset('observe')
  context.current(makeSnapshot({ nightMode: false }))
  store.noteManualChange()
  const before = store.presets.find(preset => preset.id === 'observe')
  assert.ok(store.isMarked(before))
  store.saveCurrentToSelected()
  const observe = store.presets.find(preset => preset.id === 'observe')
  assert.equal(store.isModified(observe), true)
  assert.ok(store.isMarked(observe))
  const persisted = JSON.parse(context.persisted())
  const savedObserve = persisted.presets.find(preset => preset.id === 'observe')
  assert.equal(savedObserve.snapshot.nightMode, false)
})

test('saving current settings to a custom preset keeps its modified marker', () => {
  const context = fixture()
  const { store } = context
  store.selectOnly('observe')
  store.saveSelectedAsCustom()
  const custom = store.presets.find(preset => preset.kind === 'custom')
  assert.ok(custom.factory !== undefined)
  assert.equal(store.isModified(custom), false)
  context.current(makeSnapshot({ nightMode: false }))
  store.saveCurrentToSelected()
  const saved = store.presets.find(preset => preset.id === custom.id)
  assert.equal(store.isModified(saved), true)
  assert.ok(store.isMarked(saved))
  const persisted = JSON.parse(context.persisted())
  const savedCustom = persisted.presets.find(preset => preset.kind === 'custom')
  assert.ok(savedCustom.factory !== undefined)
  assert.equal(savedCustom.snapshot.nightMode, false)
})

test('custom presets are capped at three and can be reordered and disabled', () => {
  const context = fixture()
  const { store } = context
  store.selectOnly('clean')
  store.saveSelectedAsCustom()
  store.saveSelectedAsCustom()
  store.saveSelectedAsCustom()
  assert.equal(store.presets.filter(preset => preset.kind === 'custom').length, 3)
  store.saveSelectedAsCustom()
  assert.ok(context.hints.includes('preset_custom_limit'))

  const before = store.presets.map(preset => preset.id)
  store.movePresetTo(0, 1)
  assert.notDeepEqual(store.presets.map(preset => preset.id), before)
  store.setEnabled('vivid', false)
  assert.equal(store.enabledPresets().some(preset => preset.id === 'vivid'), false)
  const custom = store.presets.find(preset => preset.kind === 'custom')
  store.renameCustom(custom.id, '我的星空')
  assert.equal(store.displayName(store.presets.find(preset => preset.id === custom.id)), '我的星空')
  store.renameCustom(custom.id, '   ')
  assert.equal(store.displayName(store.presets.find(preset => preset.id === custom.id)), 'preset_custom')

  const persisted = JSON.parse(context.persisted())
  assert.equal(persisted.version, 1)
  assert.equal(persisted.presets.filter(preset => preset.kind === 'custom').length, 3)
})

test('preset tab and host bridge expose the management and full-scene snapshot', () => {
  assert.match(layerController, /label: I18n\.t\('layer_presets_tab'\), id: 7/)
  assert.match(layerController, /applyStarMagLimit[\s\S]{0,200}noteLayerPresetManualChange/)
  assert.match(layersPanel, /LayerPresetBar\(\{ presetStore: this\.presetStore \}\)/)
  assert.match(layersPanel, /viewTab === 7[\s\S]{0,120}LayerPresetTab/)
  assert.match(bar, /labelWithMarker/)
  assert.match(bar, /I18n\.t\('layer_presets_tab'\)/)
  assert.match(bar, /preset\.customName/)
  assert.match(bar, /new Scroller\(\)/)
  assert.match(bar, /scrollTo\(/)
  assert.match(bar, /initialRevealPending/)
  assert.match(bar, /selectedId === preset\.id \? this\.c\.accent/)
  assert.doesNotMatch(bar, /preset_keep/)
  assert.match(tab, /preset_save_current/)
  assert.match(tab, /preset_save_custom/)
  assert.doesNotMatch(tab, /preset_apply/)
  assert.match(tab, /onClick\(\(\) => \{ this\.presetStore\.applyPreset\(preset\.id\) \}\)/)
  assert.match(tab, /preset_restore/)
  assert.match(tab, /preset_rename/)
  assert.match(tab, /bindContentCover/)
  assert.match(tab, /preset_details/)
  assert.match(tab, /GestureGroup\(GestureMode\.Sequence/)
  assert.match(tab, /movePresetTo/)
  assert.match(tab, /restorePreset/)
  assert.match(tab, /setEnabled/)
  assert.match(host, /captureLayerPresetSnapshot/)
  assert.match(host, /applyLayerPresetSnapshot/)
  assert.match(host, /setActionStates/)
  assert.match(host, /snapshot\.starMagLimit/)
  assert.match(host, /presetCaptureSerial/)
  assert.match(host, /requestInteractive\('getState', captureSerial/)
  assert.match(host, /applyNightMode\(snapshot\.nightMode, true\)/)
  assert.doesNotMatch(host, /setDetailDisplayMode\(snapshot\.observeMode/)
  assert.match(host, /actionSwitch_Equatorial_Mount/)
  assert.match(host, /ensurePluginLoaded\('Oculars'/)
  assert.match(host, /LAYER_PRESET_STORE/)
  for (const key of ['layer_presets_tab', 'preset_clean', 'preset_observe', 'preset_photo', 'preset_study', 'preset_vivid',
    'preset_save_current', 'preset_save_custom', 'preset_restore', 'preset_details', 'preset_rename', 'preset_custom_limit']) {
    assert.match(i18n, new RegExp(`'${key}'\\s*:\\s*\\{`))
  }
})
