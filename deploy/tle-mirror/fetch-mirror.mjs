#!/usr/bin/env node

import { createHash, randomUUID } from 'node:crypto'
import { chmod, lstat, mkdir, open, readFile, rename, rm, stat } from 'node:fs/promises'
import { basename, dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

export const MAX_BYTES = 16 * 1024 * 1024
const SKIP_PREFIX = ['query.', 'survey.', 'core.', 'realtime.']
const CATALOGS = {
  'catalog.exoplanets': ['stars', 100],
  'catalog.meteor-showers': ['showers', 1],
  'catalog.novae': ['nova', 1],
  'catalog.supernovae': ['supernova', 1],
  'catalog.pulsars': ['pulsars', 100],
  'catalog.quasars': ['quasars', 100],
}
const CSV_FIELDS = ['OBJECT_NAME', 'OBJECT_ID', 'EPOCH', 'MEAN_MOTION', 'ECCENTRICITY',
  'INCLINATION', 'RA_OF_ASC_NODE', 'ARG_OF_PERICENTER', 'MEAN_ANOMALY', 'EPHEMERIS_TYPE',
  'CLASSIFICATION_TYPE', 'NORAD_CAT_ID', 'ELEMENT_SET_NO', 'REV_AT_EPOCH', 'BSTAR',
  'MEAN_MOTION_DOT', 'MEAN_MOTION_DDOT']

class MirrorError extends Error {}

function requireValid(condition, code = 'invalid_payload') {
  if (!condition) throw new MirrorError(code)
}

function object(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
}

function finiteNumber(value) {
  return typeof value === 'string' && /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value.trim()) && Number.isFinite(Number(value))
}

function decodeAlpha5NoradId(field) {
  if (typeof field !== 'string' || field.length !== 5) return NaN
  if (/^\d{5}$/.test(field)) return Number(field)
  const alphabet = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ'
  const lead = alphabet.indexOf(field[0])
  if (lead < 10 || !/^\d{4}$/.test(field.slice(1))) return NaN
  return lead * 10000 + Number(field.slice(1))
}

function validTlePair(first, second) {
  const checksumValid = (line) => {
    if (typeof line !== 'string' || line.length !== 69 || !/\d$/.test(line)) return false
    const sum = [...line.slice(0, 68)].reduce((total, char) =>
      total + (/\d/.test(char) ? Number(char) : char === '-' ? 1 : 0), 0)
    return sum % 10 === Number(line[68])
  }
  requireValid(checksumValid(first) && checksumValid(second))
  requireValid(/^1 [0-9A-HJ-NP-Z][0-9]{4}[UCS] /.test(first) && /^2 /.test(second))
  requireValid(/^[ +\-]\.\d{8}$/.test(first.slice(33, 43)))
  requireValid(/^[ +\-]\d{5}[+\-]\d$/.test(first.slice(44, 52)))
  requireValid(/^[ +\-]\d{5}[+\-]\d$/.test(first.slice(53, 61)))
  requireValid(first.slice(2, 7) === second.slice(2, 7))
  requireValid(/^\d{2}\d{3}\.\d{8}$/.test(first.slice(18, 32)))
  const epochDay = Number(first.slice(20, 32))
  const shortYear = Number(first.slice(18, 20))
  const year = shortYear >= 57 ? 1900 + shortYear : 2000 + shortYear
  const daysInYear = (Date.UTC(year + 1, 0, 1) - Date.UTC(year, 0, 1)) / 86400000
  requireValid(epochDay >= 1 && epochDay < daysInYear + 1)
  for (const [start, end, maximum] of [[8, 16, 180], [17, 25, 360], [34, 42, 360], [43, 51, 360]]) {
    const field = second.slice(start, end)
    requireValid(finiteNumber(field) && Number(field) >= 0 && Number(field) <= maximum)
  }
  requireValid(/^\d{7}$/.test(second.slice(26, 33)))
  requireValid(finiteNumber(second.slice(52, 63)) && Number(second.slice(52, 63)) > 0)
}

