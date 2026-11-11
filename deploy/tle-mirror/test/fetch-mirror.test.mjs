import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { mkdtemp, mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import test from 'node:test'
import { atomicWrite, fetchOne, MAX_BYTES, runMirror, validatePayload } from '../fetch-mirror.mjs'
import { csv, csvHeader, csvRow, csvSource, json, jsonSource, satnogs, tle, tle1, tle2 } from './fixtures.mjs'

const logger = { log() {} }
const firstTime = '2026-11-11T12:00:00.000Z'
const nextTime = '2026-11-11T15:00:00.000Z'
const sha256 = (value) => createHash('sha256').update(value).digest('hex')
const mockFetch = async (url) => new Response(url.endsWith('.csv') ? csv : json)

async function workspace(context) {
  const root = await mkdtemp(join(tmpdir(), 'tle-mirror-test-'))
  context.after(() => rm(root, { recursive: true, force: true }))
  return root
}

function run(root, overrides = {}) {
  return runMirror({ root, sources: [csvSource], fetchImpl: mockFetch, now: () => firstTime, logger, ...overrides })
}

test('CSV accepts quoted commas, escaped quotes, CRLF and a complete orbital row', () => {
  assert.equal(validatePayload(csv, csvSource), 1)
  assert.equal(validatePayload(`\uFEFF${csv}`, csvSource), 1)
})

test('CSV rejects the observed Invalid query response and malformed or empty catalogues', () => {
  for (const body of ['Invalid query: "GROUP=gpz&FORMAT=CSV" (GROUP=gpz not found)',
    '<!DOCTYPE HTML><HTML>denied</HTML>', csvHeader, `${csvHeader}\n${csvRow},extra`,
    csv.replace('MEAN_MOTION,', 'MISSING,'), csv.replace('15.49150046', 'NaN'),
    csv.replace('15.49150046', '0x10'), csv.replace('0.0007139', '1.5'),
    csv.replace('2026-11-02', '2026-02-30'), csv.replace('51.6332', '181'),
    `${csvHeader}\n"unterminated`, `${csvHeader}\n${csvRow}\ninvalid row`]) {
    assert.throws(() => validatePayload(body, csvSource), /invalid_payload/)
  }
})

test('TLE requires complete triples, matching catalogue ids, checksums and valid orbital fields', () => {
  const source = { format: 'tle-3le' }
  assert.equal(validatePayload(tle, source), 1)
  const otherId = tle2.replace('25544', '25553')
  for (const body of [`ISS\n${tle1}`, `${tle}\nbroken`, tle.replace(tle2, otherId),
    tle.replace(tle1, `${tle1.slice(0, -1)}0`), 'ISS\n1 25544\n2 25544']) {
    assert.throws(() => validatePayload(body, source), /invalid_payload/)
  }
})

test('SatNOGS requires a nonempty array with matching NORAD ids and complete valid TLE pairs', () => {
  const source = { format: 'satnogs-json' }
  assert.equal(validatePayload(satnogs, source), 1)
  for (const body of ['[]', '{}', '{"error":"denied"}', '[null]',
    JSON.stringify([{ norad_cat_id: 25545, tle1, tle2 }]),
    JSON.stringify([{ norad_cat_id: 25544, tle1 }])]) {
    assert.throws(() => validatePayload(body, source), /invalid_payload/)
  }
})

test('JSON validates known catalogue schemas and minimum counts; unsupported formats fail closed', () => {
  assert.equal(validatePayload(json, jsonSource), 1)
  for (const body of ['null', '[]', '{}', '{"error":"failure"}', '{"version":1,"nova":{}}',
    '{"version":1,"nova":{"fixture":null}}', '{"version":1,"nova":{"fixture":{}}}']) {
    assert.throws(() => validatePayload(body, jsonSource), /invalid_payload/)
  }
  assert.throws(() => validatePayload('{"version":1,"pulsars":{"one":{"name":"one"}}}',
    { id: 'catalog.pulsars', format: 'json' }), /invalid_payload/)
  assert.throws(() => validatePayload('apparently valid text', { format: 'mpc-orbit-elements' }), /unsupported_format/)
})

test('all six bundled JSON catalogue schemas pass without any downloads', async () => {
  for (const [folder, filename, id] of [
    ['Exoplanets', 'exoplanets', 'exoplanets'], ['MeteorShowers', 'MeteorShowers', 'meteor-showers'],
    ['Novae', 'novae', 'novae'], ['Supernovae', 'supernovae', 'supernovae'],
    ['Pulsars', 'pulsars', 'pulsars'], ['Quasars', 'quasars', 'quasars'],
  ]) {
    const body = await readFile(new URL(`../../../plugins/${folder}/resources/${filename}.json`, import.meta.url), 'utf8')
    assert.ok(validatePayload(body, { id: `catalog.${id}`, format: 'json' }) > 0)
  }
})

test('download preserves original bytes and rejects malformed UTF-8', async () => {
  assert.deepEqual(await fetchOne(csvSource, { fetchImpl: mockFetch }), Buffer.from(csv))
  await assert.rejects(fetchOne(csvSource, { fetchImpl: async () => new Response(new Uint8Array([255, 254])) }), /invalid_encoding/)
})

test('unsupported upstream formats are rejected before any request', async () => {
  await assert.rejects(fetchOne({ ...csvSource, format: 'mpc-orbit-elements' }, {
    fetchImpl: async () => assert.fail('unexpected request'),
  }), /unsupported_format/)
})

test('download enforces both Content-Length and actual streamed bytes, cancelling excess input', async () => {
  await assert.rejects(fetchOne(csvSource, { fetchImpl: async () => new Response(csv,
    { headers: { 'content-length': String(MAX_BYTES + 1) } }) }), /payload_too_large/)
  for (const headers of [{}, { 'content-length': '1' }]) {
    let cancelled = false
    let chunks = 0
    const body = new ReadableStream({
      pull(controller) { chunks++; controller.enqueue(new Uint8Array(8)) },
      cancel() { cancelled = true },
    })
    await assert.rejects(fetchOne(csvSource, { maxBytes: 12,
      fetchImpl: async () => new Response(body, { headers }) }), /payload_too_large/)
    assert.equal(cancelled, true)
    assert.ok(chunks <= 3)
  }
})

test('deadline bounds both an unresponsive fetch and a stalled response body', async () => {
  let signal
  await assert.rejects(fetchOne(csvSource, { timeoutMs: 10, fetchImpl: async (_, options) => {
    signal = options.signal
    return new Promise(() => {})
  } }), /download_timeout/)
  assert.equal(signal.aborted, true)
  let cancelled = false
  await assert.rejects(fetchOne(csvSource, { timeoutMs: 10, fetchImpl: async () =>
    new Response(new ReadableStream({ cancel() { cancelled = true } })) }), /download_timeout/)
  assert.equal(cancelled, true)
})

test('success publishes accurate metadata without server paths or upstream URLs', async (context) => {
  const root = await workspace(context)
  const result = await run(root)
  assert.equal(result.exitCode, 0)
  const manifest = JSON.parse(await readFile(join(root, 'v1/manifest.json')))
  assert.deepEqual(manifest, result.manifest)
  assert.deepEqual(manifest.sources[0], { id: csvSource.id, path: csvSource.mirrorPath,
    bytes: Buffer.byteLength(csv), sha256: sha256(csv), ok: true, available: true,
    stale: false, status: 'fresh', lastAttemptAt: firstTime, lastSuccessAt: firstTime })
  assert.equal(JSON.stringify(manifest).includes(root), false)
  assert.equal(JSON.stringify(manifest).includes('fixtures.invalid'), false)
  assert.equal(await readFile(join(root, csvSource.mirrorPath), 'utf8'), csv)
  assert.deepEqual(await readdir(root), ['v1'])
})

test('failure retains last-good bytes/hash/time and explicitly marks stale through repeated attempts', async (context) => {
  const root = await workspace(context)
  await run(root)
  const failedFetch = async () => new Response('forbidden', { status: 403 })
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await run(root, { fetchImpl: failedFetch, now: () => nextTime })
    const entry = result.manifest.sources[0]
    assert.equal(result.exitCode, 1)
    assert.equal(entry.status, 'stale')
    assert.equal(entry.ok, false)
    assert.equal(entry.available, true)
    assert.equal(entry.stale, true)
    assert.equal(entry.sha256, sha256(csv))
    assert.equal(entry.bytes, Buffer.byteLength(csv))
    assert.equal(entry.lastSuccessAt, firstTime)
    assert.equal(entry.lastAttemptAt, nextTime)
    assert.equal(entry.error, 'http_403')
    assert.equal(await readFile(join(root, csvSource.mirrorPath), 'utf8'), csv)
  }
})

