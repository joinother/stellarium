import { TonightPlanetRow } from '../pages/MainWindowModels'
import { StellariumBridgeResponse, SessionSnapshot, TonightEvents, ObserverPlanetItem } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { sessionSignature } from '../common/derive/actions'
import { planetZh } from '../common/derive/labels'
import { I18n } from '../pages/I18n'

// 观测星球选择列表的分组顺序：地球、月球、地球观测点固定前三；其后太阳与
// 八大行星按行星顺序分组（行星 → 卫星 → 全览点）；再后矮行星/小行星；最后彗星等小天体。
const OBSERVER_PLANET_TOP_ORDER: string[] = ['Earth', 'Moon', 'Earth Observer']
const OBSERVER_MAJOR_PLANET_ORDER: string[] = ['Mercury', 'Venus', 'Mars', 'Jupiter', 'Saturn', 'Uranus', 'Neptune']
const OBSERVER_DWARF_PLANET_TYPES: string[] = ['dwarfPlanet', 'plutino', 'cubewano', 'sdo', 'oco', 'sednoid']

interface ObserverPlanetSortEntry {
  name: string
  key: number
  originalIndex: number
}

// 宿主 → SessionToolStore 的注入。
// UI 提示、剪贴板写入、ToolsStore 的导入/导出文本框与 canUseDistributed 标志经具名回注
//（store 不 import UI / 他 store）。
export interface SessionToolHooks {
  flashHint(text: ResourceStr): void
  // 把会话 JSON 写剪贴板。
  copySessionJson(text: string, successHint: ResourceStr): void
  // 读取 ToolsStore 的会话导入文本框。
  sessionImportText(): string
  // 写 ToolsStore 的会话导出文本框。
  setSessionExportText(text: string): void
  // 把协作会话 JSON 落盘并拉起系统分享。
  shareSessionJson(json: string): void
  // 是否具备分布式续传能力。
  canUseDistributed(): boolean
  // 今晚天象拉取完成后回调宿主（复用同一份 TonightEvents 刷新桌面卡片，避免重复触发 getTonightEvents）。
  onTonightReady?: (tonight: TonightEvents) => void
}

// 观测/会话工具区块 store：持有观测星球切换、虚拟指星笔、手表陀螺仪模拟、今晚天象与会话
// 导出/应用/迁移的状态，由 panels/astro/SessionToolSections.ets 下的组件经 @ObjectLink 观察。
// 桥经 attachPort 注入 CommandPort，本 store 自持 loadPlanetList / refreshTonight；UI 提示、
// 剪贴板、ToolsStore 文本框与分布式能力经 SessionToolHooks 回注。
//
// 只放数据与纯计算，不 import UI / NAPI。native 桥动作、主题色与 watchLastSend（节流时间戳，
// 每次发送都写、不可观测）仍留宿主。
@Observed
export class SessionToolStore {
  // —— 观测星球（可站立星球切换）——
  observerPlanet: string = 'Earth'
  planetList: string[] = []
  observerPlanets: ObserverPlanetItem[] = []
  observerPlanetPending: boolean = false
  // 仅跨星球切换时置真（地球内 GPS / 地图选点不置真），供切换星球加载指示器使用。
  observerPlanetSwitching: boolean = false
  observerPlanetTarget: string = ''
  // 缓存 Select 下拉选项数组，避免每次状态刷新都重建 200+ MenuItem 导致 580ms UI 冻结。
  planetOptionsVersion: number = 0
  private cachedPlanetOptions: SelectOption[] = []
  private cachedPlanetOptionsKey: string = ''

  // —— 虚拟指星笔（多设备联动）——
  pointAlt: string = '45'
  pointAz: string = '180'
  pointResult: string = ''

  // —— 手表陀螺仪（发射端模拟）——
  watchAlt: number = 45
  watchAz: number = 180
  watchTracking: boolean = false
  watchResult: string = ''

  // —— 今晚天象 ——
  tonightDate: string = ''
  tonightMoon: string = ''
  tonightSun: string = ''
  tonightDark: string = ''
  tonightShowers: string[] = []
  tonightSats: string = ''
  tonightHint: string = ''
  // 点击跳转用：各卡片对应的事件时刻(JD)与锁定对象
  tonightMoonJd: number = 0
  tonightSunJd: number = 0
  tonightShowerJd: number = 0
  tonightPlanetRows: TonightPlanetRow[] = []
  // 今晚天象的缓存时间戳与在途标记。getTonightEvents 要跑太阳/月亮/行星共约 10 次
  // 升落搜索，是同步桥调用（JS 线程直接阻塞），所以只在数据过期后才重算，避免每次
  // 打开「位置」页都卡一下。
  private tonightFetchedAt: number = 0
  private tonightInFlight: boolean = false