function parseCsv(text) {
  const rows = []
  let row = []
  let field = ''
  let quoted = false
  let closedQuote = false
  for (let offset = 0; offset < text.length; offset++) {
    const char = text[offset]
    if (quoted) {
      if (char === '"' && text[offset + 1] === '"') { field += '"'; offset++ }
      else if (char === '"') { quoted = false; closedQuote = true }
      else field += char
    } else if (char === '"') {
      requireValid(field === '' && !closedQuote)
      quoted = true
    } else if (char === ',' || char === '\n') {
      row.push(field)
      field = ''
      closedQuote = false
      if (char === '\n') { rows.push(row); row = [] }
    } else {
      requireValid(!closedQuote)
      field += char
    }
  }
  requireValid(!quoted)
  if (field !== '' || row.length || closedQuote) { row.push(field); rows.push(row) }
  return rows
}

function hasUnsafeText(value) {
  return typeof value === 'string' && /https?:\/\/|<\s*\/?\s*(?:script|iframe|a\b|img\b)|[\x00-\x08\x0b\x0c\x0e-\x1f]/i.test(value)
}

export function sanitizeSpaceflightCrewPayload(text) {
  const value = JSON.parse(text)
  const cleanPeople = value.people.map((person, index) => ({
    id: typeof person.id === 'number' && Number.isInteger(person.id) ? person.id : index + 1,
    name: person.name.trim(),
    country: person.country.trim(),
    flag_code: typeof person.flag_code === 'string' ? person.flag_code.trim().toLowerCase().slice(0, 8) : '',
    agency: typeof person.agency === 'string' ? person.agency.trim().slice(0, 80) : '',
    position: typeof person.position === 'string' ? person.position.trim().slice(0, 80) : '',
    spacecraft: person.spacecraft.trim(),
    launched: typeof person.launched === 'number' && Number.isFinite(person.launched) ? Math.trunc(person.launched) : 0,
    iss: person.iss === true,
  }))
  const cleanDoc = {
    number: cleanPeople.length,
    iss_expedition: typeof value.iss_expedition === 'number' && Number.isInteger(value.iss_expedition) ? value.iss_expedition : 0,
    people: cleanPeople,
  }
  return Buffer.from(`${JSON.stringify(cleanDoc, null, 2)}\n`, 'utf8')
}

