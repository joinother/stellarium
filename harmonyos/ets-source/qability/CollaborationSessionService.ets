export interface CollaborationSessionOptions {
  includeLocation?: boolean
  ttlMinutes?: number
  copy?: boolean
}

export interface CollaborationSessionEnvelope {
  kind: string
  schemaVersion: number
  sessionId: string
  createdAt: string
  expiresAt: string
  source: Record<string, Object>
  privacy: Record<string, Object>
  state: Record<string, Object>
}

export interface CollaborationSessionPreview {
  ok: boolean
  kind?: string
  schemaVersion?: number
  sessionId?: string
  createdAt?: string
  expiresAt?: string
  expired?: boolean
  includesLocation?: boolean
  selected?: string
  fovDeg?: number
  jd?: number
  locationLabel?: string
  error?: string
}

const SESSION_KIND: string = 'stellarium.collaboration.session'
const CURRENT_SCHEMA: number = 2
const DEFAULT_TTL_MINUTES: number = 24 * 60
const MAX_TTL_MINUTES: number = 7 * 24 * 60

function record(value: Object | undefined): Record<string, Object> {
  if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('expected an object')
  }
  return value as Record<string, Object>
}

function finiteNumber(value: Object | undefined, minimum: number, maximum: number): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error('session number is out of range')
  }
  return value
}

function shortText(value: Object | undefined): string {
  if (typeof value !== 'string' || value.length > 256 || /[\u0000-\u001f]/.test(value)) {
    throw new Error('session text is invalid')
  }
  return value
}

function copyLocation(value: Object | undefined): Record<string, Object> | undefined {
  if (value === undefined) return undefined
  const input = record(value)
  const output: Record<string, Object> = {}
  output['name'] = shortText(input['name'])
  const planet = shortText(input['planetName'])
  if (!['Earth', 'Moon', 'Mars', 'Mercury', 'Venus', 'Jupiter', 'Saturn', 'Uranus', 'Neptune', 'Sun', 'Pluto'].includes(planet)) {
    throw new Error('unsupported observer planet')
  }
  output['planetName'] = planet
  output['latitude'] = finiteNumber(input['latitude'], -90, 90)
  output['longitude'] = finiteNumber(input['longitude'], -180, 180)
  output['altitude'] = finiteNumber(input['altitude'], -100000, 1000000)
  output['ianaTimeZone'] = shortText(input['ianaTimeZone'])
  return output
}

function copyState(nativeState: Record<string, Object>, includeLocation: boolean): Record<string, Object> {
  const state: Record<string, Object> = {}
  record(nativeState)
  const vector = nativeState['viewJ2000']
  if (!Array.isArray(vector) || vector.length !== 3) throw new Error('invalid view direction')
  const direction = (vector as Object[]).map((component: Object) => finiteNumber(component, -1, 1))
  const norm = Math.sqrt(direction.reduce((sum: number, component: number) => sum + component * component, 0))
  if (norm < 0.99 || norm > 1.01) throw new Error('view direction must be a unit vector')
  state['viewJ2000'] = direction.map((component: number) => component / norm)
  state['fovDeg'] = finiteNumber(nativeState['fovDeg'], 0.000001, 360)
  state['jd'] = finiteNumber(nativeState['jd'], -100000000, 100000000)
  state['selected'] = shortText(nativeState['selected'])
  const flags = record(nativeState['flags'])
  const safeFlags: Record<string, Object> = {}
  for (const key of ['flipHorz', 'flipVert']) {
    if (typeof flags[key] !== 'boolean') throw new Error('invalid display orientation')
    safeFlags[key] = flags[key]
  }
  state['flags'] = safeFlags
  if (includeLocation) {
    const location = copyLocation(nativeState['location'])
    if (location !== undefined) state['location'] = location
    // A panorama ID can identify a site, so it follows the location privacy
    // switch. Without it the receiver uses its local Earth memory/default.
    const landscapeID = nativeState['landscapeID']
    if (typeof landscapeID === 'string' && landscapeID.length > 0) {
      state['landscapeID'] = shortText(landscapeID)
    }
  }
  return state
}

function safeTtlMinutes(value: number | undefined): number {
  if (value === undefined || !Number.isFinite(value)) return DEFAULT_TTL_MINUTES
  return Math.min(MAX_TTL_MINUTES, Math.max(5, Math.round(value)))
}

