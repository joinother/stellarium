// 目镜插件「器材配置」的纯表单草稿与校验。
//
// 面板只持有字符串草稿（便于 TextInput 编辑），本模块负责：
// - 从现有器材条目回填草稿；
// - 校验并生成 add/update 命令的 JSON payload。
// 不 import UI / NAPI / I18n：错误以稳定代码返回，由面板映射文案。
import { OcularInstrumentItem } from '../types/MainWindowModels'

export const OCULAR_KIND_OCULAR: string = 'ocular'
export const OCULAR_KIND_TELESCOPE: string = 'telescope'
export const OCULAR_KIND_LENS: string = 'lens'
export const OCULAR_KIND_CCD: string = 'ccd'

export const OCULAR_EQUIPMENT_ERROR_NAME: string = 'name_empty'
export const OCULAR_EQUIPMENT_ERROR_VALUE: string = 'value_invalid'

export interface OcularEquipmentItemPayload {
  name: string
  apparentFov?: number
  focalLength?: number
  fieldStop?: number
  binocular?: boolean
  permanentCrosshair?: boolean
  multiplier?: number
  diameter?: number
  horizontalFlipped?: boolean
  verticalFlipped?: boolean
  equatorial?: boolean
  resolutionX?: number
  resolutionY?: number
  chipWidth?: number
  chipHeight?: number
  binningX?: number
  binningY?: number
  rotation?: number
  hasOAG?: boolean
  prismHeight?: number
  prismWidth?: number
  prismDistance?: number
  prismPosAngle?: number
}

export interface OcularEquipmentMutationPayload {
  kind: string
  index: number
  item?: OcularEquipmentItemPayload
  delta?: number
}

// UI 侧沿用 Ocular/Telescope/Lens/CCD 的器材类别名；桥 payload 使用小写代码。
export function equipmentKindCode(kind: string): string {
  if (kind === 'Telescope') return OCULAR_KIND_TELESCOPE
  if (kind === 'Lens') return OCULAR_KIND_LENS
  if (kind === 'CCD') return OCULAR_KIND_CCD
  return OCULAR_KIND_OCULAR
}

@Observed
export class OcularEquipmentDraft {
  name: string = ''
  apparentFov: string = '50'
  focalLength: string = '25'
  fieldStop: string = '0'
  binocular: boolean = false
  permanentCrosshair: boolean = false
  multiplier: string = '2'
  diameter: string = '80'
  horizontalFlipped: boolean = true
  verticalFlipped: boolean = true
  equatorial: boolean = true
  resolutionX: string = '4096'
  resolutionY: string = '4096'
  chipWidth: string = '36.8'
  chipHeight: string = '36.8'
  binningX: string = '1'
  binningY: string = '1'
  rotation: string = '0'
  hasOAG: boolean = false
  prismHeight: string = '0'
  prismWidth: string = '0'
  prismDistance: string = '0'
  prismPosAngle: string = '0'
}

export function emptyEquipmentDraft(): OcularEquipmentDraft {
  return new OcularEquipmentDraft()
}

function numberText(value: number | undefined, fallback: number): string {
  const resolved = typeof value === 'number' && Number.isFinite(value) ? value : fallback
  return resolved.toString()
}

export function equipmentDraftFromItem(kind: string, item: OcularInstrumentItem): OcularEquipmentDraft {
  const draft = new OcularEquipmentDraft()
  draft.name = item.name
  if (kind === OCULAR_KIND_OCULAR) {
    draft.apparentFov = numberText(item.apparentFov, 50)
    draft.focalLength = numberText(item.focalLength, 25)
    draft.fieldStop = numberText(item.fieldStop, 0)
    draft.binocular = item.binocular === true
    draft.permanentCrosshair = item.permanentCrosshair === true
  } else if (kind === OCULAR_KIND_LENS) {
    draft.multiplier = numberText(item.multiplier, 2)
  } else if (kind === OCULAR_KIND_TELESCOPE) {
    draft.diameter = numberText(item.diameter, 80)
    draft.focalLength = numberText(item.focalLength, 500)
    draft.horizontalFlipped = item.horizontalFlipped !== false
    draft.verticalFlipped = item.verticalFlipped !== false
    draft.equatorial = item.equatorial !== false
  } else {
    draft.resolutionX = numberText(item.resolutionX, 4096)
    draft.resolutionY = numberText(item.resolutionY, 4096)
    draft.chipWidth = numberText(item.chipWidth, 36.8)
    draft.chipHeight = numberText(item.chipHeight, 36.8)
    draft.binningX = numberText(item.binningX, 1)
    draft.binningY = numberText(item.binningY, 1)
    draft.rotation = numberText(item.rotation, 0)
    draft.hasOAG = item.hasOAG === true
    draft.prismHeight = numberText(item.prismHeight, 0)
    draft.prismWidth = numberText(item.prismWidth, 0)
    draft.prismDistance = numberText(item.prismDistance, 0)
    draft.prismPosAngle = numberText(item.prismPosAngle, 0)
  }
  return draft
}

function readNumber(value: string): number {
  const text = value.trim()
  if (text.length === 0) {
    return Number.NaN
  }
  return Number(text)
}