export function validatePayload(body, source) {
  const text = body.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').trim()
  requireValid(text.length > 0 && !/^\s*(?:<!doctype|<html|invalid query|error\b)/i.test(text))
  if (source.format === 'tle-3le') {
    const lines = text.split('\n')
    requireValid(lines.length % 3 === 0)
    for (let offset = 0; offset < lines.length; offset += 3) {
      requireValid(lines[offset].trim().length > 0)
      validTlePair(lines[offset + 1], lines[offset + 2])
    }
    return lines.length / 3
  }
  if (source.format === 'csv') {
    const [header, ...rows] = parseCsv(text)
    requireValid(header && new Set(header).size === header.length && CSV_FIELDS.every((key) => header.includes(key)))
    requireValid(rows.length > 0)
    for (const row of rows) {
      requireValid(row.length === header.length)
      const record = Object.fromEntries(header.map((key, index) => [key, row[index].trim()]))
      requireValid(record.OBJECT_NAME !== '' && /^[UCS]$/.test(record.CLASSIFICATION_TYPE))
      requireValid(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?$/.test(record.EPOCH) &&
        Number.isFinite(Date.parse(record.EPOCH.endsWith('Z') ? record.EPOCH : `${record.EPOCH}Z`)))
      requireValid(new Date(record.EPOCH.endsWith('Z') ? record.EPOCH : `${record.EPOCH}Z`).toISOString().slice(0, 19) === record.EPOCH.slice(0, 19))
      for (const key of CSV_FIELDS.slice(3).filter((key) => key !== 'CLASSIFICATION_TYPE')) {
        requireValid(finiteNumber(record[key]))
      }
      for (const key of ['NORAD_CAT_ID', 'EPHEMERIS_TYPE', 'ELEMENT_SET_NO', 'REV_AT_EPOCH']) {
        requireValid(/^\d+$/.test(record[key]))
      }
      requireValid(Number(record.NORAD_CAT_ID) > 0 && Number(record.MEAN_MOTION) > 0 &&
        Number(record.ECCENTRICITY) >= 0 && Number(record.ECCENTRICITY) < 1 &&
        Number(record.INCLINATION) >= 0 && Number(record.INCLINATION) <= 180)
      for (const key of ['RA_OF_ASC_NODE', 'ARG_OF_PERICENTER', 'MEAN_ANOMALY']) {
        requireValid(Number(record[key]) >= 0 && Number(record[key]) <= 360)
      }
    }
    return rows.length
  }
  if (source.format === 'satnogs-json' || source.format === 'json') {
    let value
    try { value = JSON.parse(text) } catch { throw new MirrorError('invalid_payload') }
    if (source.format === 'satnogs-json') {
      requireValid(Array.isArray(value) && value.length > 0)
      for (const record of value) {
        requireValid(object(record) && /^\d+$/.test(String(record.norad_cat_id)) && Number(record.norad_cat_id) > 0)
        validTlePair(record.tle1, record.tle2)
        const recordNorad = Number(record.norad_cat_id)
        const tleNorad = decodeAlpha5NoradId(record.tle1.slice(2, 7))
        // Accept exact NORAD match (including Alpha-5 >= 100000) or SatNOGS temporary IDs (98000-99999)
        // linked to a valid assigned Space-Track TLE.
        const isSatnogsTempId = recordNorad >= 98000 && recordNorad <= 99999 && Number.isFinite(tleNorad) && tleNorad > 0
        requireValid(tleNorad === recordNorad || isSatnogsTempId)
      }
      return value.length
    }
    const schema = CATALOGS[source.id]
    requireValid(schema, 'unsupported_format')
    requireValid(object(value) && /^(?:[1-9]\d*)$/.test(String(value.version)) && object(value[schema[0]]))
    const records = Object.values(value[schema[0]])
    requireValid(records.length >= schema[1] && records.every((record) => object(record) && Object.keys(record).length > 0))
    return records.length
  }
  if (source.format === 'mpc-comet-lines') {
    const rawLines = body.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').split('\n')
    const lines = rawLines.map((l) => l.trimEnd()).filter((l) => l.trim().length > 0)
    requireValid(lines.length >= 1)
    let validCount = 0
    for (const line of lines) {
      if (line.length < 103) continue
      const periDate = line.slice(14, 30).trim()
      const qStr = line.slice(30, 40).trim()
      const eStr = line.slice(41, 50).trim()
      const argPeriStr = line.slice(51, 60).trim()
      const nodeStr = line.slice(61, 70).trim()
      const inclStr = line.slice(71, 80).trim()
      const nameStr = line.slice(102).trim()
      const okDate = /^\d{4}\s+\d{1,2}\s+\d{1,2}(?:\.\d+)?$/.test(periDate)
      const okNum = finiteNumber(qStr) && Number(qStr) > 0 &&
        finiteNumber(eStr) && Number(eStr) >= 0 &&
        finiteNumber(argPeriStr) && Number(argPeriStr) >= 0 && Number(argPeriStr) <= 360 &&
        finiteNumber(nodeStr) && Number(nodeStr) >= 0 && Number(nodeStr) <= 360 &&
        finiteNumber(inclStr) && Number(inclStr) >= 0 && Number(inclStr) <= 180
      if (okDate && okNum && nameStr.length > 0) validCount++
    }
    requireValid(validCount > 0 && validCount * 20 >= lines.length * 19)
    return validCount
  }
  if (source.format === 'mpc-minor-planet-lines') {
    const rawLines = body.replace(/^\uFEFF/, '').replaceAll('\r\n', '\n').split('\n')
    const lines = rawLines.map((l) => l.trimEnd()).filter((l) => l.trim().length > 0)
    requireValid(lines.length >= 1)
    let validCount = 0
    for (const line of lines) {
      if (line.length < 167) continue
      const desig = line.slice(0, 7).trim()
      const epoch = line.slice(20, 25).trim()
      const mStr = line.slice(26, 35).trim()
      const periStr = line.slice(37, 46).trim()
      const nodeStr = line.slice(48, 57).trim()
      const inclStr = line.slice(59, 68).trim()
      const eStr = line.slice(70, 79).trim()
      const nStr = line.slice(80, 91).trim()
      const aStr = line.slice(92, 103).trim()
      const readableName = line.slice(166).trim()
      const okEpoch = /^[IJK][0-9A-Za-z]{4}$/.test(epoch)
      const okNum = finiteNumber(mStr) && finiteNumber(periStr) && finiteNumber(nodeStr) &&
        finiteNumber(inclStr) && Number(inclStr) >= 0 && Number(inclStr) <= 180 &&
        finiteNumber(eStr) && Number(eStr) >= 0 && Number(eStr) < 1.5 &&
        finiteNumber(nStr) && Number(nStr) > 0 &&
        finiteNumber(aStr) && Number(aStr) > 0
      if (desig.length > 0 && okEpoch && okNum && readableName.length > 0) validCount++
    }
    requireValid(validCount > 0 && validCount * 20 >= lines.length * 19)
    return validCount
  }
  if (source.format === 'spaceflight-crew-json') {
    let value
    try { value = JSON.parse(text) } catch { throw new MirrorError('invalid_payload') }
    requireValid(object(value) && Array.isArray(value.people) && value.people.length <= 200)
    if (value.number !== undefined) {
      requireValid(typeof value.number === 'number' && Number.isInteger(value.number) && value.number >= 0 && value.number <= 200)
    }
    for (const person of value.people) {
      requireValid(object(person))
      requireValid(typeof person.name === 'string' && person.name.trim().length > 0 && person.name.length <= 120 && !hasUnsafeText(person.name))
      requireValid(typeof person.country === 'string' && person.country.trim().length > 0 && person.country.length <= 80 && !hasUnsafeText(person.country))
      requireValid(typeof person.spacecraft === 'string' && person.spacecraft.trim().length > 0 && person.spacecraft.length <= 120 && !hasUnsafeText(person.spacecraft))
      requireValid((person.agency === undefined || (typeof person.agency === 'string' && !hasUnsafeText(person.agency))) &&
        (person.position === undefined || (typeof person.position === 'string' && !hasUnsafeText(person.position))) &&
        (person.flag_code === undefined || (typeof person.flag_code === 'string' && !hasUnsafeText(person.flag_code))))
      requireValid(typeof person.iss === 'boolean')
    }
    return value.people.length
  }
  throw new MirrorError('unsupported_format')
}

