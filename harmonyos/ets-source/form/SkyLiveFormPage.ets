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

  private runOverflowShowcase(): void {
    // Choreographed <= 3.1s overflow animation (within HarmonyOS 3500ms hard cap):
    // Lift the 3D celestial orb boldly past the card's top border into the overflow zone!
    const liftDistance = -Math.round(this.formRect.height * 0.44)

    if (this.formKind === 'celestial_events_card') {
      this.meteorX = -this.formRect.width * 0.15
      this.meteorY = this.formRect.height * 0.62
      this.meteorOpacity = 0.0
      this.uiContext?.animateTo({ duration: 220, curve: Curve.EaseIn }, () => {
        this.meteorOpacity = 1.0
        this.badgeOpacity = 1.0
        this.haloOpacity = 1.0
      })
      this.uiContext?.animateTo({ duration: 1250, curve: Curve.FastOutSlowIn }, () => {
        this.meteorX = this.formRect.width * 0.92
        this.meteorY = -Math.max(22, this.formRect.top * 0.65)
        this.orbScale = 1.48
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
      }, 2050)
      return
    }

    this.uiContext?.animateTo({ duration: 950, curve: Curve.FastOutSlowIn }, () => {
      this.orbScale = 1.48
      this.orbLiftY = liftDistance
      this.orbTilt = -6
      this.haloOpacity = 1.0
      this.badgeOpacity = 1.0
    })

    setTimeout(() => {
      this.uiContext?.animateTo({ duration: 850, curve: Curve.EaseInOut }, () => {
        this.orbScale = 1.0
        this.orbLiftY = 0
        this.orbTilt = 0
        this.haloOpacity = 0.4
        this.badgeOpacity = 0.0
      })
    }, 2200)
  }

  private cycleFloatingPlanetInPlace(): void {
    if (this.liveFormContext === undefined || this.formId.length === 0) return
    const cfg = readFormConfig(this.liveFormContext, this.formId)
    const nextPlanet = nextCyclePlanet(this.observerPlanet)
    cfg.planetMode = nextPlanet
    writeFormConfig(this.liveFormContext, this.formId, cfg)
    writeFormTimeOffset(this.liveFormContext, this.formId, 0)
    const nextData = resolveCardDataForForm(this.liveFormContext, this.formId, Date.now())

    // Morph the levitating orb smoothly right above the user's wallpaper!
    this.uiContext?.animateTo({ duration: 280, curve: Curve.FastOutSlowIn }, () => {
      this.applySnapshotRecord(nextData)
      this.orbTilt = this.orbTilt === -6 ? 8 : -6
      this.orbScale = 1.54
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
    if (this.isBorderlessFloating()) return 112
    const minSide = Math.min(this.formRect.width, this.formRect.height)
    return Math.max(62, Math.min(96, Math.round(minSide * 0.52)))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 1. Card backdrop aligned pixel-for-pixel with inactive card rect & corner radius
      //    (For API 22 transparent backplate 'floating_orb_card', keep backdrop completely transparent
      //     and reveal two floating glass pills: '↻ 换星' and '✦ 星图'!)
      if (this.isBorderlessFloating()) {
        Column({ space: 6 }) {
          Blank()
          Row({ space: 5 }) {
            Circle()
              .width(5)
              .height(5)
              .fill('#8AD4FF')
            Text(this.showcaseCaption())
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor('#F5F9FF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .padding({ left: 9, right: 9, top: 4, bottom: 4 })
          .backgroundColor('#A8081124')
          .borderRadius(11)
          .opacity(this.badgeOpacity)

          Row({ space: 6 }) {
            Text('↻ 换星')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#C81B3A70')
              .borderRadius(12)
              .onClick(() => this.cycleFloatingPlanetInPlace())

            Text('✦ 星图')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#EAF4FF')
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#B8091226')
              .borderRadius(12)
              .onClick(() => this.launchAppDirect())
          }
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

      // 2. Overflow Layer: 3D Celestial Orb rising ABOVE the card's top border!
      Stack({ alignContent: Alignment.Center }) {
        // Luminous corona expanding in the overflow canvas
        Circle()
          .width(this.baseOrbSize() * 1.55)
          .height(this.baseOrbSize() * 1.55)
          .fill(Color.Transparent)
          .radialGradient({
            center: ['50%', '50%'],
            radius: this.baseOrbSize() * 0.78,
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
          glowIntensity: 0.9
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