  // —— 会话导出 / 应用 / 迁移 ——
  // sessionJson 与 sessionExportSig 供 sessionApply 500ms 后二次比对，验证无缝还原；
  // sessionHint 为续传区块即时提示文案。
  sessionJson: string = ''
  sessionExportSig: string = ''
  sessionHint: string = ''

  // —— 桥注入 ——
  private port: CommandPort | null = null
  // 本加载器无并发抑制需求，seq 预留未用。
  private seq: number = 0
  private onChanged: (() => void) | null = null
  // 会话导出/应用/迁移的宿主注入（UI 提示 / 剪贴板 / ToolsStore 文本框 / 分布式能力）。
  private hooks: SessionToolHooks | null = null

  // 宿主在 aboutToAppear 注入端口与发布回调；重复注入会覆盖旧值（幂等）。
  attachPort(port: CommandPort, onChanged: () => void): void {
    this.port = port
    this.onChanged = onChanged
  }

  attachHooks(hooks: SessionToolHooks): void {
    this.hooks = hooks
  }

  // 加载器统一守卫：未注入端口时静默跳过（不 crash，也不 import 桥）。
  private ensurePort(): CommandPort | null {
    return this.port
  }

  private notifyChanged(): void {
    if (this.onChanged !== null) {
      this.onChanged()
    }
  }

  loadPlanetList(): void {
    const port = this.ensurePort()
    if (port === null) {
      return
    }
    port.requestInteractive('getObserverPlanetList', '', (r: StellariumBridgeResponse) => {
      if (r.ok === true && r.planets) {
        // 必须先保存引擎返回的 planetList，sortObserverPlanets() 才能据此生成
        // 下拉框项；rebase 时这里漏掉赋值会让 Select 变空、无法选择天体。
        this.planetList = r.planets
        this.observerPlanets = r.observerPlanets ?? []
        this.sortObserverPlanets()
        this.cachedPlanetOptionsKey = ''
        this.planetOptionsVersion += 1
        this.notifyChanged()
      }
    })
  }

  // 选择列表按观测优先级重排；planetList 与 observerPlanets 必须保持同名同序，
  // Select 的 selected 索引与 onSelect 回调都直接使用 planetList 下标。
  private sortObserverPlanets(): void {
    const typeByName = new Map<string, string>()
    const parentByName = new Map<string, string>()
    const indexByName = new Map<string, number>()
    for (let i = 0; i < this.observerPlanets.length; i++) {
      const item = this.observerPlanets[i]
      typeByName.set(item.name, item.type ?? '')
      parentByName.set(item.name, item.parent ?? '')
      indexByName.set(item.name, i)
    }
    const entries: ObserverPlanetSortEntry[] = []
    for (let i = 0; i < this.planetList.length; i++) {
      const name = this.planetList[i]
      const type = typeByName.get(name) ?? ''
      const parent = parentByName.get(name) ?? ''
      entries.push({
        name: name,
        key: this.observerPlanetSortKey(name, type, parent, i, indexByName, typeByName),
        originalIndex: i
      })
    }
    entries.sort((left: ObserverPlanetSortEntry, right: ObserverPlanetSortEntry): number => {
      if (left.key !== right.key) return left.key - right.key
      return left.originalIndex - right.originalIndex
    })
    this.planetList = entries.map((entry: ObserverPlanetSortEntry): string => entry.name)
    const sortedPlanets: ObserverPlanetItem[] = []
    for (const entry of entries) {
      const item = this.observerPlanets.find((candidate: ObserverPlanetItem) => candidate.name === entry.name)
      if (item !== undefined) sortedPlanets.push(item)
    }
    // 防御：引擎若返回 planetList 之外的条目，仍保留其本地化名称/贴图。
    for (const item of this.observerPlanets) {
      if (sortedPlanets.indexOf(item) < 0) sortedPlanets.push(item)
    }
    this.observerPlanets = sortedPlanets
  }