test('first failure is unavailable and network exception details never enter the manifest', async (context) => {
  const root = await workspace(context)
  const result = await run(root, { fetchImpl: async () => { throw new Error('/private/key https://secret.invalid/?token=secret') } })
  const entry = result.manifest.sources[0]
  assert.equal(entry.available, false)
  assert.equal(entry.status, 'unavailable')
  assert.equal(entry.lastSuccessAt, null)
  assert.equal(entry.error, 'download_failed')
  assert.equal('sha256' in entry, false)
  assert.doesNotMatch(JSON.stringify(result.manifest), /private|secret|root/)
})

test('legacy manifests are sanitized and last-good time is migrated only when bytes match', async (context) => {
  const root = await workspace(context)
  await run(root)
  const path = join(root, 'v1/manifest.json')
  await writeFile(path, JSON.stringify({ generatedAt: firstTime, root: '/srv/private', sources: [{
    id: csvSource.id, path: csvSource.mirrorPath, bytes: Buffer.byteLength(csv), sha256: sha256(csv), ok: true,
    secret: 'private-value', error: '/srv/private/details',
  }] }))
  const result = await run(root, { fetchImpl: async () => new Response('Invalid query: missing group'), now: () => nextTime })
  assert.equal(result.manifest.sources[0].lastSuccessAt, firstTime)
  assert.doesNotMatch(JSON.stringify(result.manifest), /private|secret/)
})

