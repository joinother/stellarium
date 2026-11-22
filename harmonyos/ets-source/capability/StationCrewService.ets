// 空间站在轨航天员与国籍服务：
// 仅从自有阿里云境内只读静态镜像（https://skyinstrument.cn）拉取 /v1/manifest.json
// 与经 SHA-256 校验的 /v1/catalogs/spaceflight/people-in-space.json；
// 不直连任何第三方接口，不上传位置/设备信息；支持本地落盘缓存与离线内置快照兜底。

import { fileIo } from '@kit.CoreFileKit'
import { util } from '@kit.ArkTS'
import hilog from '@ohos.hilog'
import { hasCurrentPrivacyConsent } from '../qability/PrivacyConsent'
import { OFFLINE_APPGALLERY_BUILD } from '../common/types/MainWindowModels'
import {
  MirrorManifestClient,
  findManifestSource
} from './MirrorManifestClient'

export type StationCrewKey = '' | 'iss' | 'tiangong'
export type StationCrewSourceKind = 'mirror' | 'cache' | 'bundled'

export interface StationCrewMember {
  id: string
  name: string
  country: string
  flagCode: string
  agency: string
  position: string
  spacecraft: string
  iss: boolean
  launchedEpochSec: number
}

export interface StationCrewCountryCount {
  flagCode: string
  country: string
  count: number
}

export interface StationCrewSnapshot {
  stationKey: StationCrewKey
  issExpedition: number
  members: StationCrewMember[]
  countries: StationCrewCountryCount[]
  sourceKind: StationCrewSourceKind
  syncedAtMs: number
}

interface RawPeopleInSpacePerson {
  id?: number
  name?: string
  country?: string
  flag_code?: string
  agency?: string
  position?: string
  spacecraft?: string
  launched?: number
  iss?: boolean
}

interface RawPeopleInSpaceDocument {
  number?: number
  iss_expedition?: number
  people?: Array<RawPeopleInSpacePerson>
}

interface PersistedStationCrewCache {
  version: number
  sha256: string
  syncedAtMs: number
  issExpedition: number
  people: StationCrewMember[]
}

const ROOT_MANIFEST_SOURCE_ID: string = 'catalog.spaceflight.crew'
const CACHE_FILE_NAME: string = 'station_crew_cache_v1.json'
const AUTO_SYNC_INTERVAL_MS: number = 3 * 60 * 60 * 1000
const MAX_CREW_BYTES: number = 512 * 1024

// 离线兜底快照（同步自阿里云镜像上游基准 2026-11）：
// 即使离线或镜像首次同步前，国际空间站与中国空间站详情卡仍可准确展示当前在轨乘组与国籍。
const BUNDLED_ISS_EXPEDITION: number = 75
const BUNDLED_CREW_SNAPSHOT: StationCrewMember[] = [
  {
    id: 'bundled-1',
    name: 'Zhu Yangzhu',
    country: 'China',
    flagCode: 'cn',
    agency: 'CMSA',
    position: 'Commander',
    spacecraft: 'Shenzhou 23',
    iss: false,
    launchedEpochSec: 1779628116
  },
  {
    id: 'bundled-2',
    name: 'Zhang Zhiyuan',
    country: 'China',
    flagCode: 'cn',
    agency: 'CMSA',
    position: 'Pilot',
    spacecraft: 'Shenzhou 23',
    iss: false,
    launchedEpochSec: 1779628116
  },
  {
    id: 'bundled-3',
    name: 'Lai Ka-ying',
    country: 'China',
    flagCode: 'cn',
    agency: 'CMSA',
    position: 'Payload Specialist',
    spacecraft: 'Shenzhou 23',
    iss: false,
    launchedEpochSec: 1779628116
  },
  {
    id: 'bundled-4',
    name: 'Pyotr Dubrov',
    country: 'Russia',
    flagCode: 'ru',
    agency: 'Roscosmos',
    position: 'Commander',
    spacecraft: 'Soyuz MS-29',
    iss: true,
    launchedEpochSec: 1784040463
  },
  {
    id: 'bundled-5',
    name: 'Anna Kikina',
    country: 'Russia',
    flagCode: 'ru',
    agency: 'Roscosmos',
    position: 'Flight Engineer',
    spacecraft: 'Soyuz MS-29',
    iss: true,
    launchedEpochSec: 1784040463
  },
  {
    id: 'bundled-6',
    name: 'Anil Menon',
    country: 'United States',
    flagCode: 'us',
    agency: 'NASA',
    position: 'Flight Engineer',
    spacecraft: 'Soyuz MS-29',
    iss: true,
    launchedEpochSec: 1784040463
  },
  {
    id: 'bundled-7',
    name: 'Jessica Watkins',
    country: 'United States',
    flagCode: 'us',
    agency: 'NASA',
    position: 'Flight Engineer',
    spacecraft: 'Crew-13 Dragon',
    iss: true,
    launchedEpochSec: 1790867406
  },
  {
    id: 'bundled-8',
    name: 'Luke Delaney',
    country: 'United States',
    flagCode: 'us',
    agency: 'NASA',
    position: 'Flight Engineer',
    spacecraft: 'Crew-13 Dragon',
    iss: true,
    launchedEpochSec: 1790867406
  },
  {
    id: 'bundled-9',
    name: 'Joshua Kutryk',
    country: 'Canada',
    flagCode: 'ca',
    agency: 'CSA',
    position: 'Flight Engineer',
    spacecraft: 'Crew-13 Dragon',
    iss: true,
    launchedEpochSec: 1790867406
  },
  {
    id: 'bundled-10',
    name: 'Sergey Teteryatnikov',
    country: 'Russia',
    flagCode: 'ru',
    agency: 'Roscosmos',
    position: 'Flight Engineer',
    spacecraft: 'Crew-13 Dragon',
    iss: true,
    launchedEpochSec: 1790867406
  }
]