  private observerPlanetSortKey(name: string, type: string, parent: string, originalIndex: number,
    indexByName: Map<string, number>, typeByName: Map<string, string>): number {
    const topRank = OBSERVER_PLANET_TOP_ORDER.indexOf(name)
    if (topRank >= 0) return topRank
    if (type === 'star') return 1000
    const majorRank = OBSERVER_MAJOR_PLANET_ORDER.indexOf(name)
    if (majorRank >= 0) return 1000 + (majorRank + 1) * 1000
    if (type === 'moon') {
      const parentMajorRank = OBSERVER_MAJOR_PLANET_ORDER.indexOf(parent)
      if (parentMajorRank >= 0) return 1000 + (parentMajorRank + 1) * 1000 + 10
    }
    if (type === 'observer') {
      if (name === 'Solar System Observer') return 9000
      if (name.endsWith(' Observer')) {
        const base = name.substring(0, name.length - 9)
        const observerMajorRank = OBSERVER_MAJOR_PLANET_ORDER.indexOf(base)
        if (observerMajorRank >= 0) return 1000 + (observerMajorRank + 1) * 1000 + 20
      }
    }
    if (OBSERVER_DWARF_PLANET_TYPES.indexOf(type) >= 0) {
      return 100000 + originalIndex * 10
    }
    if (type === 'moon') {
      // 矮行星/小行星的卫星紧随其母天体。
      const parentIndex = indexByName.get(parent)
      if (parentIndex !== undefined) {
        const parentType = typeByName.get(parent) ?? ''
        const base = OBSERVER_DWARF_PLANET_TYPES.indexOf(parentType) >= 0 ? 100000 : 200000
        return base + parentIndex * 10 + 1
      }
      return 200000 + originalIndex * 10 + 1
    }
    if (type === 'asteroid') return 200000 + originalIndex * 10
    const otherRank = type === 'comet' ? 0 : (type === 'interstellar' ? 1 : (type === 'artificial' ? 2 : 3))
    return 1000000 + otherRank * 10000 + originalIndex * 10
  }

  observerPlanetLabel(name: string): string {
    const translated = planetZh(name)
    if (translated !== name) return translated
    return this.observerPlanets.find((item: ObserverPlanetItem) => item.name === name)?.displayName ?? name
  }

  observerPlanetMapTexture(): string {
    const texture = this.observerPlanets.find((item: ObserverPlanetItem) => item.name === this.observerPlanet)?.mapTexture ?? ''
    return /^[a-zA-Z0-9_.-]+\.(png|jpg|jpeg)$/i.test(texture) ? texture : ''
  }

  // "Earth Observer", "Mars Observer", ... are fixed solar-system overview
  // viewpoints, not a point on a planet's surface. Editing their lat/lon is
  // meaningless, so the location editor is disabled for them.
  isObserverOverviewPoint(): boolean {
    const name = this.observerPlanet.trim().toLowerCase()
    return name.endsWith(' observer') || name.endsWith('全览点')
  }

  observerPlanetOptions(): SelectOption[] {
    const lang: string = typeof I18n.getLanguage === 'function' ? I18n.getLanguage() : 'zh_CN'
    const first: string = this.planetList.length > 0 ? this.planetList[0] : ''
    const last: string = this.planetList.length > 0 ? this.planetList[this.planetList.length - 1] : ''
    const key: string = `${lang}|${this.planetList.length}|${first}|${last}`
    if (this.cachedPlanetOptionsKey === key && this.cachedPlanetOptions.length === this.planetList.length) {
      return this.cachedPlanetOptions
    }
    this.cachedPlanetOptions = this.planetList.map((name: string): SelectOption => ({ value: this.observerPlanetLabel(name) }))
    this.cachedPlanetOptionsKey = key
    return this.cachedPlanetOptions
  }

  // 选中天体是否为当前观测星球。
  isObserverPlanetSelection(name: string): boolean {
    return name.trim().toLowerCase() === this.observerPlanet.trim().toLowerCase()
  }

  // ── 会话导出 / 应用 / 迁移：UI / 剪贴板 / ToolsStore / 分布式能力经 hooks 回注。

  // 会话摘要文案。
  sessionSummary(r: StellariumBridgeResponse): string {
    const locObj = r.location as Record<string, Object>
    const planet = (r.location && locObj['planetName'] !== undefined) ? String(locObj['planetName']) : 'Earth'
    const selection = r.selected ? I18n.format('m_session_selected', [r.selected]) : I18n.t('m_session_unselected')
    return I18n.format('m_session_summary', [(r.fovDeg ?? 0).toFixed(1), planetZh(planet), selection])
  }