test('legacy failure without metadata can recover validated bytes but never invents a success time', async (context) => {
  const root = await workspace(context)
  await mkdir(join(root, 'v1/catalogs/satellites'), { recursive: true })
  await writeFile(join(root, csvSource.mirrorPath), csv)
  await writeFile(join(root, 'v1/manifest.json'), JSON.stringify({ generatedAt: firstTime, sources: [
    { id: csvSource.id, path: csvSource.mirrorPath, ok: false, error: 'HTTP 403' },
  ] }))
  const result = await run(root, { fetchImpl: async () => new Response('bad', { status: 403 }) })
  assert.equal(result.manifest.sources[0].available, true)
  assert.equal(result.manifest.sources[0].lastSuccessAt, null)
  assert.equal(result.manifest.sources[0].sha256, sha256(csv))
})

test('corrupt or hash-mismatched retained files are not advertised as last-good', async (context) => {
  const root = await workspace(context)
  for (const corrupt of ['Invalid query: missing group', csv.replace('51.6332', '51.6333')]) {
    await run(root)
    await writeFile(join(root, csvSource.mirrorPath), corrupt)
    const result = await run(root, { fetchImpl: async () => new Response('bad', { status: 403 }) })
    assert.equal(result.manifest.sources[0].available, false)
    assert.equal('sha256' in result.manifest.sources[0], false)
  }
})

test('partial failure publishes other valid sources and returns a failing exit code', async (context) => {
  const root = await workspace(context)
  const result = await run(root, { sources: [csvSource, jsonSource], fetchImpl: async (url) =>
    new Response(url.endsWith('.csv') ? 'Invalid query: missing group' : json) })
  assert.equal(result.exitCode, 1)
  assert.equal(result.manifest.sources[0].available, false)
  assert.equal(result.manifest.sources[1].ok, true)
})

