import { createHash, verify, createPublicKey } from 'node:crypto';

const identifier = value => typeof value === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function validateSubscription(value) {
  if (!object(value) || value.schemaVersion !== 1 || !Number.isSafeInteger(value.revision) || value.revision < 1 ||
      typeof value.language !== 'string' || value.language.length > 40 ||
      typeof value.timeZone !== 'string' || value.timeZone.length > 80 ||
      !['astronomy', 'digest', 'quietEnabled'].every(key => typeof value[key] === 'boolean') ||
      !['quietStart', 'quietEnd'].every(key => Number.isInteger(value[key]) && value[key] >= 0 && value[key] < 1440)) {
    throw new Error('invalid-subscription');
  }
  new Intl.DateTimeFormat(value.language, { timeZone: value.timeZone });
  const allowed = new Set(['schemaVersion', 'revision', 'language', 'timeZone', 'astronomy', 'digest', 'quietStart', 'quietEnd', 'quietEnabled']);
  if (Object.keys(value).some(key => !allowed.has(key))) throw new Error('unexpected-subscription-field');
  return structuredClone(value);
}

export function decideDelivery(notice, subscription, now = Date.now()) {
  validateSubscription(subscription);
  if (!object(notice) || notice.schemaVersion !== 1 || !identifier(notice.messageId) ||
      !['astronomy', 'digest'].includes(notice.category) || !object(notice.reference) ||
      !['article', 'event'].includes(notice.reference.kind) || !identifier(notice.reference.id) ||
      !Number.isSafeInteger(notice.reference.revision) || notice.reference.revision < 1 ||
      !Number.isFinite(now) || !Number.isFinite(notice.issuedAt) || notice.issuedAt > now + 300000 ||
      !Number.isFinite(notice.expiresAt) || notice.expiresAt <= now || notice.expiresAt <= notice.issuedAt ||
      notice.expiresAt - notice.issuedAt > 7 * 86400000) return 'reject';
  if (!subscription[notice.category]) return 'unsubscribed';
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: subscription.timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const minute = Number(parts.find(part => part.type === 'hour').value) * 60 + Number(parts.find(part => part.type === 'minute').value);
  const { quietStart: start, quietEnd: end } = subscription;
  if (subscription.quietEnabled && (start === end || (start < end ? minute >= start && minute < end : minute >= start || minute < end))) return 'quiet';
  return 'send';
}

export function verifyResourceRelease(envelope, trustedKeys, options) {
  if (!object(envelope) || !identifier(envelope.keyId) || typeof envelope.payload !== 'string' ||
      Buffer.byteLength(envelope.payload) > 1024 * 1024 || typeof envelope.signature !== 'string' ||
      !/^[A-Za-z0-9+/]{86}==$/.test(envelope.signature)) throw new Error('invalid-envelope');
  if (!Object.hasOwn(trustedKeys, envelope.keyId)) throw new Error('untrusted-key');
  const publicKey = createPublicKey(trustedKeys[envelope.keyId]);
  if (publicKey.asymmetricKeyType !== 'ed25519' ||
      !verify(null, Buffer.from(envelope.payload, 'utf8'), publicKey, Buffer.from(envelope.signature, 'base64'))) throw new Error('bad-signature');
  const release = JSON.parse(envelope.payload);
  const { now, acceptedGeneration, clientBuild, acceptedPayloadSha256 } = options;
  if (!Number.isFinite(now) || !Number.isSafeInteger(acceptedGeneration) || !Number.isSafeInteger(clientBuild) ||
      !object(release) || release.schemaVersion !== 2 || !Number.isSafeInteger(release.generation) ||
      release.generation < Math.max(1, acceptedGeneration) || !Number.isSafeInteger(release.minimumBuild) ||
      release.minimumBuild < 0 || release.minimumBuild > clientBuild || !Number.isFinite(release.issuedAt) ||
      release.issuedAt > now + 300000 || !Number.isFinite(release.expiresAt) || release.expiresAt <= now ||
      release.expiresAt <= release.issuedAt || !Array.isArray(release.resources) || release.resources.length > 512) throw new Error('invalid-release');
  if (release.generation === acceptedGeneration && createHash('sha256').update(envelope.payload).digest('hex') !== acceptedPayloadSha256) throw new Error('generation-conflict');
  const ids = new Set();
  for (const resource of release.resources) {
    if (!object(resource) || !identifier(resource.id) || ids.has(resource.id) ||
        typeof resource.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(resource.sha256) ||
        !Number.isSafeInteger(resource.bytes) || resource.bytes < 1 || resource.bytes > 512 * 1024 * 1024 ||
        resource.path !== `/v2/blobs/${resource.sha256}` || !identifier(resource.format) ||
        typeof resource.license !== 'string' || !resource.license.trim() || resource.license.length > 1024) throw new Error('invalid-resource');
    ids.add(resource.id);
  }
  return release;
}

export function verifyResourceBytes(bytes, resource) {
  if (!Buffer.isBuffer(bytes) || bytes.length !== resource.bytes ||
      createHash('sha256').update(bytes).digest('hex') !== resource.sha256) throw new Error('resource-integrity');
  return true;
}
