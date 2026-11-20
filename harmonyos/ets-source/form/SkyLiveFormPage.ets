import { common } from '@kit.AbilityKit'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  CompactEventItem,
  CompactPlanetItem,
  OrreryPlanetState,
  UpcomingEventPage,
  clampOrreryDayOffset,
  computeDaylightDuration,
  computeGoldenHourClock,
  computeSolarArcProgress,
  estimateSolarTermZh,
  focusTargetForCard,
  formatCountdownZh,
  formatOrreryOffsetBadge,
  formatPlanetDisplayList,
  formatShortDateZh,
  isLightTextColor,
  nextCyclePlanet,
  offsetHoursToJd,
  parseHeliocentricPlanets,
  parseRemindedEventIds,
  parseUpcomingEvents,
  parseVisiblePlanets,
  projectSolarSystemOrrery,
  routePlanetForCard,
  routeTargetForCard,
  sliceUpcomingEventPage,
  solarStageFromAltitude
} from './AstronomyCardData'
import {
  CompactSatellitePass,
  compassDirectionZh,
  formatPassDurationZh,
  parseSatellitePasses,
  satelliteBrightnessGradeZh,
  satellitePassReminderId,
  satelliteVisualProfile
} from './SatelliteVisualRegistry'
import {
  readFormConfig,
  resolveCardDataForForm,
  writeFormConfig,
  writeFormTimeOffset
} from './FormStoreHelper'
import {
  CelestialOrbView,
  HorizonArcView,
  MiniPhaseStripView,
  PlanetVisibilityRow,
  SatellitePassArcView,
  SolarSystemOrreryStage,
  StarfieldLayer,
  eventAccentColor,
  eventBadgeText,
  fallbackPlanetRows,
  satelliteIconResource
} from './WidgetVisuals'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyLiveFormPage'

@Entry
@Component
struct SkyLiveFormPage {
  // Exact resting socket center inside the LiveForm window (initialized analytically, refined sub-pixel via onAreaChange)
  @State slotCenterX: number = 80
  @State slotCenterY: number = 80

  // Smooth decoupled transform state for the soaring 3D orb
  @State orbScale: number = 1.0
  @State orbDx: number = 0.0
  @State orbDy: number = 0.0
  @State orbTilt: number = 0.0

  // Seamless cross-dimming between resting card content (1.0 -> dim -> 1.0) and showcase overlay (0.0 -> 1.0 -> 0.0)
  @State restingContentOpacity: number = 1.0
  @State badgeOpacity: number = 0.0
  @State controlsOffsetY: number = 10.0

  // Shooting meteor state (celestial_events_card)
  @State meteorX: number = -120
  @State meteorY: number = 70
  @State meteorOpacity: number = 0.0

  // Reactive world state (supports live '↻ 换星' morph mid-overflow!)
  @State observerPlanet: string = 'Earth'
  @State observerPlanetName: string = '地球'
  @State companionName: string = '月球'
  @State companionEnglish: string = 'Moon'
  @State companionRole: string = 'moon'
  @State orbBody: string = 'moon'
  @State moonPhase: string = '今夜月相'
  @State moonIllumination: number = 72
  @State moonAge: number = 10
  @State moonSummary: string = '72% 照明'
  @State moonRise: string = '—'
  @State moonSet: string = '—'
  @State companionAlt: number = 28
  @State sunAlt: number = -18
  @State sunRise: string = '06:58'
  @State sunTransit: string = '11:58'
  @State sunSet: string = '16:59'
  @State solarStage: string = '白昼晴光'
  @State daylightDuration: string = '10h 01m'
  @State goldenHourText: string = '16:21'
  @State solarTermText: string = ''
  @State darkStart: string = '—'
  @State darkEnd: string = '—'
  @State observationSummary: string = '暗夜观测'
  @State planetNames: string = ''
  @State visiblePlanetsJson: string = '[]'
  @State upcomingEventsJson: string = '[]'
  @State remindedEventIds: string = '[]'
  @State nextEventTitle: string = ''
  @State nextEventCountdown: string = ''
  @State nextEventKind: string = 'sky'
  @State nextEventAt: number = 0
  @State skyHexTop: string = '#070E22'
  @State skyHexHorizon: string = '#172C52'
  @State dataStatus: string = '本地快照'
  @State updatedAt: string = '离线推演'
  @State cardThemeStyle: string = 'sky'
  @State cardLabelStyle: string = 'name'
  @State textColor: string = '#F5F9FF'
  @State timeOffsetHours: number = 0
  @State timePreviewLabel: string = ''
  @State heliocentricPlanetsJson: string = '[]'
  @State orreryDayOffset: number = 0
  @State orreryInnerOnly: boolean = false
  @State satellitePassesJson: string = '[]'
  @State satPassIndex: number = 0

  private uiContext: UIContext | undefined = undefined
  private liveFormContext: common.LiveFormExtensionContext | undefined = undefined
  private formId: string = ''
  private formKind: string = 'sky_window_card'
  private formRect: formInfo.Rect = { left: 0, top: 0, width: 160, height: 160 }
  private formBorderRadius: number = 22

  private animStarted: boolean = false
  private userSwappedPlanet: boolean = false
  private hasCardGlobal: boolean = false
  private hasRawSlot: boolean = false
  private cardGlobalX: number = 0
  private cardGlobalY: number = 0
  private rawSlotCenterX: number = 0
  private rawSlotCenterY: number = 0
  private startTimerId: number = -1
  private returnTimerId: number = -1
  private finishTimerId: number = -1
  private meteorFadeTimerId: number = -1

  private isWide(): boolean { return this.formRect.width >= 230 }
  private isTall(): boolean { return this.formRect.height >= 230 }
  private isBorderlessFloating(): boolean { return this.formKind === 'floating_orb_card' }

