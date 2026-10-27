import { TonightPlanetRow } from '../pages/MainWindowModels'
import { StellariumBridgeResponse, SessionSnapshot, TonightEvents, ObserverPlanetItem } from '../pages/StellariumTypes'
import { CommandPort } from '../bridge/CommandPort'
import { sessionSignature } from '../common/derive/actions'
import { planetZh } from '../common/derive/labels'
import { I18n } from '../pages/I18n'

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
        this.planetList = r.planets
        this.observerPlanets = r.observerPlanets ?? []
        this.notifyChanged()
      }
    })
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

  observerPlanetOptions(): SelectOption[] {
    return this.planetList.map((name: string): SelectOption => ({ value: this.observerPlanetLabel(name) }))
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

  // 「位置」面板今晚天象：桥拉取并本地化各卡片文案。
  refreshTonight(): void {
    const port = this.ensurePort()
    const hooks = this.hooks
    if (port === null || hooks === null) {
      return
    }
    port.requestWhenReady('getTonightEvents', '', (r: StellariumBridgeResponse) => {
      if (!r.ok || !r.tonight) { hooks.flashHint(I18n.t('msg_fetch_failed')); return }
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
      hooks.flashHint('已刷新今晚天象 · 点击卡片可跳转')
    })
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
