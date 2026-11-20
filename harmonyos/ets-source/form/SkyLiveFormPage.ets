import { common } from '@kit.AbilityKit'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  CompactEventItem,
  CompactPlanetItem,
  formatCountdownZh,
  formatPlanetDisplayList,
  formatShortDateZh,
  isLightTextColor,
  nextCyclePlanet,
  parseRemindedEventIds,
  parseUpcomingEvents,
  parseVisiblePlanets
} from './AstronomyCardData'
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
  StarfieldLayer,
  eventAccentColor,
  eventBadgeText,
  fallbackPlanetRows
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
  }

  // Exact resting orb diameter in vp (1:1 match with the inactive card!)
  private restingOrbSize(): number {
    if (this.formKind === 'floating_orb_card') return 110
    if (this.formKind === 'companion_arc_card') return this.isWide() ? 86 : 64
    if (this.formKind === 'celestial_events_card') return this.isTall() ? 50 : 36
    // sky_window_card
    if (!this.isWide() && !this.isTall()) return 56
    return this.isTall() ? 82 : 72
  }

  // Native-resolution peak orb diameter in vp (orb renders at peakSize and scales down to startScale at rest -> zero upscaling blur!)
  private peakOrbSize(): number {
    if (this.formKind === 'floating_orb_card') return 130
    if (this.formKind === 'companion_arc_card') return this.isWide() ? 112 : 106
    if (this.formKind === 'celestial_events_card') return this.isTall() ? 124 : 96
    // sky_window_card
    if (!this.isWide() && !this.isTall()) return 104
    return this.isTall() ? 128 : 112
  }

  private startOrbScale(): number {
    return this.restingOrbSize() / this.peakOrbSize()
  }

  private initAnalyticalRestingSocket(): void {
    const l = this.formRect.left
    const t = this.formRect.top
    const w = this.formRect.width
    const h = this.formRect.height
    const s = this.restingOrbSize()

    if (this.formKind === 'floating_orb_card') {
      this.slotCenterX = l + w * 0.5
      this.slotCenterY = t + (h - 132) * 0.5 + 56
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
    // Wait 24ms (1-2 frames) so ArkUI's first layout pass locks exact sub-pixel slotCenterX/Y via onAreaChange!
    this.startTimerId = setTimeout(() => {
      this.runOverflowShowcase()
    }, 24)
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

    // Phase 1 (24ms -> 584ms): Smooth lift directly out of exact resting socket -> top-center overflow peak
    this.uiContext?.animateTo({ duration: 560, curve: Curve.FastOutSlowIn }, () => {
      this.orbDx = dx
      this.orbDy = dy
      this.orbScale = 1.0
      this.orbTilt = -4
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
      this.uiContext?.animateTo({ duration: 1100, curve: Curve.FastOutSlowIn }, () => {
        this.meteorX = this.formRect.width * 0.88
        this.meteorY = -Math.max(8, Math.round(this.formRect.top * 0.48))
      })
      this.meteorFadeTimerId = setTimeout(() => {
        this.uiContext?.animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
          this.meteorOpacity = 0.0
        })
      }, 1050)
    }

    // Phase 3 (2050ms -> 2690ms): Smooth return ALL THE WAY back into exact resting socket + restore resting card UI
    this.returnTimerId = setTimeout(() => {
      this.uiContext?.animateTo({ duration: 640, curve: Curve.EaseInOut }, () => {
        this.orbDx = 0
        this.orbDy = 0
        this.orbScale = restScale
        this.orbTilt = 0
        this.restingContentOpacity = 1.0
        this.badgeOpacity = 0.0
        this.controlsOffsetY = 10
        this.meteorOpacity = 0.0
      })
    }, 2050)

    // Phase 4 (3020ms): After resting pixel-identically for ~330ms, release overflow cleanly with zero jump!
    this.finishTimerId = setTimeout(() => {
      if (!this.userSwappedPlanet && this.formId.length > 0) {
        formProvider.cancelOverflow(this.formId).catch(() => {})
      }
    }, 3020)
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
    const targetPanel = this.formKind === 'celestial_events_card'
      ? 'calendar' : (this.formKind === 'companion_arc_card' ? 'astro' : 'sky')
    try {
      this.liveFormContext.startAbilityByLiveForm({
        bundleName: 'com.joinother.skyinstrument',
        abilityName: 'QAbility',
        parameters: {
          panel: targetPanel,
          observerPlanet: this.observerPlanet
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
    if (this.formKind === 'celestial_events_card') return false
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

  private visibleEvents(): CompactEventItem[] {
    const all = this.allEvents()
    return this.isTall() ? all.slice(0, 4) : all.slice(0, 2)
  }

  private heroEvent(): CompactEventItem | undefined {
    const all = this.allEvents()
    return all.length > 0 ? all[0] : undefined
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

  private showcaseHeading(): string {
    if (this.formKind === 'celestial_events_card') {
      return this.heroTitle()
    }
    if (this.formKind === 'companion_arc_card') {
      return this.moonPhase.startsWith(this.companionName) ? this.moonPhase : (this.companionName + ' · ' + this.moonPhase)
    }
    return this.observerPlanetName + ' · ' + this.observationSummary
  }

  private showcaseSubline(): string {
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
  buildCompanionRestingCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      Column() {
        if (!this.isWide()) {
          // 2x2 CompanionArcCard mirror
          Column() {
            Row() {
              Text((this.observerPlanet === 'Earth' ? this.companionName : (this.observerPlanetName + '·' + this.companionName)) + ' ↻')
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
          Row({ space: 14 }) {
            Column({ space: 4 }) {
              Column()
                .width(86)
                .height(86)
                .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
              Text((this.companionRole === 'parent-planet' || this.companionRole === 'host')
                ? ('宿主 · ' + this.companionName) : this.moonPhase)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor('#E8F2FF')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .width(100)
            .height('100%')

            Column({ space: 5 }) {
              Row() {
                Column({ space: 1 }) {
                  Text(this.observerPlanetName + ' · 星历弧盘 ↻')
                    .fontSize(11)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#CBE4FF')
                    .height(24)
                    .padding({ left: 8, right: 9 })
                    .backgroundColor('#26FFFFFF')
                    .borderRadius(12)
                    .maxLines(1)
                  Text(this.moonPhase)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#FFFFFF')
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.moonIllumination >= 0 ? (String(Math.round(this.moonIllumination)) + '%') : '—')
                  .fontSize(20)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.companionAccentColor())
              }
              .width('100%')

              HorizonArcView({
                arcWidth: 172,
                arcHeight: 32,
                altitudeDeg: this.companionAlt,
                riseText: this.moonRise,
                setText: this.moonSet,
                accentColor: this.companionAccentColor()
              })

              MiniPhaseStripView({
                phaseAge: this.moonAge,
                nowMs: Date.now(),
                selectedIndex: 0
              })
            }
            .layoutWeight(1)
            .height('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .width('100%')
          .height('100%')
          .padding({ left: 14, right: 15, top: 11, bottom: 10 })
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
                  ? ('天文暗夜 ' + this.darkStart + ' – ' + this.darkEnd)
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

      Column({ space: this.isTall() ? 10 : 6 }) {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Row({ space: 6 }) {
              Text(this.observerPlanetName + ' · 天象预告')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B8D6F8')
                .maxLines(1)
              Text(eventBadgeText(this.heroKind()))
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(eventAccentColor(this.heroKind()))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor('#26FFFFFF')
                .borderRadius(8)
            }
            Text(this.heroTitle())
              .fontSize(this.isTall() ? 17 : 15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                if (this.allEvents().length > 1) {
                  Text('‹').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#E4F1FF')
                    .textAlign(TextAlign.Center).width(30).height(30).backgroundColor('#2CFFFFFF').borderRadius(15)
                }
                Text(this.heroCountdown())
                  .fontSize(this.isTall() ? 20 : 17)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(eventAccentColor(this.heroKind()))
                  .maxLines(1)
                if (this.allEvents().length > 1) {
                  Text('›').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#E4F1FF')
                    .textAlign(TextAlign.Center).width(30).height(30).backgroundColor('#2CFFFFFF').borderRadius(15)
                }
              }
              .alignItems(VerticalAlign.Center)

              if (this.heroAtMs() > 0) {
                Text(formatShortDateZh(this.heroAtMs())).fontSize(10).fontColor('#9ABCE0').maxLines(1)
              }
            }
            .alignItems(HorizontalAlign.End)

            // Exact top-right orb socket placeholder
            Column()
              .width(this.isTall() ? 50 : 36)
              .height(this.isTall() ? 50 : 36)
              .onAreaChange((_oldArea: Area, newArea: Area) => this.captureSlotArea(newArea))
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')

        if (this.visibleEvents().length > 0) {
          Column({ space: this.isTall() ? 9 : 5 }) {
            ForEach(this.visibleEvents(), (ev: CompactEventItem) => {
              Row({ space: 7 }) {
                Circle().width(6).height(6).fill(eventAccentColor(ev.kind))
                Text(ev.title)
                  .fontSize(this.isTall() ? 13 : 12)
                  .fontColor('#EEF5FF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(formatShortDateZh(ev.at)).fontSize(10).fontColor('#96B6DA').maxLines(1)
                Text(this.isReminded(ev.id) ? '★ 已约' : '提醒')
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isReminded(ev.id) ? '#1B1404' : '#EAF4FF')
                  .textAlign(TextAlign.Center)
                  .constraintSize({ minWidth: 58 })
                  .height(this.isTall() ? 32 : 28)
                  .padding({ left: 10, right: 10 })
                  .backgroundColor(this.isReminded(ev.id) ? '#FFD166' : '#3AFFFFFF')
                  .borderRadius(16)
              }
              .width('100%')
              .padding({ left: 11, right: 7, top: this.isTall() ? 7 : 4, bottom: this.isTall() ? 7 : 4 })
              .backgroundColor('#22FFFFFF')
              .borderRadius(12)
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
          .padding({ left: 12, right: 12, top: 9, bottom: 9 })
          .backgroundColor('#1EFFFFFF')
          .borderRadius(12)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 15, right: 14, top: 12, bottom: 11 })
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
        Text(this.observerPlanetName)
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
      } else if (this.formKind === 'companion_arc_card') {
        this.buildCompanionRestingCard()
      } else if (this.formKind === 'celestial_events_card') {
        this.buildEventsRestingCard()
      } else {
        this.buildSkyWindowRestingCard()
      }

      // 2. Overflow Layer: Borderless native-resolution 3D Orb anchored at exact resting socket!
      // Outer Stack handles pure world-space translation; inner Stack handles scale/rotate around exact orb center.
      Stack({ alignContent: Alignment.Center }) {
        Stack({ alignContent: Alignment.Center }) {
          CelestialOrbView({
            orbBody: this.orbBody,
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
