import {
  focusTargetForCard,
  isLightTextColor,
  routePlanetForCard,
  solarStageFromAltitude
} from './AstronomyCardData'
import { CelestialOrbView } from './WidgetVisuals'

const floatingOrbStorage: LocalStorage = new LocalStorage()

// API 22 Transparent Backplate Card:
// A photorealistic 3D celestial globe (real lunar phase / Earthphase / ringed Saturn / Mars / Jupiter / Neptune)
// floats directly over the user's desktop wallpaper with zero rectangular frame.
// Non-transparent visual area is ~44% of the 2*2 slot (well above the 10% platform minimum).
@Entry(floatingOrbStorage)
@Component
struct FloatingOrbCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('observerPlanetName') observerPlanetName: string = '地球'
  @LocalStorageProp('companionName') companionName: string = '月球'
  @LocalStorageProp('companionEnglish') companionEnglish: string = 'Moon'
  @LocalStorageProp('orbBody') orbBody: string = 'moon'
  @LocalStorageProp('moonPhase') moonPhase: string = '今夜月相'
  @LocalStorageProp('moonIllumination') moonIllumination: string = '76'
  @LocalStorageProp('moonAge') moonAge: string = '11'
  @LocalStorageProp('moonSummary') moonSummary: string = '76% 照明'
  @LocalStorageProp('observationSummary') observationSummary: string = '暗夜观测'
  @LocalStorageProp('sunAlt') sunAlt: string = '-18.0'
  @LocalStorageProp('sunRise') sunRise: string = '—'
  @LocalStorageProp('sunSet') sunSet: string = '—'
  @LocalStorageProp('solarStage') solarStage: string = ''
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'
  @LocalStorageProp('textColor') textColor: string = '#F5F9FF'

  private numericIllum(): number {
    const v = Number(this.moonIllumination)
    return Number.isFinite(v) ? v : -1
  }

  private numericAge(): number {
    const v = Number(this.moonAge)
    return Number.isFinite(v) ? v : 11
  }

  private showPhaseShadow(): boolean {
    const body = this.orbBody.trim().toLowerCase()
    return body === 'moon' || body === 'earth'
  }

  private safeTextColor(): string {
    return /^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(this.textColor) ? this.textColor : '#F5F9FF'
  }

  private contrastShadowColor(): string {
    return isLightTextColor(this.safeTextColor()) ? '#8C000000' : '#70FFFFFF'
  }

  private captionText(): string {
    const body = this.orbBody.trim().toLowerCase()
    if (body === 'sun') {
      const alt = Number(this.sunAlt)
      const stage = this.solarStage.length > 0 ? this.solarStage : solarStageFromAltitude(alt)
      if (Number.isFinite(alt)) {
        const sign = alt >= 0 ? '+' : ''
        return '太阳 · ' + stage + ' ' + sign + String(Math.round(alt)) + '°'
      }
      return '太阳 · 升 ' + this.sunRise + ' 落 ' + this.sunSet
    }
    if (body === 'moon') {
      const pct = this.numericIllum() >= 0 ? (' · ' + String(Math.round(this.numericIllum())) + '%') : ''
      return this.moonPhase + pct
    }
    if (this.observerPlanet === 'Moon') {
      const pct = this.numericIllum() >= 0 ? (' · ' + String(Math.round(this.numericIllum())) + '%') : ''
      return this.moonPhase + pct
    }
    if (this.observerPlanet === 'Titan') {
      return '土星 · ' + this.moonPhase
    }
    return this.observerPlanetName + ' · ' + this.observationSummary
  }

  private openSky(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'sky',
        observerPlanet: routePlanetForCard(this.observerPlanet),
        target: focusTargetForCard(this.observerPlanet, this.companionEnglish, this.orbBody),
        landingTitle: this.captionText(),
        landingSource: 'card'
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openSky()
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'floating_orb_card'
      }
    })
  }

  build() {
    Column({ space: 4 }) {
      // Generous 3D celestial orb floating freely over wallpaper (~42% non-transparent coverage)
      // Do NOT apply rectangular .shadow() on the container — keep the orb silhouette 100% borderless.
      Stack({ alignContent: Alignment.Center }) {
        CelestialOrbView({
          orbBody: this.orbBody,
          orbSize: 110,
          showPhase: this.showPhaseShadow(),
          illumination: this.numericIllum(),
          phaseAge: this.numericAge(),
          glowIntensity: 0.9
        })
      }
      .width(112)
      .height(112)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.triggerOverflowOrOpen())

      // Single crisp adaptive-color floating telemetry caption (follows HOST_BG_INVERSE_COLOR_KEY)
      Text(this.captionText())
        .fontSize(11)
        .lineHeight(15)
        .height(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.safeTextColor())
        .textShadow({ radius: 5, color: this.contrastShadowColor(), offsetX: 0, offsetY: 1 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 6, right: 6 })
        .onClick(() => this.openSky())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Transparent)
    .onClick(() => this.openSky())
  }
}
