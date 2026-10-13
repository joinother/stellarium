// 星空文化行为控制器：负责当前星空文化的切换、详情请求与标签/视觉设置、模拟年时间跟随，
// 以及 Art 预览资源的探测、缩略图解码与预览解码。
// 依赖 CommandPort（文化/标签桥命令）、ImagePort（文件存在性、图片解码）、
// SkyCultureViewStore / SkyCultureSettingsStore（视图与设置状态）。
// 宿主 UI 上下文派生量（filesDir / pathToUri / 资源解析、标签下拉动画、锚点校正滚动）
// 与仍留宿主的详情加载器、共享请求序号、Art 渐进字段，均经 SkyCultureHostHooks 具名回注。
import hilog from '@ohos.hilog'
import { image } from '@kit.ImageKit'
import { I18n } from '../pages/I18n'
import { StellariumBridgeResponse, SkyCultureArtItem, SkyCultureItem } from '../pages/StellariumTypes'
import { SkyCultureVisualColors } from '../pages/MainWindowModels'
import { CommandPort } from '../bridge/CommandPort'
import { ImagePort } from '../bridge/MediaPort'
import { decodeLocalImage, releaseDecodedImage } from '../common/media/ImageDecoder'
import { isSafeSkyCultureArtPath } from '../common/derive/skycult'
import { SkyCultureViewStore } from '../state/SkyCultureViewStore'
import { SkyCultureSettingsStore } from '../state/SkyCultureSettingsStore'
import { BehaviorHostHooks } from './ControllerHooks'

export interface SkyCultureHostHooks extends BehaviorHostHooks {
  // 宿主保留的详情加载器与共享请求序号；序号单一持有者在宿主，控制器经此读写。
  loadSkyCultureDetails(): void
  skyCultureDetailsRequestId(): number
  nextSkyCultureDetailsRequestId(): number
  // 宿主控制器持有：读图层开关 + hasZodiac/hasLunarSystem。
  skyCultureActiveColorTarget(): string
  // 高频渐进字段本体留宿主（@State，LayersPanel @Prop 消费），控制器经 hooks 读写。
  skyCultureArtStates(): Record<string, string>
  setSkyCultureArtStates(next: Record<string, string>): void
  skyCultureArtThumbnailPixelMaps(): Record<string, image.PixelMap>
  setSkyCultureArtThumbnailPixelMaps(next: Record<string, image.PixelMap>): void
  // UI 上下文派生量（宿主 getUIContext()/fileUri/资源解析；控制器不 import NAPI/UI）。
  stellariumFilesDir(): string
  pathToUri(path: string): string
  resolveDetailMediaAsset(relativePath: string): Promise<string>
  // 前后台/面板路由谓词（宿主 applicationInForeground/activePanel/panelVisible/viewTab）。
  shouldFollowSkyCultureSimulationTime(): boolean
  // 标签下拉收起动画（宿主 getUIContext().animateTo）。
  animatePickerCollapse(action: () => void): void
  // 锚点校正滚动（宿主 isExpandedLayout / widePanelScroller / compactPanelScroller）。
  correctSkyCultureRowScroll(id: string, delta: number): void
}

export class SkyCultureController {
  private port: CommandPort
  private mediaPort: ImagePort
  private viewStore: SkyCultureViewStore
  private settingsStore: SkyCultureSettingsStore
  private hooks: SkyCultureHostHooks

  // —— 私有字段：高频/瞬态字段留控制器，不入被观察 store ——
  // 锚点校正（列表行测量 + 跨面板切换保持可见行）。
  private skyCultureRowY: Record<string, number> = {}
  private skyCultureAnchorId: string = ''
  private skyCultureAnchorY: number = 0
  private skyCultureAnchorRequestId: number = 0
  private skyCultureAnchorArmed: boolean = false
  // 时间跟随模拟年轮询（500ms）。
  private skyCultureTimeFollowTimer: number = 0
  private skyCultureTimeFollowRequestPending: boolean = false
  // Art 解码代际与渐进写入定时器。
  private skyCultureArtDecodeGeneration: number = 0
  private skyCultureArtThumbnailGeneration: number = 0
  private skyCultureArtDecodeTimer: number = 0
  private skyCultureArtStatusFlushTimer: number = 0
  private skyCultureArtPendingStatuses: Record<string, string> = {}