export async function fetchOne(source, { fetchImpl = fetch, maxBytes = MAX_BYTES, timeoutMs = 60000 } = {}) {
  requireValid(['csv', 'tle-3le', 'satnogs-json', 'json', 'mpc-comet-lines', 'mpc-minor-planet-lines', 'spaceflight-crew-json'].includes(source.format) &&
    (source.format !== 'json' || Object.hasOwn(CATALOGS, source.id)), 'unsupported_format')
  const controller = new AbortController()
  let reader
  let timer
  const deadline = new Promise((_, reject) => {
    timer = setTimeout(() => { reject(new MirrorError('download_timeout')); controller.abort() }, timeoutMs)
  })
  try {
    const download = async () => {
      const targetUrl = source.upstreamUrl.replace(
        /\/iau\/Ephemerides\/Bright\/\d{4}\/Soft00Bright\.txt$/,
        `/iau/Ephemerides/Bright/${new Date().getUTCFullYear()}/Soft00Bright.txt`
      )
      const response = await fetchImpl(targetUrl, {
        signal: controller.signal,
        headers: { 'user-agent': 'SkyInstrumentMirror/1.0 (+https://skyinstrument.cn)' },
      })
      requireValid(response.ok, `http_${response.status}`)
      const length = response.headers.get('content-length')
      requireValid(length === null || (/^\d+$/.test(length) && Number(length) <= maxBytes), 'payload_too_large')
      requireValid(response.body, 'empty_payload')
      reader = response.body.getReader()
      const chunks = []
      let bytes = 0
      while (true) {
        const chunk = await reader.read()
        if (chunk.done) break
        bytes += chunk.value.byteLength
        requireValid(bytes <= maxBytes, 'payload_too_large')
        chunks.push(chunk.value)
      }
      const payload = Buffer.concat(chunks, bytes)
      let text
      try { text = new TextDecoder('utf-8', { fatal: true }).decode(payload) }
      catch { throw new MirrorError('invalid_encoding') }
      validatePayload(text, source)
      if (source.format === 'spaceflight-crew-json') {
        return sanitizeSpaceflightCrewPayload(text)
      }
      return payload
    }
    return await Promise.race([download(), deadline])
  } catch (error) {
    throw error instanceof MirrorError ? error : new MirrorError('download_failed')
  } finally {
    clearTimeout(timer)
    controller.abort()
    if (reader) void reader.cancel().catch(() => {})
  }
}