  private applySnapshotRecord(snap: Record<string, string>): void {
    this.observerPlanet = snap['observerPlanet'] ?? 'Earth'
    this.observerPlanetName = snap['observerPlanetName'] ?? '地球'
    this.companionName = snap['companionName'] ?? '月球'
    this.companionEnglish = snap['companionEnglish'] ?? ''
    this.companionRole = snap['companionRole'] ?? 'moon'
    this.orbBody = snap['orbBody'] ?? 'moon'
    this.moonPhase = snap['moonPhase'] ?? '今夜月相'
    const illum = Number(snap['moonIllumination'] ?? '72')
    this.moonIllumination = Number.isFinite(illum) ? illum : -1
    const age = Number(snap['moonAge'] ?? '10')
    this.moonAge = Number.isFinite(age) ? age : 10
    this.moonSummary = snap['moonSummary'] ?? ''
    this.moonRise = snap['moonRise'] ?? '—'
    this.moonSet = snap['moonSet'] ?? '—'
    const cAlt = Number(snap['companionAlt'] ?? '28')
    this.companionAlt = Number.isFinite(cAlt) ? cAlt : 28
    const sAlt = Number(snap['sunAlt'] ?? '-18')
    this.sunAlt = Number.isFinite(sAlt) ? sAlt : -18
    this.sunRise = snap['sunRise'] ?? '06:58'
    this.sunTransit = snap['sunTransit'] ?? '11:58'
    this.sunSet = snap['sunSet'] ?? '16:59'
    this.solarStage = snap['solarStage'] ?? solarStageFromAltitude(this.sunAlt)
    this.daylightDuration = snap['daylightDuration'] ?? computeDaylightDuration(this.sunRise, this.sunSet)
    this.goldenHourText = snap['goldenHourText'] ?? computeGoldenHourClock(this.sunSet)
    this.solarTermText = snap['solarTermText'] ?? estimateSolarTermZh(Date.now())
    this.darkStart = snap['darkStart'] ?? '—'
    this.darkEnd = snap['darkEnd'] ?? '—'
    this.observationSummary = snap['observationSummary'] ?? '暗夜观测'
    this.planetNames = snap['planetNames'] ?? ''
    this.visiblePlanetsJson = snap['visiblePlanetsJson'] ?? '[]'
    this.upcomingEventsJson = snap['upcomingEventsJson'] ?? '[]'
    this.remindedEventIds = snap['remindedEventIds'] ?? '[]'
    this.nextEventTitle = snap['nextEventTitle'] ?? ''
    this.nextEventCountdown = snap['nextEventCountdown'] ?? ''
    this.nextEventKind = snap['nextEventKind'] ?? 'sky'
    const evAt = Number(snap['nextEventAt'] ?? '0')
    this.nextEventAt = Number.isFinite(evAt) ? evAt : 0
    if (/^#[0-9A-Fa-f]{6}$/.test(snap['skyHexTop'] ?? '')) this.skyHexTop = snap['skyHexTop']
    if (/^#[0-9A-Fa-f]{6}$/.test(snap['skyHexHorizon'] ?? '')) this.skyHexHorizon = snap['skyHexHorizon']
    this.dataStatus = snap['dataStatus'] ?? '本地快照'
    this.updatedAt = snap['updatedAt'] ?? '离线推演'
    this.cardThemeStyle = snap['cardThemeStyle'] ?? 'sky'
    this.cardLabelStyle = snap['cardLabelStyle'] ?? 'name'
    if (/^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(snap['textColor'] ?? '')) this.textColor = snap['textColor']
    const offH = Number(snap['timeOffsetHours'] ?? '0')
    this.timeOffsetHours = Number.isFinite(offH) && offH > 0 ? Math.round(offH) : 0
    this.timePreviewLabel = snap['timePreviewLabel'] ?? ''
    this.heliocentricPlanetsJson = snap['heliocentricPlanetsJson'] ?? '[]'
    this.orreryDayOffset = clampOrreryDayOffset(Number(snap['orreryDayOffset'] ?? '0'))
    this.orreryInnerOnly = (snap['orreryInnerOnly'] ?? '0') === '1'
    this.satellitePassesJson = snap['satellitePassesJson'] ?? '[]'
    const spi = Math.floor(Number(snap['satPassIndex'] ?? '0'))
    this.satPassIndex = Number.isFinite(spi) && spi >= 0 ? spi : 0
  }

  private satPasses(): CompactSatellitePass[] {
    return parseSatellitePasses(this.satellitePassesJson, Date.now())
  }

  private activeSatPass(): CompactSatellitePass {
    const list = this.satPasses()
    const idx = list.length > 0 ? (this.satPassIndex % list.length) : 0
    return list[idx]
  }

  private satArcStageWidth(): number {
    if (!this.isWide() && !this.isTall()) return Math.max(124, Math.round(this.formRect.width - 18))
    if (!this.isTall()) return Math.max(134, Math.round(this.formRect.width * 0.44))
    return Math.max(250, Math.round(this.formRect.width - 26))
  }

  private satArcStageHeight(): number {
    if (!this.isWide() && !this.isTall()) return Math.max(76, Math.round(this.formRect.height - 62))
    if (!this.isTall()) return Math.max(114, Math.round(this.formRect.height - 20))
    return Math.max(106, Math.round(this.formRect.height - 186))
  }

  private satCraftRestingSize(): number {
    if (this.isTall()) return 52
    return this.isWide() ? 46 : 38
  }

  private satCraftApexY(h: number): number {
    const clampedAlt = Math.max(15, Math.min(90, this.activeSatPass().maxAlt))
    const norm = (clampedAlt - 10) / 80.0
    const horizonY = h - 22
    const topMargin = Math.max(16, Math.round(this.satCraftRestingSize() * 0.48))
    const maxAmp = Math.max(18, horizonY - topMargin)
    return horizonY - maxAmp * (0.42 + norm * 0.58)
  }

  private satMagBadge(pass: CompactSatellitePass): string {
    if (!Number.isFinite(pass.mag) || pass.mag > 15) return pass.visible ? '日照可见' : '地影'
    return (pass.mag > 0 ? '+' : '') + pass.mag.toFixed(1) + '等'
  }

  private satClockOnly(ms: number): string {
    if (!Number.isFinite(ms) || ms <= 0) return '—'
    const d = new Date(ms)
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
  }

  private orreryRestingWidth(): number {
    if (!this.isWide() && !this.isTall()) return Math.max(122, Math.round(this.formRect.width - 18))
    if (!this.isTall()) return Math.max(176, Math.round(this.formRect.width - 128))
    return Math.max(250, Math.round(this.formRect.width - 22))
  }

  private orreryRestingHeight(): number {
    if (!this.isWide() && !this.isTall()) return Math.max(76, Math.round(this.formRect.height - 62))
    if (!this.isTall()) return Math.max(118, Math.round(this.formRect.height - 18))
    return Math.max(150, Math.round(this.formRect.height - 122))
  }

  private orreryPeakWidth(): number {
    return Math.round(this.orreryRestingWidth() * 1.24)
  }

  private orreryPeakHeight(): number {
    return Math.round(this.orreryRestingHeight() * 1.24)
  }

  private orreryTiltDeg(): number {
    if (this.isTall()) return 50
    return this.isWide() ? 55 : 56
  }

  private orreryShowLabels(): boolean {
    if (this.isTall()) return true
    if (this.isWide()) return this.orreryInnerOnly
    return false
  }

  private orreryEpochLabel(): string {
    return formatOrreryOffsetBadge(this.orreryDayOffset, Date.now() + this.orreryDayOffset * 86400000)
  }

  private orrerySummaryText(): string {
    const planets = parseHeliocentricPlanets(this.heliocentricPlanetsJson, Date.now(), this.orreryDayOffset)
    return projectSolarSystemOrrery(planets, 220, 110, this.orreryInnerOnly, 55).summaryLine
  }

  private orreryFeaturedTelemetry(): OrreryPlanetState[] {
    const all = parseHeliocentricPlanets(this.heliocentricPlanetsJson, Date.now(), this.orreryDayOffset)
    if (this.orreryInnerOnly) return all.filter((p: OrreryPlanetState) => p.isInner).slice(0, 4)
    const keys: string[] = ['Earth', 'Mars', 'Jupiter', 'Saturn']
    const out: OrreryPlanetState[] = []
    for (let i = 0; i < all.length; i++) {
      if (keys.includes(all[i].id)) out.push(all[i])
    }
    return out.slice(0, 4)
  }

  // Exact resting orb diameter in vp (1:1 match with the inactive card!)
  private restingOrbSize(): number {
    if (this.formKind === 'satellite_pass_card') return this.satCraftRestingSize()
    if (this.formKind === 'floating_orb_card') return 110
    if (this.formKind === 'solar_arc_card') return this.isWide() ? 86 : 66
    if (this.formKind === 'companion_arc_card') return this.isWide() ? 86 : 64
    if (this.formKind === 'celestial_events_card') return this.isTall() ? 46 : 34
    // sky_window_card
    if (!this.isWide() && !this.isTall()) return 56
    return this.isTall() ? 82 : 72
  }

  // Native-resolution peak orb diameter in vp (orb renders at peakSize and scales down to startScale at rest -> zero upscaling blur!)
  private peakOrbSize(): number {
    if (this.formKind === 'satellite_pass_card') return this.isTall() ? 114 : 98
    if (this.formKind === 'floating_orb_card') return 130
    if (this.formKind === 'solar_arc_card') return this.isWide() ? 114 : 108
    if (this.formKind === 'companion_arc_card') return this.isWide() ? 112 : 106
    if (this.formKind === 'celestial_events_card') return this.isTall() ? 124 : 96
    // sky_window_card
    if (!this.isWide() && !this.isTall()) return 104
    return this.isTall() ? 128 : 112
  }

  private startOrbScale(): number {
    if (this.formKind === 'solar_system_card') {
      return this.orreryRestingWidth() / Math.max(1, this.orreryPeakWidth())
    }
    return this.restingOrbSize() / this.peakOrbSize()
  }

  private initAnalyticalRestingSocket(): void {
    const l = this.formRect.left
    const t = this.formRect.top
    const w = this.formRect.width
    const h = this.formRect.height
    const s = this.restingOrbSize()

    if (this.formKind === 'solar_system_card') {
      if (!this.isWide() && !this.isTall()) {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + h * 0.5
      } else if (!this.isTall()) {
        this.slotCenterX = l + 10 + (w - 136) * 0.5
        this.slotCenterY = t + h * 0.5
      } else {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + 46 + (h - 122) * 0.5
      }
      this.orbScale = this.startOrbScale()
      return
    }

    if (this.formKind === 'satellite_pass_card') {
      const stageW = this.satArcStageWidth()
      const stageH = this.satArcStageHeight()
      const ay = this.satCraftApexY(stageH)
      if (!this.isWide() && !this.isTall()) {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + 31 + ay
      } else if (!this.isTall()) {
        this.slotCenterX = l + 10 + stageW * 0.5
        this.slotCenterY = t + 10 + ay
      } else {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + 50 + ay
      }
      this.orbScale = this.startOrbScale()
      return
    }

    if (this.formKind === 'floating_orb_card') {
      this.slotCenterX = l + w * 0.5
      this.slotCenterY = t + (h - 132) * 0.5 + 56
    } else if (this.formKind === 'solar_arc_card') {
      if (this.isWide()) {
        this.slotCenterX = l + 13 + 48
        this.slotCenterY = t + (h - 104) * 0.5 + s * 0.5
      } else {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + 40.5 + s * 0.5
      }
    } else if (this.formKind === 'companion_arc_card') {
      if (this.isWide()) {
        this.slotCenterX = l + 14 + 50
        this.slotCenterY = t + (h - 104) * 0.5 + s * 0.5
      } else {
        this.slotCenterX = l + w * 0.5
        this.slotCenterY = t + 40.5 + s * 0.5
      }
    } else if (this.formKind === 'celestial_events_card') {
      this.slotCenterX = l + w - 14 - s * 0.5
      this.slotCenterY = t + 14 + s * 0.5
    } else {
      // sky_window_card
      if (!this.isWide() && !this.isTall()) {
        this.slotCenterX = l + w - 12 - s * 0.5
        this.slotCenterY = t + h * 0.5
      } else if (this.isTall()) {
        this.slotCenterX = l + w - 14 - s * 0.5
        this.slotCenterY = t + 13 + s * 0.5
      } else {
        this.slotCenterX = l + w - 14 - s * 0.5
        this.slotCenterY = t + (h - 16) * 0.5
      }
    }
    this.orbScale = this.startOrbScale()
  }

  private syncMeasuredSlot(): void {
    if (!this.hasCardGlobal || !this.hasRawSlot || this.animStarted) return
    const inCardX = this.rawSlotCenterX - this.cardGlobalX
    const inCardY = this.rawSlotCenterY - this.cardGlobalY
    if (inCardX >= 0 && inCardX <= this.formRect.width &&
      inCardY >= 0 && inCardY <= this.formRect.height) {
      this.slotCenterX = this.formRect.left + inCardX
      this.slotCenterY = this.formRect.top + inCardY
    }
  }

  private captureCardArea(newArea: Area): void {
    const gx = Number(newArea.globalPosition.x)
    const gy = Number(newArea.globalPosition.y)
    if (Number.isFinite(gx) && Number.isFinite(gy)) {
      this.cardGlobalX = gx
      this.cardGlobalY = gy
      this.hasCardGlobal = true
      this.syncMeasuredSlot()
    }
  }

  private captureSlotArea(newArea: Area): void {
    const gx = Number(newArea.globalPosition.x)
    const gy = Number(newArea.globalPosition.y)
    const aw = Number(newArea.width)
    const ah = Number(newArea.height)
    if (Number.isFinite(gx) && Number.isFinite(gy) && aw > 0 && ah > 0) {
      this.rawSlotCenterX = gx + aw * 0.5
      this.rawSlotCenterY = gy + ah * 0.5
      this.hasRawSlot = true
      this.syncMeasuredSlot()
    }
  }

  aboutToAppear(): void {
    this.uiContext = this.getUIContext()
    const storage = this.uiContext?.getSharedLocalStorage()
    if (storage === undefined) return
    this.liveFormContext = storage.get<common.LiveFormExtensionContext>('context')
    this.formId = storage.get<string>('formId') ?? ''
    this.formKind = storage.get<string>('formKind') ?? 'sky_window_card'
    const rect = storage.get<formInfo.Rect>('formRect')
    if (rect !== undefined) this.formRect = rect
    const br = storage.get<number>('borderRadius')
    if (br !== undefined && br > 0) this.formBorderRadius = br
    const raw = storage.get<string>('snapshotJson') ?? ''
    if (raw.length > 0) {
      try {
        const snap = JSON.parse(raw) as Record<string, string>
        this.applySnapshotRecord(snap)
      } catch (_) {
      }
    }
    this.initAnalyticalRestingSocket()
  }

  aboutToDisappear(): void {
    if (this.startTimerId >= 0) clearTimeout(this.startTimerId)
    if (this.returnTimerId >= 0) clearTimeout(this.returnTimerId)
    if (this.finishTimerId >= 0) clearTimeout(this.finishTimerId)
    if (this.meteorFadeTimerId >= 0) clearTimeout(this.meteorFadeTimerId)
  }

  // Peak orb center guaranteed to break visibly above formRect.top while keeping top edge strictly >= 8vp (ZERO clipping!)
  private peakCenterX(): number {
    return this.formRect.left + this.formRect.width * 0.5
  }

  private peakCenterY(): number {
    if (this.formKind === 'solar_system_card') {
      const halfH = this.orreryPeakHeight() * 0.5
      const minSafeCenterY = 8 + halfH
      const desired = this.formRect.top + Math.round(halfH * 0.42)
      return Math.max(minSafeCenterY, desired)
    }
    const half = this.peakOrbSize() * 0.5
    const minSafeCenterY = 8 + half
    if (this.isBorderlessFloating()) {
      // Lift cleanly above card top while leaving generous room below for telemetry badge + 2 pill buttons
      const desired = this.slotCenterY - Math.round(this.formRect.height * 0.22)
      return Math.max(minSafeCenterY, desired)
    }
    // Framed cards: break cleanly across the top border of the card
    const desired = this.formRect.top + Math.round(half * 0.42)
    return Math.max(minSafeCenterY, desired)
  }

  private scheduleOverflowShowcase(): void {
    if (this.animStarted) return
    // Wait 240ms after onAppear so RenderService commits our 100% pixel-identical resting frame
    // and SceneBoard finishes revealing the LiveForm surface BEFORE animateTo begins (prevents entry jump!).
    this.startTimerId = setTimeout(() => {
      this.runOverflowShowcase()
    }, 240)
  }

  private runOverflowShowcase(): void {
    if (this.animStarted) return
    this.animStarted = true

    const dx = this.peakCenterX() - this.slotCenterX
    const dy = this.peakCenterY() - this.slotCenterY
    const restScale = this.startOrbScale()
    const dimTarget = this.isBorderlessFloating() ? 0.0 : 0.24
    hilog.info(DOMAIN, TAG, 'slotMeasured kind=%{public}s slot=(%{public}d,%{public}d) peak=(%{public}d,%{public}d) measured=%{public}s',
      this.formKind, Math.round(this.slotCenterX), Math.round(this.slotCenterY),
      Math.round(this.peakCenterX()), Math.round(this.peakCenterY()),
      String(this.hasCardGlobal && this.hasRawSlot))

    // Phase 1 (240ms -> 880ms): Symmetric EaseInOut lift from velocity 0 out of exact resting socket -> top-center peak
    this.uiContext?.animateTo({ duration: 640, curve: Curve.EaseInOut }, () => {
      this.orbDx = dx
      this.orbDy = dy
      this.orbScale = 1.0
      this.orbTilt = this.formKind === 'solar_system_card' ? 0 : -4
      this.restingContentOpacity = dimTarget
      this.badgeOpacity = 1.0
      this.controlsOffsetY = 0
    })

    // Shooting meteor streak on celestial_events_card
    if (this.formKind === 'celestial_events_card') {
      this.meteorX = -this.formRect.width * 0.10
      this.meteorY = this.formRect.height * 0.36
      this.meteorOpacity = 0.0
      this.uiContext?.animateTo({ duration: 220, curve: Curve.EaseIn }, () => {
        this.meteorOpacity = 1.0
      })
      this.uiContext?.animateTo({ duration: 1050, curve: Curve.EaseInOut }, () => {
        this.meteorX = this.formRect.width * 0.88
        this.meteorY = -Math.max(8, Math.round(this.formRect.top * 0.48))
      })
      this.meteorFadeTimerId = setTimeout(() => {
        this.uiContext?.animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
          this.meteorOpacity = 0.0
        })
      }, 980)
    }

    // Phase 3 (2170ms -> 2790ms): Smooth return ALL THE WAY back into exact resting socket + restore resting card UI
    this.returnTimerId = setTimeout(() => {
      this.uiContext?.animateTo({ duration: 620, curve: Curve.EaseInOut }, () => {
        this.orbDx = 0
        this.orbDy = 0
        this.orbScale = restScale
        this.orbTilt = 0
        this.restingContentOpacity = 1.0
        this.badgeOpacity = 0.0
        this.controlsOffsetY = 10
        this.meteorOpacity = 0.0
      })
    }, 1930)

    // Phase 4 (3100ms total): After resting pixel-identically for ~310ms, hand back cleanly!
    this.finishTimerId = setTimeout(() => {
      if (!this.userSwappedPlanet && this.formId.length > 0) {
        formProvider.cancelOverflow(this.formId).catch(() => {})
      }
    }, 2860)
  }