  // 导出当前会话为 JSON 并复制到剪贴板。
  sessionExport(): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestWhenReady('getSessionState', '', (r: StellariumBridgeResponse) => {
      if (!r.ok) { this.sessionHint = I18n.t('m_session_export_failed'); return }
      const snap: SessionSnapshot = {
        schemaVersion: 1,
        exportedAt: new Date().toISOString(),
        viewJ2000: r.viewJ2000,
        fovDeg: r.fovDeg,
        jd: r.jd,
        location: r.location,
        selected: r.selected,
        flags: r.flags
      }
      this.sessionJson = JSON.stringify(snap, null, '  ')
      hooks.setSessionExportText(this.sessionJson)
      this.sessionExportSig = sessionSignature(r)
      this.sessionHint = I18n.t('m_session_exported') + ': ' + this.sessionSummary(r)
      hooks.copySessionJson(this.sessionJson, I18n.t('session_export_copied'))
    })
  }

  // 应用会话 JSON（优先用导入文本框，否则用上次导出的会话）。
  sessionApply(): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    const importedJson = hooks.sessionImportText().trim()
    const json = importedJson.length > 0 ? importedJson : this.sessionJson.trim()
    if (!json) { this.sessionHint = I18n.t('m_session_export_first'); return }
    port.requestWhenReady('applySessionState', json, (r2: StellariumBridgeResponse) => {
      if (!r2.ok) { this.sessionHint = I18n.t('m_apply_failed') + ': ' + (r2.error ?? I18n.t('m_unknown')); hooks.flashHint(I18n.t('m_apply_failed')); return }
      this.sessionHint = I18n.t('m_session_applied_syncing')
      hooks.flashHint(I18n.t('m_session_applied_syncing'))
      // 等一帧让 applySessionState 生效，再导出比对，验证无缝还原
      setTimeout(() => {
        port.requestWhenReady('getSessionState', '', (r3: StellariumBridgeResponse) => {
          if (!r3.ok) return
          const sig = sessionSignature(r3)
          if (sig === this.sessionExportSig) {
            this.sessionHint = I18n.t('m_session_exact')
            hooks.flashHint(I18n.t('m_session_exact'))
          } else {
            this.sessionHint = I18n.t('m_session_applied_done')
            hooks.flashHint(I18n.t('m_session_applied_done'))
          }
        })
      }, 500)
    })
  }

  // 生成协作会话信封（schema v2）并拉起系统分享；隐私门控由 QAbility 侧命令处理。
  sessionShare(): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestWhenReady('createCollaborationSession', '{"includeLocation":false}', (envelope: StellariumBridgeResponse) => {
      if (!envelope.ok || envelope.session === undefined) {
        this.sessionHint = I18n.t('m_session_export_failed')
        return
      }
      const json = JSON.stringify(envelope.session, null, '  ')
      this.sessionHint = I18n.t('session_share')
      hooks.shareSessionJson(json)
    })
  }

  // 跨设备续传（当前基础 SDK 无分布式软总线，给出本地能力说明）。
  sessionHandoff(): void {    const hooks = this.hooks
    if (hooks === null) {
      return
    }
    if (hooks.canUseDistributed()) {
      hooks.flashHint(I18n.t('msg_continuation_initiated'))
      this.sessionHint = I18n.t('m_continuation_migrating')
    } else {
      hooks.flashHint(I18n.t('m_continuation_basic_sdk'))
      this.sessionHint = I18n.t('m_continuation_basic_desc')
    }
  }

  // 观测点变化后让缓存的今晚天象失效；面板打开或用户手动刷新时再重算。
  invalidateTonight(): void {
    this.tonightFetchedAt = 0
  }

  // 「位置」面板今晚天象：桥拉取并本地化各卡片文案。
  // force=false（面板打开时的自动刷新）10 分钟内复用缓存；force=true（用户点「刷新」）强制重算。
  // silent=true 用于定位变化后的自动重算，不弹“已刷新”提示。
  refreshTonight(force: boolean = false, silent: boolean = false): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    if (this.tonightInFlight) {
      return
    }
    const TONIGHT_TTL_MS: number = 10 * 60 * 1000
    if (!force && this.tonightFetchedAt > 0 && Date.now() - this.tonightFetchedAt < TONIGHT_TTL_MS) {
      return
    }
    this.tonightInFlight = true
    // 位置面板仅需日月升落/行星/流星雨/卫星概况，走 lite 模式跳过 48h 时间轴、6星 SGP4 与 3 个月天象日历，避免阻塞星图渲染线程。
    port.requestWhenReady('getTonightEvents', 'lite', (r: StellariumBridgeResponse) => {
      this.tonightInFlight = false
      if (!r.ok || !r.tonight) { hooks.flashHint(I18n.t('msg_fetch_failed')); return }
      this.tonightFetchedAt = Date.now()
      const t = r.tonight as TonightEvents
      this.tonightDate = this.fmtIso(t.date ?? '')
      this.tonightMoon = I18n.t('tn_phase') + ': ' + (t.moon?.phaseName ?? I18n.t('m_unknown')) + ' (' + I18n.t('tn_illumination') + ' ' + Math.round(t.moon?.illumination ?? 0) + '% · ' + I18n.t('tn_moon_age') + ' ' + (t.moon?.age ?? 0).toFixed(1) + ' ' + I18n.t('tn_days') + ')\n'
        + '  ' + I18n.t('tn_rise') + ' ' + this.fmtIso(t.moon?.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(t.moon?.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(t.moon?.set ?? '')
      this.tonightSun = I18n.t('tn_rise') + ' ' + this.fmtIso(t.sun?.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(t.sun?.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(t.sun?.set ?? '')
      this.tonightDark = I18n.t('tn_astro_dusk') + ' ' + this.fmtIso(t.sun?.astroTwilightEnd ?? '') + ' → ' + I18n.t('tn_astro_dawn') + ' ' + this.fmtIso(t.sun?.astroTwilightStart ?? '')
        + (t.sun?.darkWindowHours !== undefined ? (' (' + I18n.t('tn_dark_hours') + ' ~' + t.sun.darkWindowHours.toFixed(1) + ' ' + I18n.t('tn_hours') + ')') : '')
      this.tonightPlanetRows = (t.planets ?? []).map((p): TonightPlanetRow => {
        const vis = p.visible === true ? I18n.t('tn_visible') : I18n.t('tn_below_horizon')
        return {
          name: p.name ?? (p.englishName ?? ''),
          line: I18n.t('tn_rise') + ' ' + this.fmtIso(p.rise ?? '') + ' · ' + I18n.t('tn_transit') + ' ' + this.fmtIso(p.transit ?? '') + ' · ' + I18n.t('tn_set') + ' ' + this.fmtIso(p.set ?? '')
            + ' · ' + I18n.t('tn_magnitude') + ' ' + (p.magnitude ?? 0).toFixed(1) + ' · ' + vis,
          jd: p.transitJd ?? 0,
          lock: p.englishName ?? (p.name ?? '')
        }
      })
      this.tonightShowers = (t.meteorShowers ?? []).map((s) => (s.name ?? '') + ': ZHR~' + (s.zhr ?? 0) + (s.status === 'confirmed' ? ' (' + I18n.t('tn_confirmed') + ')' : ' (' + I18n.t('tn_generic') + ')'))
      this.tonightSats = ((t.satellites?.enabled ?? false) ? (I18n.t('tn_loaded') + ' ' + (t.satellites?.count ?? 0) + ' ' + I18n.t('tn_sats_count')) : I18n.t('tn_not_enabled')) + ' (' + I18n.t('tn_transit_needs_data') + ')'
      // 点击跳转的时间基准
      this.tonightMoonJd = t.moon?.transitJd ?? 0
      this.tonightSunJd = t.sun?.astroTwilightEndJd ?? 0
      this.tonightShowerJd = (t.meteorShowers && t.meteorShowers.length > 0) ? (t.meteorShowers[0].primeJd ?? this.tonightSunJd) : this.tonightSunJd
      this.tonightHint = I18n.t('tn_updated') + ' · ' + this.fmtIso(t.date ?? '')
      if (hooks.onTonightReady !== undefined) {
        hooks.onTonightReady(t)
      }
      // 只有用户主动点「刷新」才弹提示；面板打开或定位变化后的自动刷新静默完成。
      if (force && !silent) hooks.flashHint('已刷新今晚天象 · 点击卡片可跳转')
    }, (): void => { this.tonightInFlight = false })
  }

  // ISO 字符串 → 'MM-DD HH:mm'。
  private fmtIso(iso: string): string {
    if (!iso || iso.length < 16) return '--'
    const parts = iso.split('T')
    const d = parts[0] ?? ''
    const t = parts[1] ?? ''
    return (d.length >= 10 ? d.slice(5) : d) + ' ' + (t.length >= 8 ? t.slice(0, 5) : t)
  }
}