test('--only preserves validated unselected entries; --dry-run writes nothing', async (context) => {
  const root = await workspace(context)
  await run(root, { sources: [csvSource, jsonSource] })
  const result = await run(root, { sources: [csvSource, jsonSource], only: 'catalog.', now: () => nextTime,
    fetchImpl: async (url) => { assert.equal(url, jsonSource.upstreamUrl); return new Response(json) } })
  assert.equal(result.manifest.sources.length, 2)
  assert.equal(result.manifest.sources[0].lastSuccessAt, firstTime)
  assert.equal(result.manifest.sources[0].ok, true)
  const absentRoot = join(root, 'dry-run')
  await run(absentRoot, { dryRun: true })
  await assert.rejects(readdir(absentRoot), { code: 'ENOENT' })
})

test('invalid registry paths, duplicate paths and empty selections fail before fetch or writes', async (context) => {
  const root = await workspace(context)
  const neverFetch = async () => assert.fail('unexpected fetch')
  for (const mirrorPath of ['/v1/catalogs/../secret', '/v1/catalogs/%2e%2e/secret', '/etc/passwd', '/v1/catalogs/.secret']) {
    await assert.rejects(run(root, { sources: [{ ...csvSource, mirrorPath }], fetchImpl: neverFetch }), /invalid_registry/)
  }
  await assert.rejects(run(root, { sources: [csvSource, { ...csvSource, id: 'duplicate' }], fetchImpl: neverFetch }), /invalid_registry/)
  await assert.rejects(run(root, { only: 'missing', fetchImpl: neverFetch }), /no_sources_selected/)
  assert.deepEqual(await readdir(root), [])
})

test('atomic replacement keeps the old manifest readable until rename and cleans up after failure', async (context) => {
  const root = await workspace(context)
  const destination = join(root, 'manifest.json')
  await writeFile(destination, '{"old":true}')
  await assert.rejects(atomicWrite(destination, '{"new":true}', { renameFile: async (temporary, target) => {
    assert.equal(await readFile(target, 'utf8'), '{"old":true}')
    assert.equal(await readFile(temporary, 'utf8'), '{"new":true}')
    throw new Error('rename failed')
  } }), /rename failed/)
  assert.deepEqual(await readdir(root), ['manifest.json'])
  assert.equal(await readFile(destination, 'utf8'), '{"old":true}')
  await atomicWrite(destination, '{"new":true}')
  assert.deepEqual(JSON.parse(await readFile(destination)), { new: true })
})

test('artifact publication errors retain last-good metadata and redact filesystem errors', async (context) => {
  const root = await workspace(context)
  await run(root)
  const result = await run(root, { publish: async (destination, payload, options) => {
    if (destination.endsWith('.csv')) throw new Error('EACCES /private/files')
    return atomicWrite(destination, payload, options)
  } })
  assert.equal(result.exitCode, 1)
  assert.equal(result.manifest.sources[0].status, 'stale')
  assert.equal(result.manifest.sources[0].error, 'publish_failed')
  assert.equal(await readFile(join(root, csvSource.mirrorPath), 'utf8'), csv)
})

test('manifest publication failure preserves the previous complete manifest and releases the lock', async (context) => {
  const root = await workspace(context)
  await run(root)
  const previous = await readFile(join(root, 'v1/manifest.json'), 'utf8')
  await assert.rejects(run(root, { now: () => nextTime, publish: (destination, payload, options) =>
    atomicWrite(destination, payload, { ...options, renameFile: async (temporary, target) => {
      if (target.endsWith('manifest.json')) throw new Error('manifest rename failed')
      return rename(temporary, target)
    } }) }), /manifest rename failed/)
  assert.equal(await readFile(join(root, 'v1/manifest.json'), 'utf8'), previous)
  assert.deepEqual(await readdir(root), ['v1'])
})

test('overlapping refreshes cannot publish concurrently', async (context) => {
  const root = await workspace(context)
  let release
  let entered
  const started = new Promise((resolve) => { entered = resolve })
  const active = run(root, { fetchImpl: async () => {
    entered()
    return new Promise((resolve) => { release = () => resolve(new Response(csv)) })
  } })
  await started
  try { await assert.rejects(run(root), /refresh_lock_unavailable/) }
  finally { release(); await active }
  assert.deepEqual(await readdir(root), ['v1'])
})