export function resolveStationCrewKey(
  catalogId: string,
  englishName: string,
  displayName: string,
  complexPrimaryId: string
): StationCrewKey {
  const cid = catalogId.trim()
  const primary = complexPrimaryId.trim()
  if (cid === '25544' || primary === '25544') return 'iss'
  if (cid === '48274' || cid === '53239' || cid === '54216' || primary === '48274') return 'tiangong'
  const hay = (englishName + ' ' + displayName).toLowerCase()
  if (hay.includes('iss (zarya)') || hay.includes('iss (nauka)') || hay.includes('国际空间站')) return 'iss'
  if (hay.includes('css (tianhe)') || hay.includes('css (wentian)') || hay.includes('css (mengtian)') ||
    hay.includes('天宫') || hay.includes('中国空间站') || hay.includes('天和核心舱')) {
    return 'tiangong'
  }
  return ''
}

export function flagEmojiForCountryCode(flagCode: string, countryName: string): string {
  let code = flagCode.trim().toUpperCase()
  if (code.length !== 2) {
    const c = countryName.trim().toLowerCase()
    if (c === 'china') code = 'CN'
    else if (c === 'united states' || c === 'usa') code = 'US'
    else if (c === 'russia' || c === 'russian federation') code = 'RU'
    else if (c === 'canada') code = 'CA'
    else if (c === 'japan') code = 'JP'
    else if (c === 'germany') code = 'DE'
    else if (c === 'france') code = 'FR'
    else if (c === 'italy') code = 'IT'
    else if (c === 'united kingdom' || c === 'uk') code = 'GB'
    else if (c === 'india') code = 'IN'
    else if (c === 'united arab emirates' || c === 'uae') code = 'AE'
    else if (c === 'saudi arabia') code = 'SA'
    else if (c === 'sweden') code = 'SE'
    else if (c === 'denmark') code = 'DK'
    else if (c === 'belarus') code = 'BY'
    else if (c === 'poland') code = 'PL'
    else if (c === 'hungary') code = 'HU'
    else if (c === 'pakistan') code = 'PK'
    else if (c === 'kazakhstan') code = 'KZ'
  }
  if (code.length === 2) {
    const a = code.charCodeAt(0)
    const b = code.charCodeAt(1)
    if (a >= 65 && a <= 90 && b >= 65 && b <= 90) {
      return String.fromCodePoint(0x1F1E6 + (a - 65), 0x1F1E6 + (b - 65))
    }
  }
  return '🛰️'
}