  constructor(
    port: CommandPort,
    mediaPort: ImagePort,
    viewStore: SkyCultureViewStore,
    settingsStore: SkyCultureSettingsStore,
    hooks: SkyCultureHostHooks
  ) {
    this.port = port
    this.mediaPort = mediaPort
    this.viewStore = viewStore
    this.settingsStore = settingsStore
    this.hooks = hooks
  }

  // ===== 选择 / 标签 / 视觉 / 时间跟随 =====

  // 切换文化 → 桥 → 成功清空详情/艺术态并重载详情。
  selectSkyCulture(id: string): void {
    if (id === this.viewStore.currentSkyCultureId || id === this.viewStore.pendingId) return
    this.captureSkyCultureAnchor(id)
    const requestId = this.hooks.nextSkyCultureDetailsRequestId()
    this.viewStore.pendingId = id
    this.viewStore.detailsLoading = true
    this.viewStore.detailError = ''
    this.port.requestInteractive('setSkyCulture', id, (r: StellariumBridgeResponse) => {
      if (requestId !== this.hooks.skyCultureDetailsRequestId()) return
      if (r.ok === true) {
        this.viewStore.currentSkyCultureId = r.cultureId !== undefined ? r.cultureId : id
        const selected = this.viewStore.skyCultureList.find((item: SkyCultureItem) => item.id === this.viewStore.currentSkyCultureId)
        this.viewStore.currentSkyCulture = r.culture !== undefined ? this.settingsStore.skyCultureDisplayName(this.viewStore.currentSkyCultureId, r.culture) : (selected !== undefined ? this.settingsStore.skyCultureDisplayName(selected.id, selected.name) : id)
        this.settingsStore.skyCultureLabelPickerOpen = ''
        this.settingsStore.skyCultureClassificationFilterOpen = false
        this.settingsStore.skyCultureRegionFilterOpen = false
        this.viewStore.narrationExpanded = false
        this.viewStore.descriptionExpanded = false
        this.viewStore.artExpanded = false
        this.closeSkyCultureArtPreview()
        this.settingsStore.skyCultureTerritoryExpanded = false
        this.settingsStore.skyCultureTerritoryMapExpanded = false
        this.settingsStore.skyCultureTerritoryMapPolygons = []
        this.settingsStore.skyCultureTerritoryMapError = ''
        this.hooks.loadSkyCultureDetails()
        return
      }
      this.viewStore.pendingId = ''
      this.viewStore.detailsLoading = false
      this.viewStore.detailError = '切换星空文化失败，请重试。'
      this.clearSkyCultureAnchor()
    }, () => {
      if (requestId !== this.hooks.skyCultureDetailsRequestId()) return
      this.viewStore.pendingId = ''
      this.viewStore.detailsLoading = false
      this.viewStore.detailError = '切换星空文化失败，请重试。'
      this.clearSkyCultureAnchor()
    })
  }