export async function atomicWrite(destination, payload, { stagingDirectory = dirname(destination), renameFile = rename } = {}) {
  await mkdir(dirname(destination), { recursive: true })
  const temporary = join(stagingDirectory, `.${basename(destination)}.${randomUUID()}.tmp`)
  try {
    const file = await open(temporary, 'wx', 0o644)
    try { await file.writeFile(payload); await file.sync() } finally { await file.close() }
    await renameFile(temporary, destination)
  } finally {
    await rm(temporary, { force: true })
  }
}

function digest(payload) {
  return createHash('sha256').update(payload).digest('hex')
}

function validDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/.test(value) && Number.isFinite(Date.parse(value))
}

async function retainedEntry(root, source, previous, previousGeneratedAt) {
  const entry = { id: source.id, path: source.mirrorPath, ok: false, available: false, stale: true,
    status: 'unavailable', lastSuccessAt: null }
  try {
    const destination = join(root, source.mirrorPath.slice(1))
    const info = await stat(destination)
    requireValid(info.isFile() && info.size <= MAX_BYTES)
    const payload = await readFile(destination)
    validatePayload(new TextDecoder('utf-8', { fatal: true }).decode(payload), source)
    const sha256 = digest(payload)
    if (previous?.sha256) requireValid(previous.path === source.mirrorPath && previous.sha256 === sha256 && previous.bytes === payload.length)
    const matches = previous?.path === source.mirrorPath && previous.sha256 === sha256 && previous.bytes === payload.length
    const lastSuccessAt = matches && validDate(previous.lastSuccessAt) ? previous.lastSuccessAt :
      matches && previous.ok === true && validDate(previousGeneratedAt) ? previousGeneratedAt : null
    return { ...entry, bytes: payload.length, sha256, available: true, status: 'stale', lastSuccessAt }
  } catch { return entry }
}