export function localizeCountryName(country: string, flagCode: string, isZh: boolean): string {
  if (!isZh) return country
  const code = flagCode.trim().toLowerCase()
  const key = country.trim().toLowerCase()
  if (code === 'cn' || key === 'china') return '中国'
  if (code === 'us' || key === 'united states' || key === 'usa') return '美国'
  if (code === 'ru' || key === 'russia' || key === 'russian federation') return '俄罗斯'
  if (code === 'ca' || key === 'canada') return '加拿大'
  if (code === 'jp' || key === 'japan') return '日本'
  if (code === 'de' || key === 'germany') return '德国'
  if (code === 'fr' || key === 'france') return '法国'
  if (code === 'it' || key === 'italy') return '意大利'
  if (code === 'gb' || key === 'united kingdom' || key === 'uk') return '英国'
  if (code === 'in' || key === 'india') return '印度'
  if (code === 'ae' || key === 'united arab emirates' || key === 'uae') return '阿联酋'
  if (code === 'sa' || key === 'saudi arabia') return '沙特阿拉伯'
  if (code === 'se' || key === 'sweden') return '瑞典'
  if (code === 'dk' || key === 'denmark') return '丹麦'
  if (code === 'by' || key === 'belarus') return '白俄罗斯'
  if (code === 'pl' || key === 'poland') return '波兰'
  if (code === 'hu' || key === 'hungary') return '匈牙利'
  if (code === 'pk' || key === 'pakistan') return '巴基斯坦'
  if (code === 'kz' || key === 'kazakhstan') return '哈萨克斯坦'
  if (code === 'tr' || key === 'turkey' || key === 'türkiye') return '土耳其'
  if (code === 'es' || key === 'spain') return '西班牙'
  if (code === 'nl' || key === 'netherlands') return '荷兰'
  if (code === 'be' || key === 'belgium') return '比利时'
  return country
}

export function localizeCrewPosition(position: string, isZh: boolean): string {
  const raw = position.trim()
  if (!isZh || raw.length === 0) return raw
  const low = raw.toLowerCase()
  if (low === 'commander') return '指令长'
  if (low === 'flight engineer') return '飞行工程师'
  if (low === 'pilot') return '驾驶员'
  if (low === 'payload specialist') return '载荷专家'
  if (low === 'mission specialist') return '任务专家'
  if (low === 'spaceflight participant') return '太空飞行参与者'
  return raw
}

export function localizeSpacecraftName(spacecraft: string, isZh: boolean): string {
  const raw = spacecraft.trim()
  if (!isZh || raw.length === 0) return raw
  const szMatch = /^Shenzhou\s+(\d+)$/i.exec(raw)
  if (szMatch !== null) return '神舟' + szMatch[1] + '号'
  const soyuzMatch = /^Soyuz\s+(.+)$/i.exec(raw)
  if (soyuzMatch !== null) return '联盟 ' + soyuzMatch[1]
  const crewDragonMatch = /^(Crew-\d+)\s+Dragon$/i.exec(raw)
  if (crewDragonMatch !== null) return '龙飞船 ' + crewDragonMatch[1]
  if (/^Dragon\s+/i.test(raw)) return '龙飞船 ' + raw.substring(7)
  if (raw.toLowerCase().includes('starliner')) return '星际客机 ' + raw
  return raw
}

export function localizeAstronautName(name: string, flagCode: string, isZh: boolean): string {
  const raw = name.trim()
  if (!isZh || flagCode.trim().toLowerCase() !== 'cn') return raw
  switch (raw.toLowerCase()) {
    case 'zhu yangzhu': return '朱杨柱'
    case 'ye guangfu': return '叶光富'
    case 'li cong': return '李聪'
    case 'li guangsu': return '李广苏'
    case 'cai xuzhe': return '蔡旭哲'
    case 'song lingdong': return '宋令东'
    case 'wang haoze': return '王浩泽'
    case 'chen dong': return '陈冬'
    case 'chen zhongrui': return '陈中瑞'
    case 'wang jie': return '王杰'
    case 'tang hongbo': return '汤洪波'
    case 'tang shengjie': return '唐胜杰'
    case 'jiang xinlin': return '江新林'
    case 'jing haipeng': return '景海鹏'
    case 'gui haichao': return '桂海潮'
    case 'fei junlong': return '费俊龙'
    case 'deng qingming': return '邓清明'
    case 'zhang lu': return '张陆'
    case 'liu yang': return '刘洋'
    case 'zhai zhigang': return '翟志刚'
    case 'wang yaping': return '王亚平'
    case 'nie haisheng': return '聂海胜'
    case 'liu boming': return '刘伯明'
    default: return raw
  }
}

function belongsToTiangong(member: StationCrewMember): boolean {
  if (member.iss) return false
  const sc = member.spacecraft.toLowerCase()
  const ag = member.agency.toLowerCase()
  return sc.includes('shenzhou') || sc.includes('tiangong') || ag === 'cmsa'
}

export class StationCrewService {
  private static instance: StationCrewService | null = null
  private cacheFilePath: string = ''
  private hydrated: boolean = false
  private syncing: boolean = false
  private sha256: string = ''
  private lastAttemptMs: number = 0
  private syncedAtMs: number = 0
  private sourceKind: StationCrewSourceKind = 'bundled'
  private issExpedition: number = BUNDLED_ISS_EXPEDITION
  private people: StationCrewMember[] = BUNDLED_CREW_SNAPSHOT.slice()

