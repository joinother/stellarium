import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import test from 'node:test'

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8')
const plain = source => stripTypeScriptTypes(source
  .replace(/^import[\s\S]*?from\s+'[^']+'\r?\n/gm, '')
  .replace(/^@Observed\r?\n/gm, '')
  .replaceAll('export ', ''))

const deriveSource = read('harmonyos/ets-source/common/derive/ocularEquipment.ets')
const api = new Function(`${plain(deriveSource)}
  return {
    emptyEquipmentDraft, equipmentDraftFromItem, validateEquipmentDraft, equipmentItemPayload,
    equipmentMutationPayload, equipmentMovePayload, equipmentIndexPayload, equipmentKindCode,
    OCULAR_EQUIPMENT_ERROR_NAME, OCULAR_EQUIPMENT_ERROR_VALUE
  }`)()

const panel = read('harmonyos/ets-source/panels/panels/OcularsPanel.ets')
const general = read('harmonyos/ets-source/panels/telescope/OcularGeneralTab.ets')
const equipment = read('harmonyos/ets-source/panels/telescope/OcularEquipmentTab.ets')
const form = read('harmonyos/ets-source/panels/telescope/OcularEquipmentForm.ets')
const tabs = read('harmonyos/ets-source/panels/telescope/OcularsTabs.ets')
const summary = read('harmonyos/ets-source/panels/telescope/OcularSummaryCard.ets')
const controller = read('harmonyos/ets-source/capability/OcularController.ets')
const host = read('harmonyos/ets-source/pages/MainWindowNativeNode.ets')
const qability = read('harmonyos/ets-source/qability/QAbility.ets')
const native = read('src/StelMainView.cpp')
const plugin = read('plugins/Oculars/src/Oculars.cpp')
const catalog = read('src/StelOhosCommandCatalog.hpp')

function draftWithName(kind) {
  const draft = api.emptyEquipmentDraft()
  draft.name = 'Test ' + kind
  return draft
}

test('UI kinds map to the lower-case bridge kinds', () => {
  assert.equal(api.equipmentKindCode('Ocular'), 'ocular')
  assert.equal(api.equipmentKindCode('Telescope'), 'telescope')
  assert.equal(api.equipmentKindCode('Lens'), 'lens')
  assert.equal(api.equipmentKindCode('CCD'), 'ccd')
})

