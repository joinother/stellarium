import { readFile } from 'node:fs/promises'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { atomicWrite } from './fetch-mirror.mjs'

export function summarizeMirror(manifest, now = Date.now()) {
  const generated = Date.parse(manifest?.generatedAt)
  const age = Number.isFinite(generated) ? now - generated : Infinity
  const expired = age < -300000 || age > 12 * 3600000
  const sources = Array.isArray(manifest?.sources) ? manifest.sources : []
  const counts = { fresh: 0, stale: 0, unavailable: 0 }
  for (const source of sources) {
    const status = source?.available === true && ['fresh', 'stale'].includes(source.status) ?
      (expired ? 'stale' : source.status) : 'unavailable'
    counts[status]++
  }
  return {
    schemaVersion: 1,
    checkedAt: new Date(now).toISOString(),
    manifestGeneratedAt: Number.isFinite(generated) ? new Date(generated).toISOString() : null,
    manifestAgeSeconds: Number.isFinite(age) ? Math.max(0, Math.floor(age / 1000)) : null,
    manifestExpired: expired,
    status: sources.length === 0 || counts.unavailable === sources.length ? 'unavailable' :
      counts.stale + counts.unavailable > 0 ? 'degraded' : 'fresh',
    sourceCount: sources.length,
    sources: counts
  }
}

async function main() {
  const root = process.argv[2] || '/srv/tle-mirror'
  let manifest = null
  try { manifest = JSON.parse(await readFile(join(root, 'v1/manifest.json'), 'utf8')) } catch {}
  const status = summarizeMirror(manifest)
  await atomicWrite(join(root, 'v1/status.json'), JSON.stringify(status) + '\n', { stagingDirectory: root })
  console.log(JSON.stringify(status))
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(() => { console.error('mirror_status_publish_failed'); process.exitCode = 1 })
}