  static getInstance(): StationCrewService {
    if (StationCrewService.instance === null) {
      StationCrewService.instance = new StationCrewService()
    }
    return StationCrewService.instance
  }

  initDir(filesDir: string): void {
    const trimmed = filesDir.trim()
    if (trimmed.length === 0) return
    const nextPath = `${trimmed}/${CACHE_FILE_NAME}`
    if (this.hydrated && this.cacheFilePath === nextPath) return
    this.cacheFilePath = nextPath
    this.hydrated = true
    this.loadFromDiskSync()
  }

  isSyncing(): boolean {
    return this.syncing
  }

  getSnapshotForStation(stationKey: StationCrewKey): StationCrewSnapshot {
    if (stationKey === '') {
      return {
        stationKey: '',
        issExpedition: this.issExpedition,
        members: [],
        countries: [],
        sourceKind: this.sourceKind,
        syncedAtMs: this.syncedAtMs
      }
    }
    const members: StationCrewMember[] = []
    for (let i = 0; i < this.people.length; i++) {
      const m = this.people[i]
      if (stationKey === 'iss' && m.iss) {
        members.push(m)
      } else if (stationKey === 'tiangong' && belongsToTiangong(m)) {
        members.push(m)
      }
    }
    const countryMap: Map<string, StationCrewCountryCount> = new Map()
    for (let i = 0; i < members.length; i++) {
      const m = members[i]
      const key = (m.flagCode.length > 0 ? m.flagCode.toLowerCase() : m.country.toLowerCase())
      const existing = countryMap.get(key)
      if (existing !== undefined) {
        existing.count += 1
      } else {
        countryMap.set(key, {
          flagCode: m.flagCode,
          country: m.country,
          count: 1
        })
      }
    }
    const countries: StationCrewCountryCount[] = []
    countryMap.forEach((value: StationCrewCountryCount) => {
      countries.push(value)
    })
    countries.sort((a: StationCrewCountryCount, b: StationCrewCountryCount) => b.count - a.count)
    return {
      stationKey: stationKey,
      issExpedition: this.issExpedition,
      members: members,
      countries: countries,
      sourceKind: this.sourceKind,
      syncedAtMs: this.syncedAtMs
    }
  }

  async syncIfNeeded(force: boolean = false): Promise<boolean> {
    if (OFFLINE_APPGALLERY_BUILD || !hasCurrentPrivacyConsent()) {
      return false
    }
    if (this.syncing) return false
    const now = Date.now()
    if (!force && this.lastAttemptMs > 0 && (now - this.lastAttemptMs) < AUTO_SYNC_INTERVAL_MS && this.sourceKind === 'mirror') {
      return false
    }
    if (!force && this.lastAttemptMs > 0 && (now - this.lastAttemptMs) < 5 * 60 * 1000) {
      return false
    }
    this.syncing = true
    this.lastAttemptMs = now
    try {
      const client = MirrorManifestClient.getInstance()
      const manifest = await client.fetchRootManifest(force)
      const entry = findManifestSource(manifest, ROOT_MANIFEST_SOURCE_ID)
      if (entry === undefined || entry.available !== true || typeof entry.path !== 'string' || typeof entry.sha256 !== 'string') {
        return false
      }
      if (!force && this.sha256.length > 0 && entry.sha256.toLowerCase() === this.sha256.toLowerCase()) {
        this.sourceKind = 'mirror'
        return false
      }
      const artifact = await client.fetchVerifiedArtifact(
        entry.path,
        entry.sha256,
        entry.bytes,
        MAX_CREW_BYTES,
        '/v1/catalogs/'
      )
      if (!artifact.ok) {
        hilog.warn(0x0000, 'StellariumArkUI', '[station-crew] mirror verify failed kind=%{public}s code=%{public}d',
          artifact.errorKind, artifact.code)
        return false
      }
      const decoder = util.TextDecoder.create('utf-8')
      const parsed = this.parseDocument(decoder.decodeToString(artifact.bytes))
      if (parsed === undefined) {
        return false
      }
      this.people = parsed.people
      this.issExpedition = parsed.issExpedition
      this.sha256 = artifact.actualSha256
      this.syncedAtMs = Date.now()
      this.sourceKind = 'mirror'
      this.persistToDiskSync()
      hilog.info(0x0000, 'StellariumArkUI', '[station-crew] synced %{public}d astronauts from skyinstrument.cn',
        this.people.length)
      return true
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[station-crew] sync skipped: %{public}s', String(err))
      return false
    } finally {
      this.syncing = false
    }
  }

