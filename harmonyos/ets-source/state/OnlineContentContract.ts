export interface ContentReference {
  kind: 'article' | 'event'
  id: string
  revision: number
}

export interface ContentNotice {
  schemaVersion: number
  messageId: string
  category: 'astronomy' | 'digest'
  issuedAt: number
  expiresAt: number
  reference: ContentReference
}

export interface ResourceHint {
  schemaVersion: number
  kind: 'resources-changed'
  generation: number
}

export interface RemoteSubscription {
  schemaVersion: number
  revision: number
  language: string
  timeZone: string
  astronomy: boolean
  digest: boolean
  quietStart: number
  quietEnd: number
  quietEnabled: boolean
}

export interface ContentSyncPort {
  refreshIndex(): Promise<boolean>
  openReference(reference: ContentReference): Promise<boolean>
}

export interface PushRegistrationPort {
  register(token: string, subscription: RemoteSubscription): Promise<boolean>
  update(subscription: RemoteSubscription): Promise<boolean>
  revoke(): Promise<boolean>
}

export function validContentReference(value: ContentReference): boolean {
  return value !== null && typeof value === 'object' && (value.kind === 'article' || value.kind === 'event') &&
    typeof value.id === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value.id) &&
    Number.isSafeInteger(value.revision) && value.revision > 0
}

export function validContentNotice(value: ContentNotice, now: number): boolean {
  return value !== null && typeof value === 'object' && value.schemaVersion === 1 && Number.isFinite(now) &&
    typeof value.messageId === 'string' && /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$/.test(value.messageId) &&
    (value.category === 'astronomy' || value.category === 'digest') &&
    Number.isFinite(value.issuedAt) && value.issuedAt <= now + 300000 &&
    Number.isFinite(value.expiresAt) && value.expiresAt > now && value.expiresAt > value.issuedAt &&
    value.expiresAt - value.issuedAt <= 7 * 86400000 && validContentReference(value.reference)
}

export function validResourceHint(value: ResourceHint): boolean {
  return value !== null && typeof value === 'object' && value.schemaVersion === 1 &&
    value.kind === 'resources-changed' && Number.isSafeInteger(value.generation) && value.generation > 0
}