function inRange(value: number, minimum: number, maximum: number): boolean {
  return Number.isFinite(value) && value >= minimum && value <= maximum
}

function readInteger(value: string): number {
  const parsed = readNumber(value)
  if (!Number.isFinite(parsed) || Math.abs(parsed - Math.round(parsed)) > 0.0001) {
    return Number.NaN
  }
  return Math.round(parsed)
}

export function validateEquipmentDraft(kind: string, draft: OcularEquipmentDraft): string {
  if (draft.name.trim().length === 0) {
    return OCULAR_EQUIPMENT_ERROR_NAME
  }
  if (kind === OCULAR_KIND_OCULAR) {
    if (!inRange(readNumber(draft.apparentFov), 1, 120) ||
      !inRange(readNumber(draft.focalLength), 1, 500) ||
      !inRange(readNumber(draft.fieldStop), 0, 200)) {
      return OCULAR_EQUIPMENT_ERROR_VALUE
    }
    return ''
  }
  if (kind === OCULAR_KIND_LENS) {
    return inRange(readNumber(draft.multiplier), 0.01, 9) ? '' : OCULAR_EQUIPMENT_ERROR_VALUE
  }
  if (kind === OCULAR_KIND_TELESCOPE) {
    if (!inRange(readNumber(draft.diameter), 1, 999999) ||
      !inRange(readNumber(draft.focalLength), 1, 9999999)) {
      return OCULAR_EQUIPMENT_ERROR_VALUE
    }
    return ''
  }
  const resolutionX = readInteger(draft.resolutionX)
  const resolutionY = readInteger(draft.resolutionY)
  const binningX = readInteger(draft.binningX)
  const binningY = readInteger(draft.binningY)
  if (!inRange(resolutionX, 1, 100000) || !inRange(resolutionY, 1, 100000) ||
    !inRange(binningX, 1, 4) || !inRange(binningY, 1, 4) ||
    !inRange(readNumber(draft.chipWidth), 0.1, 9999) ||
    !inRange(readNumber(draft.chipHeight), 0.1, 9999) ||
    !inRange(readNumber(draft.rotation), -360, 360) ||
    !inRange(readNumber(draft.prismHeight), 0, 9999) ||
    !inRange(readNumber(draft.prismWidth), 0, 9999) ||
    !inRange(readNumber(draft.prismDistance), 0, 100000) ||
    !inRange(readNumber(draft.prismPosAngle), 0, 360)) {
    return OCULAR_EQUIPMENT_ERROR_VALUE
  }
  if (draft.hasOAG && (readNumber(draft.prismHeight) < 0.1 ||
    readNumber(draft.prismWidth) < 0.1 || readNumber(draft.prismDistance) < 0.1)) {
    return OCULAR_EQUIPMENT_ERROR_VALUE
  }
  return ''
}

export function equipmentItemPayload(kind: string, draft: OcularEquipmentDraft): OcularEquipmentItemPayload {
  const item: OcularEquipmentItemPayload = { name: draft.name.trim() }
  if (kind === OCULAR_KIND_OCULAR) {
    item.apparentFov = readNumber(draft.apparentFov)
    item.focalLength = readNumber(draft.focalLength)
    item.fieldStop = readNumber(draft.fieldStop)
    item.binocular = draft.binocular
    item.permanentCrosshair = draft.permanentCrosshair
  } else if (kind === OCULAR_KIND_LENS) {
    item.multiplier = readNumber(draft.multiplier)
  } else if (kind === OCULAR_KIND_TELESCOPE) {
    item.diameter = readNumber(draft.diameter)
    item.focalLength = readNumber(draft.focalLength)
    item.horizontalFlipped = draft.horizontalFlipped
    item.verticalFlipped = draft.verticalFlipped
    item.equatorial = draft.equatorial
  } else {
    item.resolutionX = readInteger(draft.resolutionX)
    item.resolutionY = readInteger(draft.resolutionY)
    item.chipWidth = readNumber(draft.chipWidth)
    item.chipHeight = readNumber(draft.chipHeight)
    item.binningX = readInteger(draft.binningX)
    item.binningY = readInteger(draft.binningY)
    item.rotation = readNumber(draft.rotation)
    item.hasOAG = draft.hasOAG
    item.prismHeight = readNumber(draft.prismHeight)
    item.prismWidth = readNumber(draft.prismWidth)
    item.prismDistance = readNumber(draft.prismDistance)
    item.prismPosAngle = readNumber(draft.prismPosAngle)
  }
  return item
}

export function equipmentMutationPayload(action: string, kind: string, index: number,
  draft: OcularEquipmentDraft): string {
  const payload: OcularEquipmentMutationPayload = { kind: kind, index: index }
  if (action === 'add' || action === 'update') {
    payload.item = equipmentItemPayload(kind, draft)
  }
  return JSON.stringify(payload)
}

export function equipmentMovePayload(kind: string, index: number, delta: number): string {
  const payload: OcularEquipmentMutationPayload = { kind: kind, index: index, delta: delta }
  return JSON.stringify(payload)
}

export function equipmentIndexPayload(kind: string, index: number): string {
  const payload: OcularEquipmentMutationPayload = { kind: kind, index: index }
  return JSON.stringify(payload)
}