  // 按名称设置当前文化（搜索/快捷入口）。
  setSkyCulture(name: string): void {
    this.port.requestInteractive('setSkyCulture', name, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.hooks.flashHint(I18n.t('msg_apply_failed'))
        return
      }
      const culture = r.culture && r.culture.length > 0 ? r.culture : name
      this.viewStore.currentSkyCulture = culture
      this.hooks.flashHint(I18n.t('i0068').replace('%s', culture))
    })
  }

  // 记录切换前可见行 y，供切换后校正滚动。
  captureSkyCultureAnchor(id: string): void {
    const y = this.skyCultureRowY[id]
    if (y === undefined || !Number.isFinite(y)) {
      hilog.info(0x0000, 'StellariumArkUI', '[sky-culture-anchor] row not measured id=%{public}s', id)
      this.clearSkyCultureAnchor()
      return
    }
    this.skyCultureAnchorId = id
    this.skyCultureAnchorY = y
    this.skyCultureAnchorRequestId = 0
    this.skyCultureAnchorArmed = false
    hilog.info(0x0000, 'StellariumArkUI',
      '[sky-culture-anchor] captured id=%{public}s y=%{public}s', id, y.toFixed(1))
  }

  // 详情回包后武装锚点（等下一次行测量）。
  armSkyCultureAnchor(id: string, requestId: number): void {
    if (this.skyCultureAnchorId !== id) return
    this.skyCultureAnchorRequestId = requestId
    this.skyCultureAnchorArmed = true
  }

  clearSkyCultureAnchor(): void {
    this.skyCultureAnchorId = ''
    this.skyCultureAnchorY = 0
    this.skyCultureAnchorRequestId = 0
    this.skyCultureAnchorArmed = false
  }

  // 行测量回调；命中武装锚点时校正滚动。
  // 滚动本体（宿主 Scroller / 展开布局）经 hooks.correctSkyCultureRowScroll 回注。
  handleSkyCultureRowArea(id: string, area: Area): void {
    const y = Number.parseFloat(String(area.globalPosition.y))
    if (!Number.isFinite(y)) return
    this.skyCultureRowY[id] = y
    if (!this.skyCultureAnchorArmed || this.skyCultureAnchorId !== id ||
      this.skyCultureAnchorRequestId !== this.hooks.skyCultureDetailsRequestId()) return
    const delta = y - this.skyCultureAnchorY
    this.clearSkyCultureAnchor()
    if (Math.abs(delta) < 0.5) {
      hilog.info(0x0000, 'StellariumArkUI',
        '[sky-culture-anchor] stable id=%{public}s y=%{public}s', id, y.toFixed(1))
      return
    }
    this.hooks.correctSkyCultureRowScroll(id, delta)
  }

  // 名称组合位掩码开关。
  setSkyCultureStyleOption(target: string, optionIndex: number, enabled: boolean): void {
    const oldMask = target === 'screen' ? this.settingsStore.skyCultureScreenStyleMask : this.settingsStore.skyCultureInfoStyleMask
    const bit = 1 << optionIndex
    const nextMask = enabled ? (oldMask | bit) : (oldMask & ~bit)
    this.port.requestInteractive('setSkyCultureLabelStyle', target + '|' + this.settingsStore.skyCultureStyleValue(nextMask), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      const style = target === 'screen' ? r.screenLabelStyle : r.infoLabelStyle
      const actualMask = this.settingsStore.skyCultureStyleMaskFromBridge(style)
      if (target === 'screen') {
        this.settingsStore.skyCultureScreenStyleMask = actualMask
        this.settingsStore.skyCultureScreenLabelMode = this.settingsStore.skyCultureScreenLabelModeFromBridge(style)
      } else {
        this.settingsStore.skyCultureInfoStyleMask = actualMask
        this.settingsStore.skyCultureInfoLabelMode = this.settingsStore.skyCultureScreenLabelModeFromBridge(style)
      }
    })
  }

  setSkyCultureScreenLabelMode(mode: number): void {
    this.setSkyCultureLabelMode('screen', mode, (value: number) => { this.settingsStore.skyCultureScreenLabelMode = value })
  }

  setSkyCultureInfoLabelMode(mode: number): void {
    this.setSkyCultureLabelMode('info', mode, (value: number) => { this.settingsStore.skyCultureInfoLabelMode = value })
  }

  setSkyCultureZodiacLabelMode(mode: number): void {
    this.setSkyCultureLabelMode('zodiac', mode, (value: number) => { this.settingsStore.skyCultureZodiacLabelMode = value })
  }

  setSkyCultureLunarLabelMode(mode: number): void {
    this.setSkyCultureLabelMode('lunar', mode, (value: number) => { this.settingsStore.skyCultureLunarLabelMode = value })
  }

  setSkyCultureLabelModeForTarget(target: string, mode: number): void {
    if (target === 'screen') {
      this.setSkyCultureScreenLabelMode(mode)
    } else if (target === 'info') {
      this.setSkyCultureInfoLabelMode(mode)
    } else if (target === 'zodiac') {
      this.setSkyCultureZodiacLabelMode(mode)
    } else {
      this.setSkyCultureLunarLabelMode(mode)
    }
  }

  // 选档 + 收起下拉（动画经 hooks）。
  selectSkyCultureLabelMode(target: string, index: number): void {
    this.setSkyCultureLabelModeForTarget(target, index)
    this.hooks.animatePickerCollapse(() => {
      this.settingsStore.skyCultureLabelPickerOpen = ''
    })
  }

  // 桥写标签风格并回读实际档位。
  setSkyCultureLabelMode(target: string, mode: number, apply: (value: number) => void): void {
    const styles: string[] = ['Translated', 'Native', 'Pronounce', 'Translit', 'Modern']
    if (mode < 0 || mode >= styles.length) return
    apply(mode)
    this.port.requestInteractive('setSkyCultureLabelStyle', target + '|' + styles[mode], (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        const style = target === 'screen' ? r.screenLabelStyle
          : (target === 'info' ? r.infoLabelStyle
            : (target === 'zodiac' ? r.zodiacLabelStyle : r.lunarSystemLabelStyle))
        apply(this.settingsStore.skyCultureScreenLabelModeFromBridge(style))
      }
    })
  }

  setSkyCultureShortLabels(enabled: boolean): void {
    this.port.requestInteractive('setSkyCultureShortLabels', enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.settingsStore.skyCultureShortLabels = r.abbreviatedNames === true
    })
  }

  setSkyCultureCommonNames(enabled: boolean): void {
    this.port.requestInteractive('setSkyCultureCommonNames', enabled ? '1' : '0', (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.settingsStore.skyCultureOverrideCommonNames = r.overrideCommonNames === true
    })
  }

  setSkyCultureConstellationIsolation(enabled: boolean): void {
    this.port.requestInteractive('setConstellationFlag', 'isolateSelected|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      this.settingsStore.skyCultureIsolateSelected = enabled
      if (!enabled && this.settingsStore.skyCultureSinglePick) {
        this.setSkyCultureConstellationSinglePick(false)
      }
    })
  }

  setSkyCultureConstellationSinglePick(enabled: boolean): void {
    if (enabled && !this.settingsStore.skyCultureIsolateSelected) return
    this.port.requestInteractive('setConstellationFlag', 'constellationPick|' + (enabled ? '1' : '0'), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.settingsStore.skyCultureSinglePick = enabled
    })
  }

  applySkyCultureConstellationSelection(actionId: string, hint: string): void {
    this.port.requestInteractive('triggerAction', actionId, (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.hooks.flashHint(hint)
    })
  }

  setSkyCultureVisualSetting(setting: string, value: number): void {
    this.port.requestInteractive('setSkyCultureVisualSetting', setting + '|' + value.toFixed(2), (r: StellariumBridgeResponse) => {
      if (r.ok === true) this.settingsStore.applySkyCultureVisualSetting(setting, value)
    })
  }

  // 校验 #RRGGBB → 桥 → 写配色。
  // skyCultureActiveColorTarget（宿主控制器）经 hooks 回读。
  setSkyCultureVisualColor(setting: string, color: string): void {
    const normalized = color.trim().toUpperCase()
    if (!/^#[0-9A-F]{6}$/.test(normalized)) {
      this.hooks.flashHint('请输入 #RRGGBB 格式的颜色')
      return
    }
    this.port.requestInteractive('setSkyCultureVisualColor', setting + '|' + normalized, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) return
      const nextColor = r.color !== undefined ? r.color : normalized
      const colors = this.settingsStore.skyCultureVisualColors
      const updated: SkyCultureVisualColors = {
        constellationLines: setting === 'constellationLines' ? nextColor : colors.constellationLines,
        constellationLabels: setting === 'constellationLabels' ? nextColor : colors.constellationLabels,
        constellationBoundaries: setting === 'constellationBoundaries' ? nextColor : colors.constellationBoundaries,
        constellationHulls: setting === 'constellationHulls' ? nextColor : colors.constellationHulls,
        zodiac: setting === 'zodiac' ? nextColor : colors.zodiac,
        lunarSystem: setting === 'lunarSystem' ? nextColor : colors.lunarSystem,
        asterismLines: setting === 'asterismLines' ? nextColor : colors.asterismLines,
        asterismLabels: setting === 'asterismLabels' ? nextColor : colors.asterismLabels,
        rayHelpers: setting === 'rayHelpers' ? nextColor : colors.rayHelpers
      }
      this.settingsStore.skyCultureVisualColors = updated
      if (setting === this.hooks.skyCultureActiveColorTarget()) this.settingsStore.skyCultureColorInput = nextColor
    })
  }

  setCurrentSkyCultureAsDefault(): void {
    if (this.viewStore.currentSkyCultureId.length === 0 || this.settingsStore.skyCultureDefaultId === this.viewStore.currentSkyCultureId) return
    this.port.requestInteractive('setSkyCultureDefault', this.viewStore.currentSkyCultureId, (r: StellariumBridgeResponse) => {
      if (r.ok === true) {
        this.settingsStore.skyCultureDefaultId = r.defaultId !== undefined ? r.defaultId : this.viewStore.currentSkyCultureId
        this.hooks.flashHint('已设为默认星空文化')
      }
    })
  }

  // ===== 时间跟随模拟年（500ms 轮询） =====

  stopSkyCultureTimeFollowTimer(): void {
    if (this.skyCultureTimeFollowTimer !== 0) {
      clearInterval(this.skyCultureTimeFollowTimer)
      this.skyCultureTimeFollowTimer = 0
    }
    this.skyCultureTimeFollowRequestPending = false
  }

  syncSkyCultureTimeFollowTimer(): void {
    if (!this.hooks.shouldFollowSkyCultureSimulationTime()) {
      this.stopSkyCultureTimeFollowTimer()
      return
    }
    if (this.skyCultureTimeFollowTimer !== 0) return
    this.refreshSkyCultureSimulationYear()
    this.skyCultureTimeFollowTimer = setInterval(() => {
      this.refreshSkyCultureSimulationYear()
    }, 500)
  }

  refreshSkyCultureSimulationYear(force: boolean = false): void {
    if ((!force && !this.hooks.shouldFollowSkyCultureSimulationTime()) || this.skyCultureTimeFollowRequestPending) return
    this.skyCultureTimeFollowRequestPending = true
    this.port.requestInteractive('getSimulationTime', '', (r: StellariumBridgeResponse) => {
      this.skyCultureTimeFollowRequestPending = false
      if (r.ok !== true || r.year === undefined) return
      this.settingsStore.skyCultureSimulationYear = Math.round(r.year)
      if (force || this.hooks.shouldFollowSkyCultureSimulationTime()) {
        this.settingsStore.setSkyCultureTimeYear(this.settingsStore.skyCultureSimulationYear)
      }
    }, () => {
      this.skyCultureTimeFollowRequestPending = false
    })
  }

  // ===== Art 预览 =====

  // 安全校验 + 应用目录拼接 + 存在性判定。
  skyCultureArtFilePath(rawPath: string): string {
    if (!isSafeSkyCultureArtPath(rawPath)) return ''
    const path = this.hooks.stellariumFilesDir() + '/stellarium/' + rawPath
    return this.mediaPort.fileExists(path) ? path : ''
  }

  skyCultureArtUri(rawPath: string): string {
    const path = this.skyCultureArtFilePath(rawPath)
    return path.length > 0 ? this.hooks.pathToUri(path) : ''
  }

  // 作废在途预览解码（宿主 aboutToDisappear 时调用）。
  invalidateSkyCultureArtDecode(): void {
    this.skyCultureArtDecodeGeneration++
  }

  // 48ms 合批渐进写入宿主渐进字段。
  setSkyCultureArtStatus(rawPath: string, status: string): void {
    if (this.hooks.skyCultureArtStates()[rawPath] === status && this.skyCultureArtPendingStatuses[rawPath] === undefined) return
    if (this.skyCultureArtPendingStatuses[rawPath] === status) return
    this.skyCultureArtPendingStatuses[rawPath] = status
    if (this.skyCultureArtStatusFlushTimer !== 0) return
    this.skyCultureArtStatusFlushTimer = setTimeout(() => {
      this.skyCultureArtStatusFlushTimer = 0
      const pending = this.skyCultureArtPendingStatuses
      this.skyCultureArtPendingStatuses = {}
      const next: Record<string, string> = {}
      const current = this.hooks.skyCultureArtStates()
      for (const key of Object.keys(current)) next[key] = current[key]
      for (const key of Object.keys(pending)) next[key] = pending[key]
      this.hooks.setSkyCultureArtStates(next)
    }, 48) as number
  }

  // 作废代际 + 释放缩略图 + 清宿主渐进字段。
  clearSkyCultureArtThumbnails(): void {
    this.skyCultureArtThumbnailGeneration++
    if (this.skyCultureArtDecodeTimer !== 0) {
      clearTimeout(this.skyCultureArtDecodeTimer)
      this.skyCultureArtDecodeTimer = 0
    }
    if (this.skyCultureArtStatusFlushTimer !== 0) {
      clearTimeout(this.skyCultureArtStatusFlushTimer)
      this.skyCultureArtStatusFlushTimer = 0
    }
    this.skyCultureArtPendingStatuses = {}
    const oldMaps = this.hooks.skyCultureArtThumbnailPixelMaps()
    this.hooks.setSkyCultureArtThumbnailPixelMaps({})
    for (const rawPath of Object.keys(oldMaps)) {
      releaseDecodedImage(this.mediaPort, oldMaps[rawPath], 'sky-culture-art-thumbnail')
    }
  }

  decodeSkyCultureArtThumbnail(rawPath: string, requestId: number, resolvedPath: string = rawPath): void {
    if (this.hooks.skyCultureArtThumbnailPixelMaps()[rawPath] !== undefined) {
      return
    }
    const filePath = this.skyCultureArtFilePath(resolvedPath)
    if (filePath.length === 0) {
      return
    }
    const generation = this.skyCultureArtThumbnailGeneration
    decodeLocalImage(this.mediaPort, filePath, 'sky-culture-art-thumbnail', (pixelMap: image.PixelMap) => {
      if (requestId !== this.hooks.skyCultureDetailsRequestId() || generation !== this.skyCultureArtThumbnailGeneration ||
        this.viewStore.currentSkyCultureId.length === 0) {
        releaseDecodedImage(this.mediaPort, pixelMap, 'stale-sky-culture-art-thumbnail')
        return
      }
      const next: Record<string, image.PixelMap> = {}
      const current = this.hooks.skyCultureArtThumbnailPixelMaps()
      for (const key of Object.keys(current)) {
        next[key] = current[key]
      }
      next[rawPath] = pixelMap
      this.hooks.setSkyCultureArtThumbnailPixelMaps(next)
      this.setSkyCultureArtStatus(rawPath, 'ready')
      hilog.info(0x0000, 'StellariumArkUI', '[sky-culture-art] thumbnail ready path=%{public}s', rawPath)
    }, (err: Error) => {
      if (requestId !== this.hooks.skyCultureDetailsRequestId() || generation !== this.skyCultureArtThumbnailGeneration ||
        this.viewStore.currentSkyCultureId.length === 0) {
        return
      }
      this.setSkyCultureArtStatus(rawPath, 'decodeFailed')
      hilog.warn(0x0000, 'StellariumArkUI', '[sky-culture-art] thumbnail decode failed path=%{public}s error=%{public}s',
        rawPath, JSON.stringify(err))
    }, { width: 320, height: 320 })
  }

  // 分块解码可见缩略图 + 逐张补解缺失。
  prepareSkyCultureArtResources(items: Array<SkyCultureArtItem>, requestId: number): void {
    const initial: Record<string, string> = {}
    const missing: Array<string> = []
    const visiblePaths: string[] = []
    let ready = 0
    for (let index = 0; index < items.length; index++) {
      const art = items[index]
      if (this.skyCultureArtFilePath(art.rawPath).length > 0) {
        initial[art.rawPath] = 'ready'
        ready++
        if (index < 24) visiblePaths.push(art.rawPath)
      } else {
        initial[art.rawPath] = 'preparing'
        missing.push(art.rawPath)
      }
    }
    this.hooks.setSkyCultureArtStates(initial)
    let visibleIndex = 0
    const decodeVisibleChunk = (): void => {
      this.skyCultureArtDecodeTimer = 0
      if (requestId !== this.hooks.skyCultureDetailsRequestId() || this.viewStore.currentSkyCultureId.length === 0) return
      const chunkEnd = Math.min(visibleIndex + 4, visiblePaths.length)
      while (visibleIndex < chunkEnd) {
        this.decodeSkyCultureArtThumbnail(visiblePaths[visibleIndex], requestId)
        visibleIndex++
      }
      if (visibleIndex < visiblePaths.length) {
        this.skyCultureArtDecodeTimer = setTimeout(decodeVisibleChunk, 32) as number
      }
    }
    if (visiblePaths.length > 0) {
      this.skyCultureArtDecodeTimer = setTimeout(decodeVisibleChunk, 0) as number
    }
    hilog.info(0x0000, 'StellariumArkUI',
      '[sky-culture-art] probe total=%{public}s ready=%{public}s pending=%{public}s',
      items.length.toString(), ready.toString(), missing.length.toString())
    let nextIndex = 0
    const copyNext = (): void => {
      if (requestId !== this.hooks.skyCultureDetailsRequestId() || this.viewStore.currentSkyCultureId.length === 0) return
      if (nextIndex >= missing.length) {
        const states = this.hooks.skyCultureArtStates()
        let completed = 0
        let failed = 0
        for (const key of Object.keys(states)) {
          if (states[key] === 'ready') completed++
          if (states[key] === 'missing') failed++
        }
        hilog.info(0x0000, 'StellariumArkUI',
          '[sky-culture-art] preparation complete ready=%{public}s missing=%{public}s total=%{public}s',
          completed.toString(), failed.toString(), items.length.toString())
        return
      }
      const rawPath = missing[nextIndex++]
      this.hooks.resolveDetailMediaAsset(rawPath).then((resolvedPath: string) => {
        if (requestId !== this.hooks.skyCultureDetailsRequestId()) return
        const filePath = resolvedPath.length > 0 ? this.skyCultureArtFilePath(resolvedPath) : ''
        this.setSkyCultureArtStatus(rawPath, filePath.length > 0 ? 'ready' : 'missing')
        if (filePath.length > 0 && items.slice(0, 24).some((item: SkyCultureArtItem) => item.rawPath === rawPath)) {
          this.decodeSkyCultureArtThumbnail(rawPath, requestId, resolvedPath)
        }
        copyNext()
      }).catch((err: Error) => {
        if (requestId !== this.hooks.skyCultureDetailsRequestId()) return
        this.setSkyCultureArtStatus(rawPath, 'missing')
        hilog.warn(0x0000, 'StellariumArkUI',
          '[sky-culture-art] preparation failed path=%{public}s error=%{public}s', rawPath, JSON.stringify(err))
        copyNext()
      })
    }
    copyNext()
  }

  openSkyCultureArtPreview(art: SkyCultureArtItem): void {
    this.viewStore.artPreviewOpen = true
    this.skyCultureArtDecodeGeneration++
    const oldPixelMap = this.viewStore.artPreviewPixelMap
    this.viewStore.artPreviewPixelMap = undefined
    releaseDecodedImage(this.mediaPort, oldPixelMap, 'switch-sky-culture-art')
    this.viewStore.artPreviewRawPath = art.rawPath
    this.viewStore.artPreviewName = art.name !== undefined && art.name.length > 0 ? art.name : '星座绘图 ' + art.index
    this.viewStore.artPreviewFailed = false
    this.viewStore.artPreviewLoading = true
    this.viewStore.artPreviewPath = this.skyCultureArtUri(art.rawPath)
    this.resolveSkyCultureArtPreview(art.rawPath)
  }

  resolveSkyCultureArtPreview(rawPath: string): void {
    const current = this.skyCultureArtFilePath(rawPath)
    if (current.length > 0) {
      this.viewStore.artPreviewPath = this.hooks.pathToUri(current)
      this.viewStore.artPreviewLoading = true
      this.viewStore.artPreviewFailed = false
      this.setSkyCultureArtStatus(rawPath, 'ready')
      this.decodeSkyCultureArtPreview(current, rawPath)
      return
    }
    this.hooks.resolveDetailMediaAsset(rawPath).then((resolvedPath: string) => {
      if (!this.viewStore.artPreviewOpen || this.viewStore.artPreviewRawPath !== rawPath) return
      const filePath = resolvedPath.length > 0 ? this.skyCultureArtFilePath(resolvedPath) : ''
      this.viewStore.artPreviewPath = filePath.length > 0 ? this.hooks.pathToUri(filePath) : ''
      this.viewStore.artPreviewLoading = filePath.length > 0
      this.viewStore.artPreviewFailed = filePath.length === 0
      this.setSkyCultureArtStatus(rawPath, filePath.length > 0 ? 'ready' : 'missing')
      if (filePath.length > 0) {
        this.decodeSkyCultureArtPreview(filePath, rawPath)
      }
    }).catch((_err: Error) => {
      if (!this.viewStore.artPreviewOpen || this.viewStore.artPreviewRawPath !== rawPath) return
      this.viewStore.artPreviewPath = ''
      this.viewStore.artPreviewLoading = false
      this.viewStore.artPreviewFailed = true
      this.setSkyCultureArtStatus(rawPath, 'missing')
    })
  }

  closeSkyCultureArtPreview(): void {
    this.viewStore.artPreviewOpen = false
    this.skyCultureArtDecodeGeneration++
    const oldPixelMap = this.viewStore.artPreviewPixelMap
    this.viewStore.artPreviewPixelMap = undefined
    releaseDecodedImage(this.mediaPort, oldPixelMap, 'sky-culture-art')
    this.viewStore.artPreviewPath = ''
    this.viewStore.artPreviewName = ''
    this.viewStore.artPreviewRawPath = ''
    this.viewStore.artPreviewLoading = false
    this.viewStore.artPreviewFailed = false
  }

  onSkyCultureArtLoaded(): void {
    if (!this.viewStore.artPreviewOpen) return
    this.viewStore.artPreviewLoading = false
    this.viewStore.artPreviewFailed = false
    this.setSkyCultureArtStatus(this.viewStore.artPreviewRawPath, 'ready')
    hilog.info(0x0000, 'StellariumArkUI', '[sky-culture-art] preview loaded path=%{public}s', this.viewStore.artPreviewRawPath)
  }

  decodeSkyCultureArtPreview(filePath: string, rawPath: string): void {
    const generation = ++this.skyCultureArtDecodeGeneration
    decodeLocalImage(this.mediaPort, filePath, 'sky-culture-art', (pixelMap: image.PixelMap) => {
      if (!this.viewStore.artPreviewOpen || this.viewStore.artPreviewRawPath !== rawPath ||
        generation !== this.skyCultureArtDecodeGeneration) {
        releaseDecodedImage(this.mediaPort, pixelMap, 'stale-sky-culture-art')
        return
      }
      const oldPixelMap = this.viewStore.artPreviewPixelMap
      this.viewStore.artPreviewPixelMap = pixelMap
      releaseDecodedImage(this.mediaPort, oldPixelMap, 'previous-sky-culture-art')
      this.viewStore.artPreviewLoading = false
      this.viewStore.artPreviewFailed = false
      this.setSkyCultureArtStatus(rawPath, 'ready')
      hilog.info(0x0000, 'StellariumArkUI', '[sky-culture-art] pixel map ready path=%{public}s', rawPath)
    }, (err: Error) => {
      if (!this.viewStore.artPreviewOpen || this.viewStore.artPreviewRawPath !== rawPath ||
        generation !== this.skyCultureArtDecodeGeneration) {
        return
      }
      this.viewStore.artPreviewLoading = false
      this.viewStore.artPreviewFailed = true
      this.setSkyCultureArtStatus(rawPath, 'decodeFailed')
      hilog.error(0x0000, 'StellariumArkUI', '[sky-culture-art] pixel map decode failed path=%{public}s error=%{public}s',
        rawPath, JSON.stringify(err))
    })
  }

  onSkyCultureArtError(): void {
    if (!this.viewStore.artPreviewOpen) return
    this.viewStore.artPreviewLoading = false
    this.viewStore.artPreviewFailed = true
    this.setSkyCultureArtStatus(this.viewStore.artPreviewRawPath, 'decodeFailed')
    hilog.error(0x0000, 'StellariumArkUI', '[sky-culture-art] preview decode failed path=%{public}s', this.viewStore.artPreviewRawPath)
  }

  retrySkyCultureArtPreview(): void {
    this.viewStore.artPreviewFailed = false
    this.viewStore.artPreviewLoading = true
    const oldPixelMap = this.viewStore.artPreviewPixelMap
    this.viewStore.artPreviewPixelMap = undefined
    releaseDecodedImage(this.mediaPort, oldPixelMap, 'retry-sky-culture-art')
    this.viewStore.artPreviewPath = ''
    this.resolveSkyCultureArtPreview(this.viewStore.artPreviewRawPath)
  }
}