  private parseDocument(text: string): PersistedStationCrewCache | undefined {
    try {
      const doc = JSON.parse(text) as RawPeopleInSpaceDocument
      if (doc === null || typeof doc !== 'object' || !Array.isArray(doc.people)) {
        return undefined
      }
      const members: StationCrewMember[] = []
      for (let i = 0; i < doc.people.length && i < 200; i++) {
        const p = doc.people[i]
        if (p === null || p === undefined || typeof p !== 'object') continue
        const name = typeof p.name === 'string' ? p.name.trim() : ''
        const country = typeof p.country === 'string' ? p.country.trim() : ''
        const spacecraft = typeof p.spacecraft === 'string' ? p.spacecraft.trim() : ''
        if (name.length === 0 || country.length === 0 || spacecraft.length === 0 || typeof p.iss !== 'boolean') {
          continue
        }
        const idNum = typeof p.id === 'number' && Number.isFinite(p.id) ? p.id : (i + 1)
        members.push({
          id: 'crew-' + idNum.toString() + '-' + name,
          name: name,
          country: country,
          flagCode: typeof p.flag_code === 'string' ? p.flag_code.trim().toLowerCase() : '',
          agency: typeof p.agency === 'string' ? p.agency.trim() : '',
          position: typeof p.position === 'string' ? p.position.trim() : '',
          spacecraft: spacecraft,
          iss: p.iss,
          launchedEpochSec: typeof p.launched === 'number' && Number.isFinite(p.launched) ? p.launched : 0
        })
      }
      if (members.length === 0) return undefined
      const exp = typeof doc.iss_expedition === 'number' && Number.isFinite(doc.iss_expedition) && doc.iss_expedition > 0
        ? Math.round(doc.iss_expedition)
        : this.issExpedition
      return {
        version: 1,
        sha256: this.sha256,
        syncedAtMs: Date.now(),
        issExpedition: exp,
        people: members
      }
    } catch (_err) {
      return undefined
    }
  }

  private loadFromDiskSync(): void {
    if (this.cacheFilePath.length === 0) return
    try {
      if (!fileIo.accessSync(this.cacheFilePath)) return
      const stat = fileIo.statSync(this.cacheFilePath)
      if (stat.size <= 0 || stat.size > MAX_CREW_BYTES * 2) return
      const file = fileIo.openSync(this.cacheFilePath, fileIo.OpenMode.READ_ONLY)
      try {
        const buf = new ArrayBuffer(stat.size)
        const bytesRead = fileIo.readSync(file.fd, buf)
        if (bytesRead <= 0) return
        const decoder = util.TextDecoder.create('utf-8')
        const parsed = JSON.parse(decoder.decodeToString(new Uint8Array(buf, 0, bytesRead))) as PersistedStationCrewCache
        if (parsed === null || typeof parsed !== 'object' || parsed.version !== 1 || !Array.isArray(parsed.people) || parsed.people.length === 0) {
          return
        }
        this.people = parsed.people
        this.issExpedition = typeof parsed.issExpedition === 'number' && parsed.issExpedition > 0
          ? parsed.issExpedition
          : BUNDLED_ISS_EXPEDITION
        this.sha256 = typeof parsed.sha256 === 'string' ? parsed.sha256 : ''
        this.syncedAtMs = typeof parsed.syncedAtMs === 'number' && Number.isFinite(parsed.syncedAtMs) ? parsed.syncedAtMs : 0
        this.sourceKind = 'cache'
      } finally {
        fileIo.closeSync(file.fd)
      }
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[station-crew] cache load skipped: %{public}s', String(err))
    }
  }

  private persistToDiskSync(): void {
    if (this.cacheFilePath.length === 0) return
    try {
      const payload: PersistedStationCrewCache = {
        version: 1,
        sha256: this.sha256,
        syncedAtMs: this.syncedAtMs,
        issExpedition: this.issExpedition,
        people: this.people
      }
      const text = JSON.stringify(payload)
      const encoder = util.TextEncoder.create('utf-8')
      const bytes = encoder.encodeInto(text)
      const tmpPath = this.cacheFilePath + '.tmp'
      const file = fileIo.openSync(tmpPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY)
      try {
        fileIo.writeSync(file.fd, bytes.buffer)
      } finally {
        fileIo.closeSync(file.fd)
      }
      fileIo.renameSync(tmpPath, this.cacheFilePath)
    } catch (err) {
      hilog.warn(0x0000, 'StellariumArkUI', '[station-crew] cache persist failed: %{public}s', String(err))
    }
  }
}
