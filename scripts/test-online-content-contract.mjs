import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign, createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { decideDelivery, validateSubscription, verifyResourceRelease, verifyResourceBytes } from '../deploy/content-service/contracts.mjs';

const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const keys = { test: publicKey.export({ type: 'spki', format: 'pem' }) };
const now = Date.UTC(2026, 10, 11, 16);
const preferences = { schemaVersion: 1, revision: 1, language: 'zh-CN', timeZone: 'Asia/Shanghai', astronomy: true, digest: false, quietEnabled: true, quietStart: 1350, quietEnd: 395 };
const notice = { schemaVersion: 1, messageId: 'event-1', category: 'astronomy', issuedAt: now - 1000, expiresAt: now + 86400000, reference: { kind: 'event', id: 'meteor', revision: 1 } };
const bytes = Buffer.from('verified fixture');
const hash = createHash('sha256').update(bytes).digest('hex');
const release = { schemaVersion: 2, generation: 3, minimumBuild: 1, issuedAt: now - 1000, expiresAt: now + 86400000,
  resources: [{ id: 'tle.stations', path: `/v2/blobs/${hash}`, bytes: bytes.length, sha256: hash, format: 'tle-3le', license: 'fixture-only' }] };
const envelope = value => { const payload = JSON.stringify(value); return { keyId: 'test', payload, signature: sign(null, Buffer.from(payload), privateKey).toString('base64') }; };
const verifyOptions = { now, acceptedGeneration: 2, clientBuild: 1000054 };
const source = readFileSync(new URL('../harmonyos/ets-source/state/OnlineContentContract.ts', import.meta.url), 'utf8');
const client = await import(`data:text/javascript,${encodeURIComponent(stripTypeScriptTypes(source))}`);

test('subscriptions and cross-midnight local quiet hours gate server delivery', () => {
  assert.equal(decideDelivery(notice, preferences, now), 'quiet');
  assert.equal(decideDelivery(notice, { ...preferences, timeZone: 'UTC' }, now), 'send');
  assert.equal(decideDelivery({ ...notice, category: 'digest' }, preferences, now), 'unsubscribed');
  assert.throws(() => validateSubscription({ ...preferences, sn: 'must-not-upload' }));
  assert.throws(() => validateSubscription({ ...preferences, timeZone: '../etc' }));
});
test('stale and malformed push references never become navigation or download instructions', () => {
  assert.equal(client.validContentNotice(notice, now), true);
  for (const bad of [{ ...notice, expiresAt: now }, { ...notice, reference: { ...notice.reference, id: '../file' } }, { ...notice, issuedAt: now + 600000 }]) {
    assert.equal(client.validContentNotice(bad, now), false);
    assert.equal(decideDelivery(bad, preferences, now), 'reject');
  }
  assert.equal(client.validResourceHint({ schemaVersion: 1, kind: 'resources-changed', generation: 3 }), true);
  assert.equal(client.validResourceHint({ schemaVersion: 1, kind: 'resources-changed', generation: -1 }), false);
});
test('trusted signature, monotonic generation, compatibility and immutable paths required', () => {
  assert.equal(verifyResourceRelease(envelope(release), keys, verifyOptions).generation, 3);
  for (const bad of [{ ...release, generation: 1 }, { ...release, expiresAt: now }, { ...release, minimumBuild: 9999999 },
    { ...release, resources: [{ ...release.resources[0], path: '/v2/../etc/passwd' }] },
    { ...release, resources: [release.resources[0], release.resources[0]] }]) assert.throws(() => verifyResourceRelease(envelope(bad), keys, verifyOptions));
  const signed = envelope(release);
  assert.throws(() => verifyResourceRelease(signed, keys, { ...verifyOptions, acceptedGeneration: 3 }));
  assert.equal(verifyResourceRelease(signed, keys, { ...verifyOptions, acceptedGeneration: 3,
    acceptedPayloadSha256: createHash('sha256').update(signed.payload).digest('hex') }).generation, 3);
  assert.throws(() => verifyResourceRelease({ ...signed, payload: signed.payload + ' ' }, keys, verifyOptions));
  assert.throws(() => verifyResourceRelease({ ...signed, keyId: 'unknown' }, keys, verifyOptions));
  assert.equal(verifyResourceBytes(bytes, release.resources[0]), true);
  assert.throws(() => verifyResourceBytes(Buffer.from('corrupt fixture!'), release.resources[0]));
});