  private cycleFloatingPlanetInPlace(): void {
    if (this.liveFormContext === undefined || this.formId.length === 0) return
    this.userSwappedPlanet = true
    const cfg = readFormConfig(this.liveFormContext, this.formId)
    const nextPlanet = nextCyclePlanet(this.observerPlanet)
    cfg.planetMode = nextPlanet
    writeFormConfig(this.liveFormContext, this.formId, cfg)
    writeFormTimeOffset(this.liveFormContext, this.formId, 0)
    const nextData = resolveCardDataForForm(this.liveFormContext, this.formId, Date.now())

    this.uiContext?.animateTo({ duration: 240, curve: Curve.FastOutSlowIn }, () => {
      this.applySnapshotRecord(nextData)
      this.orbTilt = this.orbTilt === -4 ? 5 : -4
    })

    const binding = formBindingData.createFormBindingData(nextData)
    formProvider.updateForm(this.formId, binding).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'cycleFloatingPlanet updateForm failed: code=%{public}d', error.code)
    })
  }

  private launchAppDirect(): void {
    if (this.liveFormContext === undefined) return
    if (this.formKind === 'satellite_pass_card') {
      const p = this.activeSatPass()
      try {
        this.liveFormContext.startAbilityByLiveForm({
          bundleName: 'com.joinother.skyinstrument',
          abilityName: 'QAbility',
          parameters: {
            panel: 'satellites',
            kind: 'satellite-pass',
            eventId: satellitePassReminderId(p),
            target: p.id,
            jd: p.peakJd,
            eventAt: new Date(p.peakAt).toISOString(),
            observerPlanet: 'Earth',
            landingTitle: p.name + ' · 最高 ' + String(Math.round(p.maxAlt)) + '°',
            landingSource: 'card'
          }
        }).catch((error: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm failed: code=%{public}d msg=%{public}s', error.code, error.message)
        })
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm err: %{public}s', String(error))
      }
      return
    }
    if (this.formKind === 'solar_system_card') {
      const targetJd = this.orreryDayOffset !== 0
        ? Math.round(((Date.now() + this.orreryDayOffset * 86400000) / 86400000.0 + 2440587.5) * 100000) / 100000
        : 0
      try {
        this.liveFormContext.startAbilityByLiveForm({
          bundleName: 'com.joinother.skyinstrument',
          abilityName: 'QAbility',
          parameters: {
            panel: 'astro',
            tab: 0,
            positionMode: 1,
            observerPlanet: routePlanetForCard(this.observerPlanet),
            jd: targetJd,
            landingTitle: '太阳系日心轨盘 · ' + this.orreryEpochLabel(),
            landingSource: 'card'
          }
        }).catch((error: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm failed: code=%{public}d msg=%{public}s', error.code, error.message)
        })
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm err: %{public}s', String(error))
      }
      return
    }
    const isSolarFlow = this.formKind === 'solar_arc_card' || this.orbBody.trim().toLowerCase() === 'sun'
    const targetPanel = this.formKind === 'celestial_events_card' ? 'calendar' : 'sky'
    const focusTarget = isSolarFlow
      ? 'Sun'
      : (this.formKind === 'celestial_events_card'
        ? (this.heroEvent()?.target ?? routeTargetForCard(this.observerPlanet))
        : focusTargetForCard(this.observerPlanet, this.companionEnglish, this.orbBody))
    const targetJd = this.formKind === 'celestial_events_card'
      ? (this.heroEvent()?.jd ?? 0)
      : offsetHoursToJd(Date.now(), this.timeOffsetHours)
    const eventId = this.formKind === 'celestial_events_card' ? (this.heroEvent()?.id ?? '') : ''
    try {
      this.liveFormContext.startAbilityByLiveForm({
        bundleName: 'com.joinother.skyinstrument',
        abilityName: 'QAbility',
        parameters: {
          panel: targetPanel,
          observerPlanet: routePlanetForCard(this.observerPlanet),
          target: focusTarget,
          jd: targetJd,
          eventId: eventId,
          landingTitle: this.showcaseHeading(),
          landingSource: 'card'
        }
      }).catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm failed: code=%{public}d msg=%{public}s', error.code, error.message)
      })
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'startAbilityByLiveForm err: %{public}s', String(error))
    }
  }

  // ---- Helper methods mirroring the exact resting cards ----

  private shouldShowPhaseShadow(): boolean {
    if (this.formKind === 'celestial_events_card' || this.formKind === 'solar_arc_card') return false
    const body = this.orbBody.trim().toLowerCase()
    return body === 'moon' || body === 'earth'
  }

  private safeTextColor(): string {
    return /^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(this.textColor) ? this.textColor : '#F5F9FF'
  }

  private contrastShadowColor(): string {
    return isLightTextColor(this.safeTextColor()) ? '#8C000000' : '#70FFFFFF'
  }

  private floatingCaptionText(): string {
    const body = this.orbBody.trim().toLowerCase()
    if (body === 'sun') {
      const stage = this.solarStage.length > 0 ? this.solarStage : solarStageFromAltitude(this.sunAlt)
      const sign = this.sunAlt >= 0 ? '+' : ''
      return '太阳 · ' + stage + ' ' + sign + String(Math.round(this.sunAlt)) + '°'
    }
    if (body === 'moon' || this.observerPlanet === 'Moon') {
      const pct = this.moonIllumination >= 0 ? (' · ' + String(Math.round(this.moonIllumination)) + '%') : ''
      return this.moonPhase + pct
    }
    if (this.observerPlanet === 'Titan') {
      return '土星 · ' + this.moonPhase
    }
    return this.observerPlanetName + ' · ' + this.observationSummary
  }

  private companionAccentColor(): string {
    const body = this.orbBody.trim().toLowerCase()
    if (body === 'sun') return '#FFD166'
    if (body === 'earth') return '#74BFFF'
    if (body === 'saturn' || body === 'titan') return '#F6CE88'
    if (body === 'mars') return '#F09B6B'
    return '#C8DCFF'
  }

  private companionBottomTint(): string {
    if (this.cardThemeStyle === 'deep') return '#0B1224'
    return /^#[0-9A-Fa-f]{6}$/.test(this.skyHexHorizon) ? this.skyHexHorizon : '#12203B'
  }

  private skyTopGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#050811'
    return this.skyHexTop
  }

  private skyBottomGradient(): string {
    if (this.cardThemeStyle === 'deep') return '#0D162B'
    return this.skyHexHorizon
  }

  private isStale(): boolean { return this.dataStatus === '旧快照' }

  private planetStrip(): string {
    return formatPlanetDisplayList(this.visiblePlanetsJson, this.planetNames, this.cardLabelStyle)
  }

  private planetRows(): CompactPlanetItem[] {
    return fallbackPlanetRows(parseVisiblePlanets(this.visiblePlanetsJson))
  }

  private allEvents(): CompactEventItem[] {
    return parseUpcomingEvents(this.upcomingEventsJson)
  }

  private eventsPage(): UpcomingEventPage {
    return sliceUpcomingEventPage(this.allEvents(), 0, this.isTall() ? 4 : 2)
  }

  private visibleEvents(): CompactEventItem[] {
    return this.eventsPage().items
  }

  private heroEvent(): CompactEventItem | undefined {
    return this.eventsPage().hero
  }

  private heroTitle(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.title : (this.nextEventTitle.length > 0 ? this.nextEventTitle : '等待星历同步')
  }

  private heroKind(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.kind : this.nextEventKind
  }

  private heroAtMs(): number {
    const ev = this.heroEvent()
    return ev !== undefined ? ev.at : this.nextEventAt
  }

  private heroCountdown(): string {
    const ev = this.heroEvent()
    return ev !== undefined ? formatCountdownZh(ev.at, Date.now()) : this.nextEventCountdown
  }

  private isReminded(eventId: string): boolean {
    if (eventId.length === 0) return false
    return parseRemindedEventIds(this.remindedEventIds).includes(eventId)
  }

  private solarAltLabel(): string {
    const alt = Math.round(this.sunAlt)
    return (alt >= 0 ? '+' : '') + String(alt) + '°'
  }

  private solarStageLabel(): string {
    return this.solarStage.length > 0 ? this.solarStage : solarStageFromAltitude(this.sunAlt)
  }

  private solarDaylightLabel(): string {
    return this.daylightDuration.length > 0 && this.daylightDuration !== '—'
      ? this.daylightDuration : computeDaylightDuration(this.sunRise, this.sunSet)
  }

  private solarGoldenLabel(): string {
    return this.goldenHourText.length > 0 && this.goldenHourText !== '—'
      ? this.goldenHourText : computeGoldenHourClock(this.sunSet)
  }

  private solarTermLabel(): string {
    return this.solarTermText.length > 0 ? this.solarTermText : estimateSolarTermZh(Date.now())
  }

  private showcaseHeading(): string {
    if (this.formKind === 'satellite_pass_card') {
      const p = this.activeSatPass()
      return p.name + ' · ' + formatCountdownZh(p.startAt, Date.now())
    }
    if (this.formKind === 'solar_system_card') {
      return '太阳系仪 · ' + this.orreryEpochLabel()
    }
    if (this.formKind === 'solar_arc_card' || this.orbBody.trim().toLowerCase() === 'sun') {
      return '太阳 · ' + this.solarStageLabel() + ' ' + this.solarAltLabel()
    }
    if (this.formKind === 'celestial_events_card') {
      return this.heroTitle()
    }
    if (this.formKind === 'companion_arc_card') {
      return this.moonPhase.startsWith(this.companionName) ? this.moonPhase : (this.companionName + ' · ' + this.moonPhase)
    }
    return this.observerPlanetName + ' · ' + this.observationSummary
  }

  private showcaseSubline(): string {
    if (this.formKind === 'satellite_pass_card') {
      const p = this.activeSatPass()
      return compassDirectionZh(p.startAz) + ' → ' + compassDirectionZh(p.endAz) +
        ' · 最高 ' + String(Math.round(p.maxAlt)) + '° · ' +
        satelliteBrightnessGradeZh(p.mag, p.visible)
    }
    if (this.formKind === 'solar_system_card') {
      return this.orrerySummaryText() + ' · 轻触进入日心轨盘'
    }
    if (this.formKind === 'solar_arc_card' || this.orbBody.trim().toLowerCase() === 'sun') {
      return '升 ' + this.sunRise + ' · 中天 ' + this.sunTransit + ' · 落 ' + this.sunSet + ' · 昼长 ' + this.solarDaylightLabel()
    }
    if (this.formKind === 'celestial_events_card') {
      const cd = this.heroCountdown()
      return (cd.length > 0 ? ('倒计时 ' + cd) : '点击进入天象日历') +
        (this.planetNames.length > 0 ? (' · ' + this.planetNames) : '')
    }
    if (this.formKind === 'companion_arc_card') {
      return this.observerPlanetName + '观测 · ' + (this.moonSummary.length > 0 ? this.moonSummary : '点击查看星历')
    }
    const phasePart = this.moonPhase.startsWith(this.companionName) ? this.moonPhase : (this.companionName + ' · ' + this.moonPhase)
    return phasePart + (this.planetNames.length > 0 ? (' · ' + this.planetNames) : '')
  }

  // ---- Pixel-matched resting card backdrops (orb replaced by measured invisible socket!) ----

  @Builder
  buildSatellitePassRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide() && !this.isTall()) {
        Column() {
          Row({ space: 4 }) {
            Text(this.activeSatPass().name)
              .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').layoutWeight(1).maxLines(1)
            Text(this.satMagBadge(this.activeSatPass()))
              .fontSize(9.5).fontWeight(FontWeight.Medium)
              .fontColor(satelliteVisualProfile(this.activeSatPass().archetype).accentHex)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 }).backgroundColor('#280B1830').borderRadius(8)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)

          Stack({ alignContent: Alignment.TopStart }) {
            SatellitePassArcView({
              stageWidth: this.satArcStageWidth(),
              stageHeight: this.satArcStageHeight(),
              maxAlt: this.activeSatPass().maxAlt,
              startAz: this.activeSatPass().startAz,
              endAz: this.activeSatPass().endAz,
              archetype: this.activeSatPass().archetype,
              visible: this.activeSatPass().visible,
              showCraft: false,
              craftSize: this.satCraftRestingSize()
            })
            Column()
              .width(this.satCraftRestingSize())
              .height(this.satCraftRestingSize())
              .position({
                x: this.satArcStageWidth() * 0.5 - this.satCraftRestingSize() * 0.5,
                y: Math.max(0, this.satCraftApexY(this.satArcStageHeight()) - this.satCraftRestingSize() * 0.5)
              })
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .width(this.satArcStageWidth())
          .height(this.satArcStageHeight())
          .opacity(this.restingContentOpacity)

          Row({ space: 5 }) {
            Text(formatCountdownZh(this.activeSatPass().startAt, Date.now()))
              .fontSize(10.5).fontWeight(FontWeight.Medium).fontColor('#7CEEFF').layoutWeight(1).maxLines(1)
            Text('提醒')
              .fontSize(9.5).fontWeight(FontWeight.Medium).fontColor('#EAF4FF').height(22)
              .padding({ left: 8, right: 8 }).backgroundColor('#2E3B6DB8').borderRadius(11)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      } else if (!this.isTall()) {
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.TopStart }) {
            SatellitePassArcView({
              stageWidth: this.satArcStageWidth(),
              stageHeight: this.satArcStageHeight(),
              maxAlt: this.activeSatPass().maxAlt,
              startAz: this.activeSatPass().startAz,
              endAz: this.activeSatPass().endAz,
              archetype: this.activeSatPass().archetype,
              visible: this.activeSatPass().visible,
              showCraft: false,
              craftSize: this.satCraftRestingSize()
            })
            Column()
              .width(this.satCraftRestingSize())
              .height(this.satCraftRestingSize())
              .position({
                x: this.satArcStageWidth() * 0.5 - this.satCraftRestingSize() * 0.5,
                y: Math.max(0, this.satCraftApexY(this.satArcStageHeight()) - this.satCraftRestingSize() * 0.5)
              })
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .width(this.satArcStageWidth())
          .height(this.satArcStageHeight())
          .opacity(this.restingContentOpacity)

          Column({ space: 4 }) {
            Row({ space: 4 }) {
              Text(satelliteVisualProfile(this.activeSatPass().archetype).categoryLabelZh)
                .fontSize(9.5).fontWeight(FontWeight.Medium)
                .fontColor(satelliteVisualProfile(this.activeSatPass().archetype).accentHex)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 }).backgroundColor('#2C13294E').borderRadius(8)
              Text(this.satMagBadge(this.activeSatPass())).fontSize(9.5).fontColor('#CFE4FF')
            }.width('100%')

            Text(this.activeSatPass().name)
              .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').width('100%').maxLines(1)

            Row({ space: 6 }) {
              Text(formatCountdownZh(this.activeSatPass().startAt, Date.now()))
                .fontSize(15).fontWeight(FontWeight.Bold).fontColor('#6DF5F5')
              Text(this.satClockOnly(this.activeSatPass().startAt) + ' · ' + formatPassDurationZh(this.activeSatPass().durationSec))
                .fontSize(10.5).fontColor('#B8D6F5').layoutWeight(1).maxLines(1)
            }.width('100%').alignItems(VerticalAlign.Bottom)

            Text(satelliteBrightnessGradeZh(this.activeSatPass().mag, this.activeSatPass().visible) + ' · 距 ' + String(Math.round(this.activeSatPass().rangeKm)) + ' km')
              .fontSize(10).fontColor('#9ABCE0').width('100%').maxLines(1)

            Blank()

            Row({ space: 6 }) {
              Text('预约提醒').fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').textAlign(TextAlign.Center).layoutWeight(1).height(27).backgroundColor('#323F76C8').borderRadius(13.5)
              Text('追踪 ↗').fontSize(10).fontWeight(FontWeight.Medium).fontColor('#8CEEFF').textAlign(TextAlign.Center).width(52).height(27).backgroundColor('#28163A6E').borderRadius(13.5)
            }.width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ top: 2, bottom: 2 })
          .opacity(this.restingContentOpacity)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      } else {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Column({ space: 2 }) {
              Text(this.activeSatPass().name).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').maxLines(1)
              Text(formatCountdownZh(this.activeSatPass().startAt, Date.now()) + ' · ' + this.satMagBadge(this.activeSatPass()))
                .fontSize(10).fontColor('#9CD4FF').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Text('提醒').fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFFFFF').height(26).padding({ left: 10, right: 10 }).backgroundColor('#363F76C8').borderRadius(13)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)

          Stack({ alignContent: Alignment.TopStart }) {
            SatellitePassArcView({
              stageWidth: this.satArcStageWidth(),
              stageHeight: this.satArcStageHeight(),
              maxAlt: this.activeSatPass().maxAlt,
              startAz: this.activeSatPass().startAz,
              endAz: this.activeSatPass().endAz,
              archetype: this.activeSatPass().archetype,
              visible: this.activeSatPass().visible,
              showCraft: false,
              craftSize: this.satCraftRestingSize()
            })
            Column()
              .width(this.satCraftRestingSize())
              .height(this.satCraftRestingSize())
              .position({
                x: this.satArcStageWidth() * 0.5 - this.satCraftRestingSize() * 0.5,
                y: Math.max(0, this.satCraftApexY(this.satArcStageHeight()) - this.satCraftRestingSize() * 0.5)
              })
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .width(this.satArcStageWidth())
          .height(this.satArcStageHeight())
          .opacity(this.restingContentOpacity)

          Blank()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 11, bottom: 10 })
      }

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 162,
      colors: [
        [this.cardThemeStyle === 'deep' ? '#040710' : '#060E24', 0.0],
        [this.cardThemeStyle === 'deep' ? '#0A1224' : '#0E2448', 1.0]
      ]
    })
    .border({ width: 0.6, color: '#2C6DF5F5' })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildSolarSystemRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide() && !this.isTall()) {
        Column() {
          Row() {
            Text('✦ 太阳系')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .maxLines(1)
            Blank()
            Text(this.orreryInnerOnly ? '内系' : '全系')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#9CD4FF')
              .height(22)
              .padding({ left: 8, right: 8 })
              .backgroundColor('#2E4678C4')
              .borderRadius(11)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(this.orreryRestingWidth())
              .height(this.orreryRestingHeight())
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .layoutWeight(1)
          .width('100%')

          Row({ space: 4 }) {
            Text('‹30天')
              .fontSize(10)
              .fontColor('#CFE4FF')
              .height(22)
              .padding({ left: 6, right: 6 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
            Text(this.orreryDayOffset === 0 ? '此刻' : (this.orreryDayOffset > 0 ? '+' + String(this.orreryDayOffset) + 'd' : String(this.orreryDayOffset) + 'd'))
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.orreryDayOffset === 0 ? '#FFE29A' : '#8AD4FF')
              .textAlign(TextAlign.Center)
              .layoutWeight(1)
              .height(22)
              .backgroundColor('#1EFFFFFF')
              .borderRadius(11)
            Text('30天›')
              .fontSize(10)
              .fontColor('#CFE4FF')
              .height(22)
              .padding({ left: 6, right: 6 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      } else if (!this.isTall()) {
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(this.orreryRestingWidth())
              .height(this.orreryRestingHeight())
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .layoutWeight(1)
          .height('100%')

          Column({ space: 6 }) {
            Row() {
              Text('太阳系仪')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
              Blank()
              Text('↗')
                .fontSize(13)
                .fontColor('#9CD4FF')
            }
            .width('100%')

            Text(this.orreryEpochLabel())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.orreryDayOffset === 0 ? '#FFE29A' : '#8AD4FF')
              .width('100%')
              .maxLines(1)

            Text(this.orreryInnerOnly ? '内太阳系 · 切全系 ↻' : '全太阳系 · 切内系 ↻')
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .textAlign(TextAlign.Center)
              .width('100%')
              .height(30)
              .backgroundColor('#384678C4')
              .borderRadius(15)
              .maxLines(1)

            Blank()

            Row({ space: 4 }) {
              Text('-1月').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor('#D8ECFF').textAlign(TextAlign.Center).layoutWeight(1).height(32).backgroundColor('#24FFFFFF').borderRadius(16)
              Text('今').fontSize(11).fontWeight(FontWeight.Medium).fontColor('#FFE29A').textAlign(TextAlign.Center).width(30).height(32).backgroundColor('#344678C4').borderRadius(16)
              Text('+1月').fontSize(10.5).fontWeight(FontWeight.Medium).fontColor('#D8ECFF').textAlign(TextAlign.Center).layoutWeight(1).height(32).backgroundColor('#24FFFFFF').borderRadius(16)
            }
            .width('100%')
          }
          .width(114)
          .height('100%')
          .padding({ top: 3, bottom: 2 })
          .opacity(this.restingContentOpacity)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      } else {
        Column({ space: 6 }) {
          Row() {
            Column({ space: 2 }) {
              Text('✦ 太阳系仪 · ' + this.orreryEpochLabel())
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
              Text(this.orrerySummaryText())
                .fontSize(10)
                .fontColor('#B8D3F2')
                .maxLines(1)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(this.orreryInnerOnly ? '切至全系' : '切至内系')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .height(26)
              .padding({ left: 10, right: 10 })
              .backgroundColor('#364678C4')
              .borderRadius(13)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)

          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(this.orreryRestingWidth())
              .height(this.orreryRestingHeight())
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .layoutWeight(1)
          .width('100%')

          Row({ space: 6 }) {
            ForEach(this.orreryFeaturedTelemetry(), (p: OrreryPlanetState) => {
              Column({ space: 1 }) {
                Row({ space: 3 }) {
                  Circle().width(5).height(5).fill(p.color)
                  Text(p.nameZh).fontSize(10).fontWeight(FontWeight.Medium).fontColor('#EAF4FF')
                }
                Text(String(Math.round(p.lonDeg)) + '° · ' + p.distAU.toFixed(1) + 'AU')
                  .fontSize(9).fontColor('#9FBAD8').maxLines(1)
              }
              .layoutWeight(1).padding({ top: 4, bottom: 4 }).backgroundColor('#1AFFFFFF').borderRadius(9).alignItems(HorizontalAlign.Center)
            }, (p: OrreryPlanetState) => p.id)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)

          Row({ space: 6 }) {
            Text('-30天').fontSize(10).fontColor('#DCEBFF').textAlign(TextAlign.Center).layoutWeight(1).height(28).backgroundColor('#22FFFFFF').borderRadius(14)
            Text('此刻').fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFE29A').textAlign(TextAlign.Center).layoutWeight(1).height(28).backgroundColor('#324678C4').borderRadius(14)
            Text('+30天').fontSize(10).fontColor('#DCEBFF').textAlign(TextAlign.Center).layoutWeight(1).height(28).backgroundColor('#22FFFFFF').borderRadius(14)
            Text('+1年').fontSize(10).fontColor('#DCEBFF').textAlign(TextAlign.Center).layoutWeight(1).height(28).backgroundColor('#22FFFFFF').borderRadius(14)
            Text('轨盘 ↗').fontSize(10).fontWeight(FontWeight.Medium).fontColor('#8AD4FF').textAlign(TextAlign.Center).layoutWeight(1).height(28).backgroundColor('#2C1C3C6E').borderRadius(14)
          }
          .width('100%')
          .opacity(this.restingContentOpacity)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 11, bottom: 10 })
      }

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 162,
      colors: [
        [this.cardThemeStyle === 'deep' ? '#04060E' : '#060C1E', 0.0],
        [this.cardThemeStyle === 'deep' ? '#0B1120' : '#102042', 1.0]
      ]
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildSolarRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: this.sunAlt, themeStyle: this.cardThemeStyle })

      if (this.sunAlt > -6 && this.cardThemeStyle !== 'deep') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 165,
            colors: [
              ['#34080E1E', 0.0],
              ['#66090E1D', 1.0]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        if (!this.isWide()) {
          // 2x2 SolarArcCard mirror
          Column() {
            Row() {
              Text(this.observerPlanet === 'Earth' || this.observerPlanet === 'Sun' ? '☀ 太阳 ↻' : ('☀ ' + this.observerPlanetName + ' ↻'))
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFF4D6')
                .maxLines(1)
                .height(26)
                .padding({ left: 8, right: 9 })
                .backgroundColor('#38140C04')
                .borderRadius(13)
              Blank()
              Text(this.solarAltLabel())
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFD166')
            }
            .width('100%')

            Column({ space: 2 }) {
              Column()
                .width(66)
                .height(66)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
              Text(this.solarStageLabel())
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)

            HorizonArcView({
              arcWidth: 122,
              arcHeight: 28,
              altitudeDeg: this.sunAlt,
              riseText: this.sunRise,
              setText: this.sunSet,
              customProgress: computeSolarArcProgress(this.sunRise, this.sunSet, Date.now(), this.sunAlt),
              accentColor: '#FFD166'
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 13, right: 13, top: 10, bottom: 9 })
        } else {
          // 2x4 SolarArcCard mirror
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Column()
                .width(86)
                .height(86)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
              Text('昼长 ' + this.solarDaylightLabel())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFE8B0')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width(96)
            .height('100%')

            Column({ space: 5 }) {
              Row() {
                Column({ space: 2 }) {
                  Text(this.observerPlanet === 'Earth' || this.observerPlanet === 'Sun' ? '☀ 太阳 · 地球 ↻' : ('☀ ' + this.observerPlanetName + ' ↻'))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFF3D2')
                    .height(24)
                    .padding({ left: 8, right: 9 })
                    .backgroundColor('#38140C04')
                    .borderRadius(12)
                    .maxLines(1)
                  Text(this.solarStageLabel() + ' · ' + this.solarTermLabel())
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.solarAltLabel())
                  .fontSize(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFD166')
                  .margin({ left: 4 })
              }
              .width('100%')

              HorizonArcView({
                arcWidth: 176,
                arcHeight: 32,
                altitudeDeg: this.sunAlt,
                riseText: this.sunRise,
                midFooterText: this.sunTransit !== '—' ? ('中天 ' + this.sunTransit) : '',
                setText: this.sunSet,
                customProgress: computeSolarArcProgress(this.sunRise, this.sunSet, Date.now(), this.sunAlt),
                accentColor: '#FFD166'
              })

              Row({ space: 5 }) {
                ForEach([
                  ['日出', this.sunRise],
                  ['中天', this.sunTransit],
                  ['黄金', this.solarGoldenLabel()],
                  ['暗夜', this.darkStart]
                ], (pair: string[], idx: number) => {
                  Column({ space: 1 }) {
                    Text(pair[0]).fontSize(9).fontWeight(FontWeight.Medium).fontColor('#DDE8F8').maxLines(1)
                    Text(pair[1]).fontSize(10).fontWeight(FontWeight.Medium).fontColor('#FFE09A').maxLines(1)
                  }
                  .layoutWeight(1)
                  .height(34)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .backgroundColor('#32090F1E')
                  .borderRadius(10)
                  .border({ width: 0.5, color: '#2AFFE09A' })
                }, (pair: string[], idx: number) => pair[0] + '_' + String(idx))
              }
              .width('100%')
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 13, right: 14, top: 11, bottom: 10 })
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.restingContentOpacity)

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 165,
      colors: [
        [this.cardThemeStyle === 'deep' ? '#0B0912' : this.skyTopGradient(), 0.0],
        [this.cardThemeStyle === 'deep' ? '#221710' : this.skyBottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#30FFD166' })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildCompanionRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      Column() {
        if (!this.isWide()) {
          // 2x2 CompanionArcCard mirror
          Column() {
            Row() {
              Text((this.observerPlanet === 'Earth' || this.observerPlanet === 'Sun'
                ? (this.orbBody.trim().toLowerCase() === 'sun' ? '☀ 太阳' : this.companionName)
                : (this.observerPlanetName + '·' + this.companionName)) + ' ↻')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#E4F0FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .height(26)
                .padding({ left: 8, right: 9 })
                .backgroundColor('#28FFFFFF')
                .borderRadius(13)
              Blank()
              Text(this.moonIllumination >= 0 ? (String(Math.round(this.moonIllumination)) + '%') : '—')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.companionAccentColor())
            }
            .width('100%')

            Column({ space: 2 }) {
              // Exact 64x64 orb socket placeholder
              Column()
                .width(64)
                .height(64)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
              Text(this.moonPhase)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Center)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)

            HorizonArcView({
              arcWidth: 122,
              arcHeight: 28,
              altitudeDeg: this.companionAlt,
              riseText: this.moonRise,
              setText: this.moonSet,
              accentColor: this.companionAccentColor()
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 13, right: 13, top: 10, bottom: 9 })
        } else {
          // 2x4 CompanionArcCard mirror
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Column()
                .width(84)
                .height(84)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
              Text((this.companionRole === 'parent-planet' || this.companionRole === 'host')
                ? ('宿主 · ' + this.companionName) : this.moonPhase)
                .fontSize(10.5)
                .fontWeight(FontWeight.Medium)
                .fontColor('#CFE6FF')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width(96)
            .height('100%')

            Column({ space: 4 }) {
              Row() {
                Column({ space: 2 }) {
                  Text(this.observerPlanet === 'Earth' ? '月球 · 月相 ↻' : (this.observerPlanetName + ' · ' + this.companionName + ' ↻'))
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#E4F1FF')
                    .height(28)
                    .padding({ left: 10, right: 10 })
                    .backgroundColor('#2CFFFFFF')
                    .borderRadius(14)
                    .maxLines(1)
                  Text(this.moonPhase)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.moonIllumination >= 0 ? (String(Math.round(this.moonIllumination)) + '%') : '—')
                  .fontSize(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.companionAccentColor())
              }
              .width('100%')

              HorizonArcView({
                arcWidth: 176,
                arcHeight: 28,
                altitudeDeg: this.companionAlt,
                riseText: this.moonRise,
                setText: this.moonSet,
                accentColor: this.companionAccentColor()
              })

              if (this.orbBody.trim().toLowerCase() === 'moon' || this.orbBody.trim().toLowerCase() === 'earth') {
                MiniPhaseStripView({
                  phaseAge: this.moonAge,
                  nowMs: Date.now(),
                  selectedIndex: 0
                })
              }
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 13, right: 14, top: 10, bottom: 9 })
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.restingContentOpacity)

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 165,
      colors: [
        ['#050914', 0.0],
        [this.companionBottomTint(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#22FFFFFF' })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildSkyWindowRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: this.sunAlt, themeStyle: this.cardThemeStyle })

      if (this.sunAlt > -4 && this.cardThemeStyle !== 'deep') {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 170,
            colors: [
              ['#24061024', 0.0],
              ['#4E061024', 1.0]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
      }

      Column()
        .width('100%')
        .height(this.isTall() ? 72 : 44)
        .position({ x: 0, y: '100%' })
        .translate({ y: this.isTall() ? -72 : -44 })
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [
            ['#00FFFFFF', 0.0],
            ['#18FFFFFF', 1.0]
          ]
        })
        .hitTestBehavior(HitTestMode.None)

      Column() {
        if (!this.isWide() && !this.isTall()) {
          // 2x2 SkyWindowCard mirror
          Column() {
            Row() {
              Row({ space: 4 }) {
                Circle().width(6).height(6).fill(this.isStale() ? '#FFB74D' : '#8AD4FF')
                Text(this.observerPlanetName + ' ↻')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#EBF4FF')
                  .maxLines(1)
              }
              .height(28)
              .padding({ left: 9, right: 10 })
              .backgroundColor('#38081224')
              .borderRadius(14)

              Blank()
              Text(this.moonSummary).fontSize(10).fontColor('#B8DCEEFF').maxLines(1)
            }
            .width('100%')

            Row({ space: 6 }) {
              Column({ space: 2 }) {
                Text(this.observationSummary)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.moonPhase)
                  .fontSize(11)
                  .fontColor('#CCE4F6FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column()
                .width(56)
                .height(56)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
            }
            .width('100%')
            .layoutWeight(1)
            .alignItems(VerticalAlign.Center)

            Row() {
              Text(this.planetStrip())
                .fontSize(10)
                .fontColor('#A8D8ECFF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .height('100%')
          .padding({ left: 13, right: 12, top: 11, bottom: 11 })
        } else {
          // 2x4 & 4x4 SkyWindowCard mirror
          Column({ space: this.isTall() ? 10 : 6 }) {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Row({ space: 5 }) {
                    Circle().width(6).height(6).fill(this.isStale() ? '#FFB74D' : '#8AD4FF')
                    Text(this.observerPlanetName + ' · 天穹 ↻')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#F0F7FF')
                      .maxLines(1)
                  }
                  .height(30)
                  .padding({ left: 10, right: 11 })
                  .backgroundColor('#3A071022')
                  .borderRadius(15)

                  if (this.timeOffsetHours > 0 && this.timePreviewLabel.length > 0) {
                    Text(this.timePreviewLabel)
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFE09A')
                      .height(26)
                      .padding({ left: 8, right: 8 })
                      .textAlign(TextAlign.Center)
                      .backgroundColor('#48140D04')
                      .borderRadius(13)
                  } else if (this.isStale()) {
                    Text('待刷新').fontSize(10).fontColor('#FFD27F')
                  }
                }

                Text(this.timeOffsetHours > 0
                  ? ('太阳高度 ' + this.sunAlt.toFixed(1) + '°')
                  : this.observationSummary)
                  .fontSize(this.isTall() ? 20 : 17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 1 })

                Text(this.observerPlanet === 'Earth'
                  ? ('☀ ' + this.sunRise + '–' + this.sunSet + ' · 暗夜 ' + this.darkStart + '–' + this.darkEnd)
                  : this.observerPlanet === 'Sun'
                    ? ('日出 ' + this.sunRise + ' · 日落 ' + this.sunSet + ' · 暗夜 ' + this.darkStart)
                    : (this.moonPhase.startsWith(this.companionName) ? this.moonPhase : (this.companionName + ' · ' + this.moonPhase)))
                  .fontSize(11)
                  .fontColor('#CCE4F7FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (!this.isTall()) {
                  Row({ space: 6 }) {
                    Text('‹ -4h')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.timeOffsetHours > 0 ? '#FFFFFF' : '#77B0CCE8')
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .height(32)
                      .backgroundColor('#34061022')
                      .borderRadius(16)
                    Text(this.timeOffsetHours > 0 ? '此刻' : '48h')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.timeOffsetHours > 0 ? '#FFE09A' : '#B8DAF8')
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .height(32)
                      .backgroundColor('#28061022')
                      .borderRadius(16)
                    Text('+4h ›')
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#FFFFFF')
                      .textAlign(TextAlign.Center)
                      .layoutWeight(1)
                      .height(32)
                      .backgroundColor('#34061022')
                      .borderRadius(16)
                  }
                  .width('100%')
                  .margin({ top: 4 })
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 2 }) {
                Column()
                  .width(this.isTall() ? 82 : 72)
                  .height(this.isTall() ? 82 : 72)
                  .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
                Text(this.companionName + ' ' + this.moonSummary)
                  .fontSize(10)
                  .fontColor('#C4DDF4FF')
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.isTall()) {
              Row({ space: 8 }) {
                Text('‹ -4h').fontSize(12).fontWeight(FontWeight.Medium)
                  .fontColor(this.timeOffsetHours > 0 ? '#FFFFFF' : '#77B0CCE8')
                  .textAlign(TextAlign.Center).layoutWeight(1).height(34).backgroundColor('#30FFFFFF').borderRadius(17)
                Text(this.timeOffsetHours > 0 ? '回到此刻' : '48h 实时').fontSize(12).fontWeight(FontWeight.Medium)
                  .fontColor(this.timeOffsetHours > 0 ? '#FFE09A' : '#C2E2FF')
                  .textAlign(TextAlign.Center).layoutWeight(1.2).height(34).backgroundColor('#22FFFFFF').borderRadius(17)
                Text('+4h ›').fontSize(12).fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .textAlign(TextAlign.Center).layoutWeight(1).height(34).backgroundColor('#30FFFFFF').borderRadius(17)
              }
              .width('100%')
              .padding({ left: 6, right: 6, top: 5, bottom: 5 })
              .backgroundColor('#2A060D1E')
              .borderRadius(20)

              Column({ space: 9 }) {
                Row() {
                  Text('今夜行星可见性').fontSize(12).fontWeight(FontWeight.Medium).fontColor('#C6E2FFFF')
                  Blank()
                  Text(this.updatedAt).fontSize(10).fontColor('#8CC2DEFF')
                }
                .width('100%')

                if (this.planetRows().length > 0) {
                  ForEach(this.planetRows(), (p: CompactPlanetItem) => {
                    PlanetVisibilityRow({
                      itemName: p.n,
                      itemSymbol: p.s,
                      labelStyle: this.cardLabelStyle,
                      visible: p.v,
                      altitude: p.a,
                      riseText: p.r,
                      setText: p.t
                    })
                  }, (p: CompactPlanetItem, idx: number) => p.e + '_' + String(idx))
                } else {
                  Text(this.planetNames).fontSize(12).fontColor('#A8C8E8FF').maxLines(1)
                }
              }
              .width('100%')
              .layoutWeight(1)
              .justifyContent(FlexAlign.SpaceEvenly)
              .padding({ left: 13, right: 13, top: 10, bottom: 10 })
              .backgroundColor('#2B060D1E')
              .borderRadius(15)

              Row({ space: 8 }) {
                Circle().width(6).height(6).fill('#8AD4FF')
                Text(this.nextEventTitle).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#F4F9FF')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                Text(this.nextEventCountdown).fontSize(11).fontWeight(FontWeight.Medium).fontColor('#9ED2FF').maxLines(1)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('#36050B1A')
              .borderRadius(13)
            }
          }
          .width('100%')
          .height('100%')
          .padding({ left: 15, right: 14, top: 13, bottom: 13 })
        }
      }
      .width('100%')
      .height('100%')
      .opacity(this.restingContentOpacity)

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 170,
      colors: [
        [this.skyTopGradient(), 0.0],
        [this.skyBottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#24FFFFFF' })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildEventsRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      Column()
        .width(130)
        .height(130)
        .borderRadius(65)
        .clip(true)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 65,
          colors: [
            ['#2C' + eventAccentColor(this.heroKind()).slice(1), 0.0],
            ['#00000000', 1.0]
          ]
        })
        .position({ x: '68%', y: -32 })
        .hitTestBehavior(HitTestMode.None)

      Column({ space: this.isTall() ? 8 : 4 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text(this.observerPlanetName + ' · 天象 ↻')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D4E8FF')
                .height(22)
                .padding({ left: 8, right: 8 })
                .backgroundColor('#28FFFFFF')
                .borderRadius(11)
                .maxLines(1)
              Text(eventBadgeText(this.heroKind()))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(eventAccentColor(this.heroKind()))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#22FFFFFF')
                .borderRadius(8)
            }
            Text(this.heroTitle())
              .fontSize(this.isTall() ? 16 : 14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 7 }) {
            Column({ space: 1 }) {
              Text(this.heroCountdown())
                .fontSize(this.isTall() ? 18 : 15)
                .fontWeight(FontWeight.Medium)
                .fontColor(eventAccentColor(this.heroKind()))
                .maxLines(1)
              if (this.heroAtMs() > 0) {
                Text(formatShortDateZh(this.heroAtMs())).fontSize(10).fontColor('#9ABCE0').maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.End)

            if (this.heroEvent() !== undefined) {
              Text(this.isReminded(this.heroEvent()!.id) ? '★ 已约' : '提醒')
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isReminded(this.heroEvent()!.id) ? '#1B1404' : '#EAF4FF')
                .textAlign(TextAlign.Center)
                .constraintSize({ minWidth: 52 })
                .height(28)
                .padding({ left: 9, right: 9 })
                .backgroundColor(this.isReminded(this.heroEvent()!.id) ? '#FFD166' : '#3AFFFFFF')
                .borderRadius(14)
            }

            // Exact top-right orb socket placeholder
            Column()
              .width(this.isTall() ? 46 : 34)
              .height(this.isTall() ? 46 : 34)
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

        if (this.visibleEvents().length > 0) {
          if (this.eventsPage().pageCount > 1) {
            Row({ space: 6 }) {
              Text('后续天象 · 共 ' + String(this.allEvents().length - 1) + ' 场')
                .fontSize(10)
                .fontColor('#8FB4DA')
                .maxLines(1)
              Blank()
              Row({ space: 5 }) {
                Text('‹').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E4F1FF')
                  .textAlign(TextAlign.Center).width(26).height(22).backgroundColor('#2CFFFFFF').borderRadius(11)
                Text('1/' + String(this.eventsPage().pageCount)).fontSize(10).fontWeight(FontWeight.Medium).fontColor('#C6E0FA')
                Text('›').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E4F1FF')
                  .textAlign(TextAlign.Center).width(26).height(22).backgroundColor('#2CFFFFFF').borderRadius(11)
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
          }

          Column({ space: this.isTall() ? 8 : 4 }) {
            ForEach(this.visibleEvents(), (ev: CompactEventItem) => {
              Row({ space: 7 }) {
                Circle().width(6).height(6).fill(eventAccentColor(ev.kind))
                Text(ev.title)
                  .fontSize(this.isTall() ? 13 : 11)
                  .fontColor('#EEF5FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(formatShortDateZh(ev.at)).fontSize(10).fontColor('#96B6DA').maxLines(1)
                Text(this.isReminded(ev.id) ? '★ 已约' : '提醒')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isReminded(ev.id) ? '#1B1404' : '#EAF4FF')
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 52 })
                  .height(this.isTall() ? 30 : 25)
                  .padding({ left: 9, right: 9 })
                  .backgroundColor(this.isReminded(ev.id) ? '#FFD166' : '#3AFFFFFF')
                  .borderRadius(14)
              }
              .width('100%')
              .padding({ left: 10, right: 6, top: this.isTall() ? 6 : 3, bottom: this.isTall() ? 6 : 3 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(11)
            }, (ev: CompactEventItem, idx: number) => ev.id + '_' + String(idx))
          }
          .width('100%')
          .layoutWeight(this.isTall() ? 1 : 0)
          .justifyContent(this.isTall() ? FlexAlign.SpaceEvenly : FlexAlign.Start)
        }

        if (this.isTall()) {
          Row({ space: 6 }) {
            Text('可见行星').fontSize(10).fontColor('#88B0D4')
            Text(this.planetStrip())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#E4F1FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#1EFFFFFF')
          .borderRadius(12)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 14, right: 13, top: 10, bottom: 9 })
      .opacity(this.restingContentOpacity)

      this.buildFramedShowcaseOverlay()
    }
    .width(this.formRect.width)
    .height(this.formRect.height)
    .position({ x: this.formRect.left, y: this.formRect.top })
    .borderRadius(this.formBorderRadius)
    .clip(true)
    .linearGradient({
      angle: 160,
      colors: [
        [this.cardThemeStyle === 'deep' ? '#050811' : '#081024', 0.0],
        [this.cardThemeStyle === 'deep' ? '#0D1528' : '#132242', 1.0]
      ]
    })
    .border({ width: 0.6, color: '#24FFFFFF' })
    .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
    .onClick(() => this.launchAppDirect())
  }

  @Builder
  buildFramedShowcaseOverlay() {
    // Soft bottom vignette + crisp showcase spotlight that fades cleanly in & out over the dimmed resting card
    Column({ space: 5 }) {
      Blank()
      Row({ space: 6 }) {
        Text(this.formKind === 'solar_system_card'
          ? '太阳系'
          : (this.formKind === 'satellite_pass_card'
            ? satelliteVisualProfile(this.activeSatPass().archetype).categoryLabelZh
            : this.observerPlanetName))
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#D8ECFF')
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor('#380B1830')
          .borderRadius(8)
        if (this.formKind === 'celestial_events_card') {
          Text(eventBadgeText(this.heroKind()))
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor(eventAccentColor(this.heroKind()))
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor('#380B1830')
            .borderRadius(8)
        }
        Blank()
        Text('轻触进入 ↗')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor('#A8D4FF')
      }
      .width('100%')

      Text(this.showcaseHeading())
        .fontSize(this.isTall() ? 18 : 14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.showcaseSubline())
        .fontSize(11)
        .fontColor('#D0E4F8')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 14, right: 14, bottom: 12 })
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [
        ['#00060D1E', 0.0],
        ['#58060D1E', 0.45],
        ['#D6050B1A', 1.0]
      ]
    })
    .opacity(this.badgeOpacity)
    .translate({ y: this.controlsOffsetY })
    .hitTestBehavior(HitTestMode.None)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Card Surface — 100% pixel-matched to the resting inactive card at t=0 and t=return!
      if (this.isBorderlessFloating()) {
        Stack({ alignContent: Alignment.TopStart }) {
          // Exact resting FloatingOrbCard layout (orb replaced by measured 112x112 socket; caption fades smoothly!)
          Column({ space: 4 }) {
            Column()
              .width(112)
              .height(112)
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))

            Text(this.floatingCaptionText())
              .fontSize(11)
              .lineHeight(15)
              .height(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.safeTextColor())
              .textShadow({ radius: 5, color: this.contrastShadowColor(), offsetX: 0, offsetY: 1 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 6, right: 6 })
              .opacity(this.restingContentOpacity)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .hitTestBehavior(HitTestMode.None)

          // Interactive overflow controls (glide up cleanly while orb hovers, glide away before return!)
          Column({ space: 6 }) {
            Blank()
            Row({ space: 5 }) {
              Circle().width(5).height(5).fill('#8AD4FF')
              Text(this.showcaseHeading())
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F5F9FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor('#AE081124')
            .borderRadius(12)

            Row({ space: 8 }) {
              Text('↻ 换星')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#FFFFFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(34)
                .backgroundColor('#D61D4282')
                .borderRadius(17)
                .onClick(() => this.cycleFloatingPlanetInPlace())

              Text('✦ 星图')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#EAF4FF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(34)
                .backgroundColor('#C409142B')
                .borderRadius(17)
                .onClick(() => this.launchAppDirect())
            }
            .width('100%')
            .padding({ left: 4, right: 4 })
          }
          .width('100%')
          .height('100%')
          .padding({ bottom: 4 })
          .alignItems(HorizontalAlign.Center)
          .opacity(this.badgeOpacity)
          .translate({ y: this.controlsOffsetY })
        }
        .width(this.formRect.width)
        .height(this.formRect.height)
        .position({ x: this.formRect.left, y: this.formRect.top })
        .backgroundColor(Color.Transparent)
        .onAreaChange((_oldArea: Area, newArea: Area) => this.captureCardArea(newArea))
        .onClick(() => this.launchAppDirect())
      } else if (this.formKind === 'satellite_pass_card') {
        this.buildSatellitePassRestingCard()
      } else if (this.formKind === 'solar_system_card') {
        this.buildSolarSystemRestingCard()
      } else if (this.formKind === 'solar_arc_card') {
        this.buildSolarRestingCard()
      } else if (this.formKind === 'companion_arc_card') {
        this.buildCompanionRestingCard()
      } else if (this.formKind === 'celestial_events_card') {
        this.buildEventsRestingCard()
      } else {
        this.buildSkyWindowRestingCard()
      }

      // 2. Overflow Layer: Spacecraft Flyby / 3D Solar System Orrery / 3D Celestial Orb!
      if (this.formKind === 'satellite_pass_card') {
        Stack({ alignContent: Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            Image(satelliteIconResource(this.activeSatPass().archetype))
              .width(this.peakOrbSize())
              .height(this.peakOrbSize())
              .objectFit(ImageFit.Contain)
              .draggable(false)
          }
          .width(this.peakOrbSize())
          .height(this.peakOrbSize())
          .scale({ x: this.orbScale, y: this.orbScale })
          .rotate({ angle: this.orbTilt * 2 })
        }
        .width(this.peakOrbSize())
        .height(this.peakOrbSize())
        .position({
          x: this.slotCenterX - this.peakOrbSize() * 0.5,
          y: this.slotCenterY - this.peakOrbSize() * 0.5
        })
        .translate({ x: this.orbDx, y: this.orbDy })
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.None)
        .onAppear(() => this.scheduleOverflowShowcase())
      } else if (this.formKind === 'solar_system_card') {
        Stack({ alignContent: Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            SolarSystemOrreryStage({
              stageWidth: this.orreryPeakWidth(),
              stageHeight: this.orreryPeakHeight(),
              heliocentricPlanetsJson: this.heliocentricPlanetsJson,
              dayOffset: this.orreryDayOffset,
              innerOnly: this.orreryInnerOnly,
              tiltDeg: this.orreryTiltDeg(),
              showLabels: this.orreryShowLabels()
            })
          }
          .width(this.orreryPeakWidth())
          .height(this.orreryPeakHeight())
          .scale({ x: this.orbScale, y: this.orbScale })
        }
        .width(this.orreryPeakWidth())
        .height(this.orreryPeakHeight())
        .position({
          x: this.slotCenterX - this.orreryPeakWidth() * 0.5,
          y: this.slotCenterY - this.orreryPeakHeight() * 0.5
        })
        .translate({ x: this.orbDx, y: this.orbDy })
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.None)
        .onAppear(() => this.scheduleOverflowShowcase())
      } else {
        Stack({ alignContent: Alignment.Center }) {
          Stack({ alignContent: Alignment.Center }) {
            CelestialOrbView({
              orbBody: this.formKind === 'solar_arc_card' ? 'sun' : this.orbBody,
              orbSize: this.peakOrbSize(),
              showPhase: this.shouldShowPhaseShadow(),
              illumination: this.moonIllumination,
              phaseAge: this.moonAge,
              glowIntensity: 0
            })
          }
          .width(this.peakOrbSize())
          .height(this.peakOrbSize())
          .scale({ x: this.orbScale, y: this.orbScale })
          .rotate({ angle: this.orbTilt })
        }
        .width(this.peakOrbSize())
        .height(this.peakOrbSize())
        .position({
          x: this.slotCenterX - this.peakOrbSize() * 0.5,
          y: this.slotCenterY - this.peakOrbSize() * 0.5
        })
        .translate({ x: this.orbDx, y: this.orbDy })
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.None)
        .onAppear(() => this.scheduleOverflowShowcase())
      }

      // 3. Overflow Shooting Meteor Streak (for celestial_events_card)
      if (this.formKind === 'celestial_events_card') {
        Row({ space: 0 }) {
          Column()
            .width(96)
            .height(3)
            .borderRadius(1.5)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [
                ['#00FFFFFF', 0.0],
                ['#AAE0F4FF', 0.65],
                ['#FFFFFFFF', 1.0]
              ]
            })
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 12, color: '#99E0FF', offsetX: 0, offsetY: 0 })
        }
        .alignItems(VerticalAlign.Center)
        .rotate({ angle: -24 })
        .offset({ x: this.formRect.left + this.meteorX, y: this.formRect.top + this.meteorY })
        .opacity(this.meteorOpacity)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onDisAppear(() => {
      if (this.formId.length > 0) {
        formProvider.cancelOverflow(this.formId).catch(() => {})
      }
    })
  }
}