export function createCollaborationSession(nativeJson: string, options: CollaborationSessionOptions = {}): CollaborationSessionEnvelope {
  record(options)
  if (options.includeLocation !== undefined && typeof options.includeLocation !== 'boolean') throw new Error('invalid location option')
  if (options.copy !== undefined && typeof options.copy !== 'boolean') throw new Error('invalid clipboard option')
  if (options.ttlMinutes !== undefined) finiteNumber(options.ttlMinutes, 5, MAX_TTL_MINUTES)
  const nativeState = JSON.parse(nativeJson) as Record<string, Object>
  if (nativeState['ok'] !== true) throw new Error('native session is not ready')
  const includeLocation = options.includeLocation === true
  const created = new Date()
  const expires = new Date(created.getTime() + safeTtlMinutes(options.ttlMinutes) * 60 * 1000)
  return {
    kind: SESSION_KIND,
    schemaVersion: CURRENT_SCHEMA,
    sessionId: `sky-${created.getTime().toString(36)}`,
    createdAt: created.toISOString(),
    expiresAt: expires.toISOString(),
    source: { platform: 'harmonyos', app: 'stellarium' },
    privacy: {
      locationIncluded: includeLocation,
      redactedFields: ['SN', 'UDID', 'account', 'password', 'telescopeHost', 'telescopePort']
    },
    state: copyState(nativeState, includeLocation)
  }
}

export function parseCollaborationSession(json: string): CollaborationSessionEnvelope {
  if (json.trim().length === 0 || json.length > 32768) throw new Error('session payload size is invalid')
  const value = record(JSON.parse(json) as Object)
  if (value['kind'] !== SESSION_KIND) throw new Error('unsupported collaboration session kind')
  if (value['schemaVersion'] !== CURRENT_SCHEMA) throw new Error('unsupported collaboration session version')
  if (typeof value['sessionId'] !== 'string' || typeof value['createdAt'] !== 'string' || typeof value['expiresAt'] !== 'string') {
    throw new Error('session envelope is incomplete')
  }
  const expiresAt = new Date(String(value['expiresAt']))
  const createdAt = new Date(String(value['createdAt']))
  if (!Number.isFinite(createdAt.getTime()) || createdAt.getTime() > Date.now() + 300000 ||
    expiresAt.getTime() <= createdAt.getTime() ||
    expiresAt.getTime() - createdAt.getTime() > MAX_TTL_MINUTES * 60000) throw new Error('session lifetime is invalid')
  if (!Number.isFinite(expiresAt.getTime())) throw new Error('session expiry is invalid')
  if (expiresAt.getTime() <= Date.now()) throw new Error('session has expired')
  const privacy = record(value['privacy'])
  if (typeof privacy['locationIncluded'] !== 'boolean') throw new Error('invalid location policy')
  const rawState = record(value['state'])
  if ((rawState['location'] !== undefined) !== (privacy['locationIncluded'] === true)) throw new Error('location policy mismatch')
  const session: CollaborationSessionEnvelope = {
    kind: String(value['kind']),
    schemaVersion: Number(value['schemaVersion']),
    sessionId: shortText(value['sessionId']),
    createdAt: String(value['createdAt']),
    expiresAt: String(value['expiresAt']),
    source: { platform: 'harmonyos', app: 'stellarium' },
    privacy: { locationIncluded: privacy['locationIncluded'] === true },
    state: copyState(rawState, privacy['locationIncluded'] === true)
  }
  return session
}

export function collaborationPreview(json: string): CollaborationSessionPreview {
  try {
    const session = parseCollaborationSession(json)
    const state = session.state
    const location = state['location'] as Record<string, Object> | undefined
    return {
      ok: true,
      kind: session.kind,
      schemaVersion: session.schemaVersion,
      sessionId: session.sessionId,
      createdAt: session.createdAt,
      expiresAt: session.expiresAt,
      expired: false,
      includesLocation: session.privacy['locationIncluded'] === true,
      selected: state['selected'] === undefined ? '' : String(state['selected']),
      fovDeg: state['fovDeg'] === undefined ? undefined : Number(state['fovDeg']),
      jd: state['jd'] === undefined ? undefined : Number(state['jd']),
      locationLabel: location === undefined || location['name'] === undefined ? '' : String(location['name'])
    }
  } catch (error) {
    return { ok: false, error: String(error) }
  }
}

export function collaborationNativeState(json: string): string {
  const session = parseCollaborationSession(json)
  return JSON.stringify(session.state)
}
