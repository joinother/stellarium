#!/usr/bin/env node
// Rewrites the compile-time feature flags in the generated hvigor project.
//
// The tracked ArkTS source keeps the release default. A packaging run that
// wants a build without the metered Map Kit server APIs or without the
// development panel flips the constants in the build tree only, so the working
// tree stays clean and the next sync restores the default automatically.
//
// Usage:
//   node scripts/apply-ohos-feature-flags.mjs --ets-root <generated ets root> \
//     [--metered-map-apis=0|1] [--dev-tools=0|1]
//
// Exit codes:
//   0  flags applied (or already at the requested values)
//   1  bad arguments, missing flag file, or a declaration marker moved
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { join, resolve } from 'node:path'

const FLAG_FILE = 'common/config/OhosFeatureFlags.ets'
const FLAGS = [
  { name: 'METERED_MAP_APIS_ENABLED', arg: 'metered-map-apis', label: 'metered Map Kit APIs' },
  { name: 'DEV_TOOLS_ENABLED', arg: 'dev-tools', label: 'development panel' }
]

function fail(message) {
  console.error(`[feature-flags] ERROR: ${message}`)
  process.exit(1)
}

function parseArgs(argv) {
  let etsRoot = ''
  const values = {}
  for (const flag of FLAGS) values[flag.arg] = '1'
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--ets-root') {
      etsRoot = argv[++i] ?? ''
      continue
    }
    if (arg.startsWith('--ets-root=')) {
      etsRoot = arg.slice('--ets-root='.length)
      continue
    }
    const flag = FLAGS.find(candidate => arg === `--${candidate.arg}` || arg.startsWith(`--${candidate.arg}=`))
    if (flag === undefined) fail(`unknown argument: ${arg}`)
    const value = arg === `--${flag.arg}` ? (argv[++i] ?? '') : arg.slice(`--${flag.arg}=`.length)
    if (value !== '0' && value !== '1') fail(`--${flag.arg} must be 0 or 1`)
    values[flag.arg] = value
  }
  if (etsRoot.length === 0) fail('missing --ets-root')
  return { etsRoot: resolve(etsRoot), values }
}

const { etsRoot, values } = parseArgs(process.argv.slice(2))
const file = join(etsRoot, FLAG_FILE)
if (!existsSync(file)) fail(`missing generated flag file: ${file}`)

let source = readFileSync(file, 'utf8')
for (const flag of FLAGS) {
  const declaration = new RegExp(`export const ${flag.name}: boolean = (true|false)`, 'g')
  const matches = [...source.matchAll(declaration)]
  if (matches.length !== 1) {
    fail(`expected exactly one ${flag.name} declaration in ${file}, found ${matches.length}`)
  }
  const desired = values[flag.arg] === '1' ? 'true' : 'false'
  declaration.lastIndex = 0
  source = source.replace(declaration, `export const ${flag.name}: boolean = ${desired}`)
  console.log(`[feature-flags] ${flag.label} ${desired === 'true' ? 'enabled' : 'disabled'} (${file})`)
}
writeFileSync(file, source)
