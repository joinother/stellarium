import { common } from '@kit.AbilityKit'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { nextCyclePlanet } from './AstronomyCardData'
import {
  readFormConfig,
  resolveCardDataForForm,
  writeFormConfig,
  writeFormTimeOffset
} from './FormStoreHelper'
import {
  CelestialOrbView,
  StarfieldLayer,
  eventAccentColor,
  orbGlowColor
} from './WidgetVisuals'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyLiveFormPage'

@Entry
@Component
struct SkyLiveFormPage {
  @State orbScale: number = 1.0
  @State orbLiftY: number = 0.0
  @State orbTilt: number = 0.0
  @State haloOpacity: number = 0.35
  @State badgeOpacity: number = 0.0
  @State meteorX: number = -120
  @State meteorY: number = 70
  @State meteorOpacity: number = 0.0

  // Reactive world state so '↻ 换一颗星' in floating_orb_card live-morphs mid-overflow!
  @State observerPlanet: string = 'Earth'
  @State observerPlanetName: string = '地球'
  @State companionName: string = '月球'
  @State orbBody: string = 'moon'
  @State moonPhase: string = '今夜月相'
  @State moonIllumination: number = 72
  @State moonAge: number = 10
  @State observationSummary: string = '暗夜观测'
  @State nextEventTitle: string = ''
  @State nextEventCountdown: string = ''
  @State nextEventKind: string = 'sky'
  @State skyHexTop: string = '#070E22'
  @State skyHexHorizon: string = '#172C52'

  private uiContext: UIContext | undefined = undefined
  private liveFormContext: common.LiveFormExtensionContext | undefined = undefined
  private formId: string = ''
  private formKind: string = 'sky_window_card'
  private formRect: formInfo.Rect = { left: 0, top: 0, width: 160, height: 160 }
  private formBorderRadius: number = 22