export async function runMirror({ root, sources, only = '', dryRun = false, fetchImpl = fetch,
  validateOnly = false, batchBudgetMs = 600000, interRequestDelayMs = (fetchImpl === fetch ? 350 : 0),
  now = () => new Date().toISOString(), publish = atomicWrite, logger = console }) {
  const startedAt = performance.now()
  const mirrors = sources.filter((source) => !SKIP_PREFIX.some((prefix) => source.id.startsWith(prefix)))
  const ids = new Set()
  const paths = new Set()
  for (const source of mirrors) {
    requireValid(/^[A-Za-z0-9.-]+$/.test(source.id) && !ids.has(source.id), 'invalid_registry')
    requireValid(/^\/v1\/catalogs\/(?:[A-Za-z0-9_-][A-Za-z0-9._-]*\/)*[A-Za-z0-9_-][A-Za-z0-9._-]*$/.test(source.mirrorPath) &&
      !paths.has(source.mirrorPath), 'invalid_registry')
    const upstream = new URL(source.upstreamUrl)
    requireValid(upstream.protocol === 'https:' && !upstream.username && !upstream.password, 'invalid_registry')
    ids.add(source.id)
    paths.add(source.mirrorPath)
  }
  requireValid(mirrors.some((source) => source.id.startsWith(only)), 'no_sources_selected')
  const manifestPath = join(root, 'v1', 'manifest.json')
  const lockPath = join(root, '.refresh.lock')
  if (!dryRun) {
    await mkdir(root, { recursive: true })
    try { await mkdir(lockPath) } catch { throw new MirrorError('refresh_lock_unavailable') }
  }
  try {
    let previous = {}
    try { previous = JSON.parse(await readFile(manifestPath, 'utf8')) } catch {}
    const previousEntries = new Map((Array.isArray(previous?.sources) ? previous.sources : [])
      .filter((entry) => object(entry)).map((entry) => [entry.id, entry]))
    const manifest = { generatedAt: now(), sources: [] }
    let attempted = 0
    let failed = 0
    for (const source of mirrors) {
      const old = previousEntries.get(source.id)
      let entry = await retainedEntry(root, source, old, previous?.generatedAt)
      if (!dryRun && !entry.available) {
        const destination = join(root, source.mirrorPath.slice(1))
        let existing
        try { existing = await lstat(destination) } catch (error) { if (error.code !== 'ENOENT') throw error }
        if (existing) {
          requireValid(existing.isFile() && !existing.isSymbolicLink(), 'unsafe_existing_file')
          const quarantine = join(root, '.quarantine')
          await mkdir(quarantine, { recursive: true, mode: 0o700 })
          await chmod(quarantine, 0o700)
          await rename(destination, join(quarantine, `${source.id}-${randomUUID()}`))
          logger.log(`quarantined ${source.id}`)
        }
      }
      if (validateOnly || !source.id.startsWith(only)) {
        if (entry.available && old?.ok === true && old.sha256 === entry.sha256 && entry.lastSuccessAt &&
            Date.parse(now()) - Date.parse(entry.lastSuccessAt) < 12 * 3600000) {
          entry = { ...entry, ok: true, stale: false, status: 'fresh' }
        }
        if (validDate(old?.lastAttemptAt)) entry.lastAttemptAt = old.lastAttemptAt
        if (!entry.ok) entry.error = 'not_refreshed'
        if (validateOnly && !entry.ok) failed++
      } else {
        attempted++
        const attemptedAt = now()
        try {
          requireValid(performance.now() - startedAt < batchBudgetMs, 'batch_timeout')
          if (attempted > 1 && interRequestDelayMs > 0) {
            await new Promise((resolveDelay) => setTimeout(resolveDelay, interRequestDelayMs))
          }
          let payload
          try {
            payload = await fetchOne(source, { fetchImpl })
          } catch (firstError) {
            if (interRequestDelayMs > 0 && firstError instanceof MirrorError &&
              (firstError.message === 'http_403' || firstError.message === 'http_429') &&
              performance.now() - startedAt + 2000 < batchBudgetMs) {
              await new Promise((resolveDelay) => setTimeout(resolveDelay, 2000))
              payload = await fetchOne(source, { fetchImpl })
            } else {
              throw firstError
            }
          }
          if (!dryRun) {
            try { await publish(join(root, source.mirrorPath.slice(1)), payload, { stagingDirectory: root }) }
            catch { throw new MirrorError('publish_failed') }
          }
          entry = { id: source.id, path: source.mirrorPath, bytes: payload.length, sha256: digest(payload),
            ok: true, available: true, stale: false, status: 'fresh', lastAttemptAt: attemptedAt, lastSuccessAt: now() }
        } catch (error) {
          failed++
          entry = { ...entry, lastAttemptAt: attemptedAt,
            error: error instanceof MirrorError ? error.message : 'refresh_failed' }
        }
      }
      manifest.sources.push(entry)
      logger.log(`${entry.ok ? 'ok' : 'FAIL'} ${entry.id}: ${entry.status}${entry.error ? ` (${entry.error})` : ''}`)
    }
    if (!dryRun) await publish(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { stagingDirectory: root })
    logger.log(validateOnly ? `${manifest.sources.filter(entry => entry.available).length}/${mirrors.length} retained sources validated` : `${attempted - failed}/${attempted} sources refreshed`)
    return { manifest, exitCode: failed > 0 ? 1 : 0 }
  } finally {
    if (!dryRun) await rm(lockPath, { recursive: true, force: true })
  }
}

async function main(args) {
  const options = { root: '/srv/tle-mirror', registryPath: fileURLToPath(new URL('./sources.json', import.meta.url)) }
  for (let index = 0; index < args.length; index++) {
    const argument = args[index]
    if (argument === '--dry-run') options.dryRun = true
    else if (argument === '--validate-only') options.validateOnly = true
    else if (['--root', '--sources', '--only'].includes(argument) && args[index + 1] && !args[index + 1].startsWith('--')) {
      const key = argument === '--sources' ? 'registryPath' : argument.slice(2)
      options[key] = args[++index]
    } else throw new MirrorError('invalid_arguments')
  }
  const registry = JSON.parse(await readFile(options.registryPath, 'utf8'))
  const result = await runMirror({ ...options, sources: registry.sources })
  process.exitCode = result.exitCode
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof MirrorError ? error.message : 'mirror_failed')
    process.exitCode = 1
  })
}
