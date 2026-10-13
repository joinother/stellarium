#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const cppPath = path.join(root, 'src/StelMainView.cpp')
const etsPath = path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets')
const mirrorPath = path.join(root, 'build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets')
const typesPath = path.join(root, 'harmonyos/ets-source/common/types/StellariumTypes.ets')
// 段落助手已随界面搬进 StructuredDetailRows.ets（改为文件作用域函数）。
const detailPath = path.join(root, 'harmonyos/ets-source/panels/object/StructuredDetailRows.ets')

const cpp = fs.readFileSync(cppPath, 'utf8')
const ets = fs.readFileSync(etsPath, 'utf8')
const types = fs.readFileSync(typesPath, 'utf8')
const failures = []

const fieldPattern = /append(?:LocalizedText|ScaledPositiveNumber|NonZeroNumber|PositiveNumber|Number|DegreePair|Text|Field)\(QStringLiteral\("([^"]+)"\),\s*QStringLiteral\("([^"]+)"\)/g
const emitted = [...cpp.matchAll(fieldPattern)].map(match => ({ key: match[1], section: match[2] }))
const uniqueKeys = new Set(emitted.map(field => field.key))

const detail = fs.readFileSync(detailPath, 'utf8')
const labelsStart = detail.indexOf('function detailFieldLabel')
const labelsEnd = detail.indexOf('function detailFieldValue')
const labelsBlock = detail.slice(labelsStart, labelsEnd)
const labels = new Set([...labelsBlock.matchAll(/case '([^']+)'/g)].map(match => match[1]))

const sectionsStart = detail.indexOf('function detailSectionIds')
const sectionsEnd = detail.indexOf('function detailFieldLabel')
const sectionsBlock = detail.slice(sectionsStart, sectionsEnd)
const sectionIdsBlock = sectionsBlock.slice(0, sectionsBlock.indexOf('function detailSectionTitle'))
const sectionIds = new Set([...sectionIdsBlock.matchAll(/'([^']+)'/g)].map(match => match[1]))
const sectionTitles = new Set([...sectionsBlock.matchAll(/case '([^']+)'/g)].map(match => match[1]))

const missingLabels = [...uniqueKeys].filter(key => !labels.has(key))
const missingSections = [...new Set(emitted.map(field => field.section))].filter(section => !sectionIds.has(section) || !sectionTitles.has(section))

if (emitted.length < 100) failures.push(`structured field coverage unexpectedly fell to ${emitted.length}`)
if (uniqueKeys.size !== emitted.length) failures.push('duplicate public detail field keys detected')
if (missingLabels.length > 0) failures.push(`missing labels: ${missingLabels.join(', ')}`)
if (missingSections.length > 0) failures.push(`missing sections: ${missingSections.join(', ')}`)
if (!types.includes('detailFields?: Array<ObjectDetailField>')) failures.push('detailFields bridge contract is missing')
if (!ets.includes('LoadingProgress()')) failures.push('native detail loading indicator is missing')
// 共享 builder 需覆盖现存的全部详情面板（死代码清理后剩两处调用：卡片"资料"页与平板检查器，
// 前者已随三页搬进 ObjectDetailTabs），且它必须委托给共享的行组件。
const tabsPath = path.join(root, 'harmonyos/ets-source/panels/object/ObjectDetailTabs.ets')
const tabsSource = fs.existsSync(tabsPath) ? fs.readFileSync(tabsPath, 'utf8') : ''
// 手机端天体详情分支已下沉为 ObjectPanel 组件（Phase 4e），其资料页仍委托共享行组件。
const objectPanelPath = path.join(root, 'harmonyos/ets-source/panels/panels/ObjectPanel.ets')
const objectPanelSource = fs.existsSync(objectPanelPath) ? fs.readFileSync(objectPanelPath, 'utf8') : ''
if (((ets + tabsSource + objectPanelSource).match(/StructuredDetailRows\(\{ store: this\.(objectDetailStore|store)/g) ?? []).length < 2) failures.push('not all object detail surfaces use the shared builder')
if (!detail.includes('StructuredDetailRow({ label: detailFieldLabel(field.key)')
  || !detail.includes('DetailSectionTitle({ title: detailSectionTitle(section)')) {
  failures.push('the shared detail builder no longer delegates to the shared row components')
}

for (const forbidden of ['selectedFullInfo', 'selectedRich', 'fullInfo?: string']) {
  if (ets.includes(forbidden) || types.includes(forbidden)) failures.push(`raw detail path remains: ${forbidden}`)
}
if (cpp.includes('result["fullInfo"]')) failures.push('native bridge still exports raw fullInfo')
if (fs.existsSync(mirrorPath) && fs.readFileSync(mirrorPath, 'utf8') !== ets) failures.push('generated ArkTS mirror is stale')

if (failures.length > 0) {
  console.error('HarmonyOS object detail verification failed:')
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

console.log(`HarmonyOS object detail verification passed: ${uniqueKeys.size} labeled fields across ${sectionIds.size} sections.`)