  private applySnapshotRecord(snap: Record<string, string>): void {
    this.observerPlanet = snap['observerPlanet'] ?? 'Earth'
    this.observerPlanetName = snap['observerPlanetName'] ?? '地球'
    this.companionName = snap['companionName'] ?? '月球'
    this.orbBody = snap['orbBody'] ?? 'moon'
    this.moonPhase = snap['moonPhase'] ?? '今夜月相'
    this.moonIllumination = Number(snap['moonIllumination'] ?? '72')
    this.moonAge = Number(snap['moonAge'] ?? '10')
    this.observationSummary = snap['observationSummary'] ?? '暗夜观测'
    this.nextEventTitle = snap['nextEventTitle'] ?? ''
    this.nextEventCountdown = snap['nextEventCountdown'] ?? ''
    this.nextEventKind = snap['nextEventKind'] ?? 'sky'
    if (/^#[0-9A-Fa-f]{6}$/.test(snap['skyHexTop'] ?? '')) this.skyHexTop = snap['skyHexTop']
    if (/^#[0-9A-Fa-f]{6}$/.test(snap['skyHexHorizon'] ?? '')) this.skyHexHorizon = snap['skyHexHorizon']
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
  }

  private targetOrbScale(): number {
    // Keep scale generous yet guaranteed inside overflow canvas without clipping orb or halo
    if (this.isBorderlessFloating()) return 1.24
    return 1.32
  }

  private safeOrbLiftY(): number {
    // Overflow window top is y = 0; card top is y = formRect.top.
    // Orb center starts at cy = formRect.top + formRect.height * 0.5 (for floating_orb, slightly higher).
    // Ensure top of scaled orb + glow pad stays >= 12vp below y = 0 so NOTHING is ever clipped!
    const orbSize = this.baseOrbSize()
    const scale = this.targetOrbScale()
    const scaledHalfWithHalo = (orbSize * 1.18 * scale) * 0.5
    const startCenterY = this.formRect.top + this.formRect.height * 0.5
    const desiredTopPadding = 10
    const maxUpwardTravel = Math.max(8, startCenterY - scaledHalfWithHalo - desiredTopPadding)
    const desiredTravel = this.isBorderlessFloating()
      ? Math.round(this.formRect.height * 0.24)
      : Math.round(this.formRect.height * 0.30)
    return -Math.round(Math.min(desiredTravel, maxUpwardTravel))
  }

  private runOverflowShowcase(): void {
    // Choreographed <= 3.4s overflow animation (within HarmonyOS 3500ms hard cap):
    // Guaranteed zero clipping at top edge of overflow window while breaking above card border!
    const liftDistance = this.safeOrbLiftY()
    const peakScale = this.targetOrbScale()

    if (this.formKind === 'celestial_events_card') {
      this.meteorX = -this.formRect.width * 0.12
      this.meteorY = this.formRect.height * 0.58
      this.meteorOpacity = 0.0
      this.uiContext?.animateTo({ duration: 220, curve: Curve.EaseIn }, () => {
        this.meteorOpacity = 1.0
        this.badgeOpacity = 1.0
        this.haloOpacity = 1.0
      })
      this.uiContext?.animateTo({ duration: 1200, curve: Curve.FastOutSlowIn }, () => {
        this.meteorX = this.formRect.width * 0.88
        this.meteorY = -Math.max(12, Math.round(this.formRect.top * 0.55))
        this.orbScale = peakScale
        this.orbLiftY = liftDistance
        this.orbTilt = -5
      })
      setTimeout(() => {
        this.uiContext?.animateTo({ duration: 750, curve: Curve.EaseOut }, () => {
          this.meteorOpacity = 0.0
          this.orbScale = 1.0
          this.orbLiftY = 0
          this.orbTilt = 0
          this.haloOpacity = 0.35
        })
      }, 2450)
      return
    }

    this.uiContext?.animateTo({ duration: 780, curve: Curve.FastOutSlowIn }, () => {
      this.orbScale = peakScale
      this.orbLiftY = liftDistance
      this.orbTilt = -5
      this.haloOpacity = 0.95
      this.badgeOpacity = 1.0
    })

    setTimeout(() => {
      this.uiContext?.animateTo({ duration: 700, curve: Curve.EaseInOut }, () => {
        this.orbScale = 1.0
        this.orbLiftY = 0
        this.orbTilt = 0
        this.haloOpacity = 0.35
        this.badgeOpacity = 0.0
      })
    }, 2650)
  }

  private cycleFloatingPlanetInPlace(): void {
    if (this.liveFormContext === undefined || this.formId.length === 0) return
    const cfg = readFormConfig(this.liveFormContext, this.formId)
    const nextPlanet = nextCyclePlanet(this.observerPlanet)
    cfg.planetMode = nextPlanet
    writeFormConfig(this.liveFormContext, this.formId, cfg)
    writeFormTimeOffset(this.liveFormContext, this.formId, 0)
    const nextData = resolveCardDataForForm(this.liveFormContext, this.formId, Date.now())

    // Morph the levitating orb smoothly right above the user's wallpaper (strictly within unclipped scale!)
    this.uiContext?.animateTo({ duration: 260, curve: Curve.FastOutSlowIn }, () => {
      this.applySnapshotRecord(nextData)
      this.orbTilt = this.orbTilt === -5 ? 6 : -5
      this.orbScale = this.targetOrbScale()
      this.orbLiftY = this.safeOrbLiftY()
    })

    // Sync the resting desktop widget so the newly chosen planet persists after overflow ends
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
      // Must be called directly inside the click handler (no setTimeout), per LiveFormExtensionContext spec.
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

  private showcaseCaption(): string {
    if (this.formKind === 'celestial_events_card') {
      return this.nextEventTitle.length > 0 ? (this.nextEventTitle + ' · ' + this.nextEventCountdown) : (this.observerPlanetName + ' · 天象预告')
    }
    if (this.formKind === 'companion_arc_card') {
      return this.companionName + ' · ' + this.moonPhase
    }
    return this.observerPlanetName + ' · ' + this.observationSummary
  }

  private isBorderlessFloating(): boolean {
    return this.formKind === 'floating_orb_card'
  }

  private baseOrbSize(): number {
    if (this.isBorderlessFloating()) {
      const minSide = Math.min(this.formRect.width, this.formRect.height)
      return Math.max(88, Math.min(102, Math.round(minSide * 0.62)))
    }
    const minSide = Math.min(this.formRect.width, this.formRect.height)
    return Math.max(62, Math.min(92, Math.round(minSide * 0.50)))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Card backdrop aligned pixel-for-pixel with inactive card rect & corner radius
      //    (For API 22 transparent backplate 'floating_orb_card', keep backdrop completely transparent
      //     and reveal two generous finger-friendly glass pills: '↻ 换星' and '✦ 星图'!)
      if (this.isBorderlessFloating()) {
        Column({ space: 6 }) {
          Blank()
          Row({ space: 5 }) {
            Circle()
              .width(5)
              .height(5)
              .fill('#8AD4FF')
            Text(this.showcaseCaption())
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F9FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor('#AE081124')
          .borderRadius(12)
          .opacity(this.badgeOpacity)

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
          .opacity(this.badgeOpacity)
        }
        .width(this.formRect.width)
        .height(this.formRect.height)
        .offset({ x: this.formRect.left, y: this.formRect.top })
        .padding({ bottom: 4 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.launchAppDirect())
      } else {
        Stack({ alignContent: Alignment.TopStart }) {
          StarfieldLayer({ sunAlt: -20, themeStyle: 'deep' })

          // Bottom caption inside card body
          Column() {
            Blank()
            Row({ space: 6 }) {
              Circle()
                .width(6)
                .height(6)
                .fill(this.formKind === 'celestial_events_card' ? eventAccentColor(this.nextEventKind) : '#8AD4FF')
              Text(this.showcaseCaption())
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor('#F4F8FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 6, bottom: 10 })
            .opacity(this.badgeOpacity)
          }
          .width('100%')
          .height('100%')
        }
        .width(this.formRect.width)
        .height(this.formRect.height)
        .offset({ x: this.formRect.left, y: this.formRect.top })
        .borderRadius(this.formBorderRadius)
        .clip(true)
        .linearGradient({
          angle: 170,
          colors: [
            [this.skyHexTop, 0.0],
            [this.skyHexHorizon, 1.0]
          ]
        })
        .border({ width: 0.8, color: '#38FFFFFF' })
        .onClick(() => this.launchAppDirect())
      }

      // 2. Overflow Layer: 3D Celestial Orb rising cleanly inside the unclipped overflow zone
      Stack({ alignContent: Alignment.Center }) {
        // Soft atmospheric corona sized cleanly inside overflow bounds (no flat top edge clipping)
        Circle()
          .width(this.baseOrbSize() * 1.18)
          .height(this.baseOrbSize() * 1.18)
          .fill(Color.Transparent)
          .radialGradient({
            center: ['50%', '50%'],
            radius: this.baseOrbSize() * 0.59,
            colors: [
              [orbGlowColor(this.orbBody), 0.0],
              ['#00000000', 1.0]
            ]
          })
          .opacity(this.haloOpacity)

        CelestialOrbView({
          orbBody: this.orbBody,
          orbSize: this.baseOrbSize(),
          showPhase: this.orbBody === 'moon' || this.orbBody === 'earth',
          illumination: Number.isFinite(this.moonIllumination) ? this.moonIllumination : 72,
          phaseAge: Number.isFinite(this.moonAge) ? this.moonAge : 10,
          glowIntensity: 0
        })
      }
      .width(this.formRect.width)
      .height(this.formRect.height)
      .offset({ x: this.formRect.left, y: this.formRect.top })
      .scale({ x: this.orbScale, y: this.orbScale })
      .translate({ y: this.orbLiftY })
      .rotate({ angle: this.orbTilt })
      .hitTestBehavior(HitTestMode.None)
      .onAppear(() => this.runOverflowShowcase())

      // 3. Overflow Shooting Meteor Streak (for celestial_events_card)
      if (this.formKind === 'celestial_events_card') {
        Row({ space: 0 }) {
          Column()
            .width(104)
            .height(3.5)
            .borderRadius(2)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: [
                ['#00FFFFFF', 0.0],
                ['#AAE0F4FF', 0.65],
                ['#FFFFFFFF', 1.0]
              ]
            })
          Column()
            .width(9)
            .height(9)
            .borderRadius(4.5)
            .backgroundColor('#FFFFFF')
            .shadow({ radius: 14, color: '#99E0FF', offsetX: 0, offsetY: 0 })
        }
        .alignItems(VerticalAlign.Center)
        .rotate({ angle: -26 })
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