test('ocular drafts validate name, field ranges and payload shape', () => {
  const draft = api.emptyEquipmentDraft()
  assert.equal(api.validateEquipmentDraft('ocular', draft), api.OCULAR_EQUIPMENT_ERROR_NAME)
  draft.name = ' 25 mm Plössl '
  assert.equal(api.validateEquipmentDraft('ocular', draft), '')
  draft.apparentFov = '0'
  assert.equal(api.validateEquipmentDraft('ocular', draft), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  draft.apparentFov = '50'
  draft.fieldStop = '201'
  assert.equal(api.validateEquipmentDraft('ocular', draft), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  draft.fieldStop = '27'
  const payload = api.equipmentItemPayload('ocular', draft)
  assert.equal(payload.name, '25 mm Plössl')
  assert.equal(payload.apparentFov, 50)
  assert.equal(payload.focalLength, 25)
  assert.equal(payload.fieldStop, 27)
  assert.equal(payload.binocular, false)
})

test('lens and telescope drafts reject out-of-range values', () => {
  const lens = draftWithName('lens')
  lens.multiplier = '0.009'
  assert.equal(api.validateEquipmentDraft('lens', lens), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  lens.multiplier = '0.8'
  assert.equal(api.validateEquipmentDraft('lens', lens), '')
  assert.equal(api.equipmentItemPayload('lens', lens).multiplier, 0.8)

  const telescope = draftWithName('telescope')
  telescope.diameter = '0'
  assert.equal(api.validateEquipmentDraft('telescope', telescope), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  telescope.diameter = '200'
  telescope.focalLength = '1200'
  assert.equal(api.validateEquipmentDraft('telescope', telescope), '')
  assert.equal(api.equipmentItemPayload('telescope', telescope).focalLength, 1200)
})

test('sensor drafts enforce integer binning and OAG prism dimensions', () => {
  const ccd = draftWithName('ccd')
  assert.equal(api.validateEquipmentDraft('ccd', ccd), '')
  ccd.resolutionX = '100001'
  assert.equal(api.validateEquipmentDraft('ccd', ccd), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  ccd.resolutionX = '4096'
  ccd.binningX = '5'
  assert.equal(api.validateEquipmentDraft('ccd', ccd), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  ccd.binningX = '1'
  ccd.hasOAG = true
  assert.equal(api.validateEquipmentDraft('ccd', ccd), api.OCULAR_EQUIPMENT_ERROR_VALUE)
  ccd.prismHeight = '12'
  ccd.prismWidth = '12'
  ccd.prismDistance = '30'
  assert.equal(api.validateEquipmentDraft('ccd', ccd), '')
  const payload = api.equipmentItemPayload('ccd', ccd)
  assert.equal(payload.hasOAG, true)
  assert.equal(payload.prismDistance, 30)
})

test('mutation payloads keep the bridge contract', () => {
  const draft = draftWithName('ocular')
  const add = JSON.parse(api.equipmentMutationPayload('add', 'ocular', -1, draft))
  assert.deepEqual({ kind: add.kind, index: add.index }, { kind: 'ocular', index: -1 })
  assert.equal(add.item.name, 'Test ocular')
  const update = JSON.parse(api.equipmentMutationPayload('update', 'lens', 3, draft))
  assert.equal(update.index, 3)
  assert.equal(update.item.name, 'Test ocular')
  const move = JSON.parse(api.equipmentMovePayload('telescope', 2, -1))
  assert.deepEqual(move, { kind: 'telescope', index: 2, delta: -1 })
  const remove = JSON.parse(api.equipmentIndexPayload('ccd', 1))
  assert.deepEqual(remove, { kind: 'ccd', index: 1 })
})

test('panel hosts summary, six tabs, equipment pages and modal CRUD', () => {
  for (const anchor of ['.id(\'oculars-summary\')', '.id(\'oculars-tab-\'', '.id(\'ocular-equipment-add\')',
    '.id(\'ocular-equipment-form\')', '.id(\'ocular-equipment-import-append\')', '.id(\'ocular-equipment-export\')',
    '.bindContentCover(']) {
    assert.ok(panel.includes(anchor) || general.includes(anchor) || equipment.includes(anchor) ||
      form.includes(anchor) || tabs.includes(anchor) || summary.includes(anchor), `missing UI anchor ${anchor}`)
  }
  assert.ok(panel.includes('OcularSummaryCard'))
  assert.ok(panel.includes('OcularsTabs'))
  assert.ok(panel.includes('OcularGeneralTab'))
  assert.ok(panel.includes('OcularEquipmentTab'))
  assert.ok(panel.includes('OcularEquipmentForm'))
  for (const label of ['ocular_tab_general', 'ocular_tab_oculars', 'ocular_tab_lenses', 'ocular_tab_sensors',
    'ocular_tab_telescopes', 'ocular_tab_about']) {
    assert.ok(panel.includes(`I18n.t('${label}')`), `missing tab ${label}`)
  }
  assert.ok(panel.includes('equipmentIndexPayload') && panel.includes('equipmentMovePayload'))
  assert.ok(panel.includes('MediaSaveResult'))
  assert.ok(panel.includes("@Prop @Watch('onEditorRequestChanged') editorRequest"))
  assert.ok(panel.includes('onEditorRequestChanged()'))
  assert.ok(panel.includes('this.store.ocularPanelTab'))
  assert.ok(panel.includes("@Prop @Watch('onScrollRequestChanged') scrollRequest"))
  const store = read('harmonyos/ets-source/state/TelescopeStore.ets')
  assert.ok(store.includes('ocularPanelTab: number = 0'))
})

test('semantic CLI can switch oculars tabs and open the equipment editor', () => {
  for (const command of ['setOcularsTab', 'setOcularsScroll', 'openOcularEquipmentEditor', 'closeOcularEquipmentEditor']) {
    assert.ok(qability.includes(`'${command}'`), `QAbility missing ${command}`)
    assert.ok(host.includes(`'${command}'`), `host missing ${command}`)
  }
  assert.ok(host.includes('ocularEditorRequest = kind'))
  assert.ok(host.includes("ocularEditorRequest = 'close|0|'"))
  assert.ok(qability.includes('expected oculars tab 0..5'))
  assert.ok(qability.includes('expected kind or kind|index'))
})

test('general tab exposes Telrad FOV and CCD centre controls', () => {
  assert.ok(general.includes("onSetOcularSetting('ccdCenter'"))
  assert.ok(general.includes("'ocular-telrad-fov-'"))
  assert.ok(general.includes('onSetTelradFov(values)'))
  assert.ok(general.includes("I18n.t('ocular_equipment_export')"))
  assert.ok(general.includes("I18n.t('ocular_equipment_import')"))
  assert.ok(general.includes('this.telradDraft[index] = value'))
})

test('controller, host and UI-event bridge cover equipment mutations', () => {
  for (const method of ['addOcularEquipment', 'updateOcularEquipment', 'deleteOcularEquipment',
    'moveOcularEquipment', 'setTelradFov', 'exportEquipment', 'importEquipment']) {
    assert.ok(controller.includes(method), `controller missing ${method}`)
  }
  assert.ok(host.includes('onAddEquipment:') && host.includes('onSaveEquipmentFile:') &&
    host.includes('onPickEquipmentFile:') && host.includes('readTextFile(result.path, 524288'))
  for (const command of ['addOcularEquipment', 'updateOcularEquipment', 'deleteOcularEquipment',
    'moveOcularEquipment', 'importOcularEquipment', 'setTelradFov']) {
    assert.ok(qability.includes(`'${command}'`), `QAbility missing ${command}`)
    assert.ok(native.includes(command), `native bridge missing ${command}`)
    assert.ok(catalog.includes(command), `command catalog missing ${command}`)
  }
})

test('native equipment backend validates atomically and persists to ocular.ini', () => {
  assert.ok(native.includes('applyOhosEquipmentAction') && native.includes('exportOhosEquipmentJson') &&
    native.includes('importOhosEquipmentJson'))
  assert.ok(native.includes('setFlagShowCCDCenter(enabled)'))
  assert.ok(plugin.includes('fillOcular') && plugin.includes('fillLens') &&
    plugin.includes('fillTelescope') && plugin.includes('fillCcd'))
  assert.ok(plugin.includes('persistEquipmentSettings()'))
  assert.ok(plugin.includes('settings->sync()'))
  assert.ok(plugin.includes('stellarium-ohos-oculars-equipment'))
  assert.ok(plugin.includes('512 * 1024'))
  assert.ok(plugin.includes('Cannot delete the last') === false)
  assert.ok(plugin.includes('last_item'))
  assert.ok(plugin.includes('selectedLensIndex >= 0'))
})

test('CCD close is idempotent and never crops the FOV to zero', () => {
  assert.ok(plugin.includes('const bool wasShowing = flagShowCCD;'))
  assert.ok(plugin.includes('if (show == wasShowing)'))
  assert.ok(plugin.includes('initialFOV > 0.'))
  assert.ok(plugin.includes('movementManager->getInitFov() > 0.'))
})
