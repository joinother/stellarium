#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import process from 'node:process'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const cppPath = path.join(root, 'src/StelMainView.cpp')
const etsPath = path.join(root, 'harmonyos/ets-source/pages/MainWindowNativeNode.ets')
const mirrorPath = path.join(root, 'build/libstellarium-harmonyos/entry/src/main/ets/pages/MainWindowNativeNode.ets')
const typesPath = path.join(root, 'harmonyos/ets-source/pages/StellariumTypes.ets')

const cpp = fs.readFileSync(cppPath, 'utf8')
const ets = fs.readFileSync(etsPath, 'utf8')
const types = fs.readFileSync(typesPath, 'utf8')
const failures = []

const fieldPattern = /append(?:LocalizedText|ScaledPositiveNumber|NonZeroNumber|PositiveNumber|Number|DegreePair|Text|Field)\(QStringLiteral\("([^"]+)"\),\s*QStringLiteral\("([^"]+)"\)/g
const emitted = [...cpp.matchAll(fieldPattern)].map(match => ({ key: match[1], section: match[2] }))
const uniqueKeys = new Set(emitted.map(field => field.key))

const labelsStart = ets.indexOf('private detailFieldLabel')
const labelsEnd = ets.indexOf('private detailFieldValue')
const labelsBlock = ets.slice(labelsStart, labelsEnd)
const labels = new Set([...labelsBlock.matchAll(/case '([^']+)'/g)].map(match => match[1]))

const sectionsStart = ets.indexOf('private detailSectionIds')
const sectionsEnd = ets.indexOf('private detailFieldLabel')
const sectionsBlock = ets.slice(sectionsStart, sectionsEnd)
const sectionIdsBlock = sectionsBlock.slice(0, sectionsBlock.indexOf('private detailSectionTitle'))
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
if ((ets.match(/this\.structuredObjectDetails\(/g) ?? []).length < 3) failures.push('not all object detail surfaces use the shared builder')

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
