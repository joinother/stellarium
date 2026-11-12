import assert from 'node:assert/strict'
import test from 'node:test'
import { summarizeMirror } from '../publish-status.mjs'

test('expired fresh manifest becomes degraded even if fetching has stopped', () => {
  const result = summarizeMirror({ generatedAt: '2026-11-12T00:00:00Z', sources: [
    { available: true, status: 'fresh' }, { available: false, status: 'unavailable' }
  ] }, Date.parse('2026-11-12T13:00:00Z'))
  assert.equal(result.manifestExpired, true)
  assert.deepEqual(result.sources, { fresh: 0, stale: 1, unavailable: 1 })
  assert.equal(result.status, 'degraded')
})

test('absent manifest is unavailable, never healthy', () => {
  assert.equal(summarizeMirror(null).status, 'unavailable')
})

test('health output cannot copy raw error messages or upstream URLs', () => {
  const result = summarizeMirror({ generatedAt: new Date().toISOString(), sources: [
    { available: true, status: 'fresh', error: 'secret', upstreamUrl: 'https://secret.invalid' }
  ] })
  assert.equal(result.status, 'fresh')
  assert.doesNotMatch(JSON.stringify(result), /secret/)
})
