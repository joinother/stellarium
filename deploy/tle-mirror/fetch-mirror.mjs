#!/usr/bin/env node
// 星象仪在线数据镜像：把 sources.json 里登记的国外上游拉到本地目录，供 App 走 mirror 模式读取。
//
// 用法：node fetch-mirror.mjs --root /srv/tle-mirror [--only satellites] [--dry-run]
//
// 设计要点
// - 原子落盘：先写 .tmp，校验非空且看起来像目标格式，再 rename，失败保留上一版。
// - 单个源失败不影响其它源；结束时写 manifest.json（每个源的 sha256/字节/来源时间）。
// - 不依赖 npm 包，只用 Node 18+ 内置 fetch；服务器上装个 node 就能跑。

import { createHash } from 'node:crypto'
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'

const args = process.argv.slice(2)
function flag(name) {
  const i = args.indexOf(name)
  return i >= 0
}
function option(name, fallback = '') {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback
}

const root = option('--root', '/srv/tle-mirror')
const only = option('--only', '')
const dryRun = flag('--dry-run')
const registryPath = option('--sources', new URL('./sources.json', import.meta.url).pathname)

const registry = JSON.parse(await readFile(registryPath, 'utf8'))
const selected = registry.sources.filter((s) => !only || s.id.startsWith(only))

// 只镜像静态目录/查询接口清单；带实时参数的查询（simbad、wikipedia 等）留空，由将来代理层处理。
const SKIP_PREFIX = ['query.', 'survey.', 'core.', 'realtime.']
const mirrors = selected.filter((s) => !SKIP_PREFIX.some((p) => s.id.startsWith(p)))

function looksValid(body, format) {
  if (!body || body.length < 16) return false
  const head = body.slice(0, 2000)
  if (head.includes('<html') || head.includes('<!DOCTYPE html')) return false
  if (format === 'tle-3le') return /^\d [A-Z0-9 ]/m.test(head) || /^[^\n]+\n1 /m.test(head)
  if (format === 'json') {
    try {
      JSON.parse(body)
      return true
    } catch {
      return false
    }
  }
  return true
}

async function fetchOne(source) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), 60000)
  try {
    const response = await fetch(source.upstreamUrl, {
      signal: controller.signal,
      headers: { 'user-agent': 'SkyInstrumentMirror/1.0 (+https://skyinstrument.app)' },
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    const body = await response.text()
    if (!looksValid(body, source.format)) throw new Error('payload rejected (not the expected format)')
    return body
  } finally {
    clearTimeout(timer)
  }
}

const manifest = { generatedAt: new Date().toISOString(), root, sources: [] }
for (const source of mirrors) {
  const destination = join(root, source.mirrorPath.replace(/^\//, ''))
  try {
    const body = await fetchOne(source)
    const sha256 = createHash('sha256').update(body).digest('hex')
    if (!dryRun) {
      await mkdir(dirname(destination), { recursive: true })
      const tmp = `${destination}.tmp`
      await writeFile(tmp, body)
      await rename(tmp, destination)
    }
    manifest.sources.push({ id: source.id, path: source.mirrorPath, bytes: Buffer.byteLength(body), sha256, ok: true })
    console.log(`ok   ${source.id} -> ${source.mirrorPath} (${Buffer.byteLength(body)} B)`)
  } catch (error) {
    manifest.sources.push({ id: source.id, path: source.mirrorPath, error: String(error.message || error), ok: false })
    console.error(`FAIL ${source.id}: ${error.message || error}`)
  }
}

if (!dryRun) {
  await writeFile(join(root, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
}
const failed = manifest.sources.filter((s) => !s.ok).length
console.log(`\n${manifest.sources.length - failed}/${manifest.sources.length} 个源已刷新，失败 ${failed} 个`)
process.exit(failed === manifest.sources.length ? 1 : 0)
