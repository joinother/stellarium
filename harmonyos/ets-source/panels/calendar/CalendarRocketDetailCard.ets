import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { AstronomyCalendarEvent } from '../../state/AstronomyCalendarEvent'
import {
  RocketDebrisInfo,
  RocketSimulationData,
  RocketSimulationRequest,
  formatBeijingTimeFromIso,
  formatPropellantTag,
  formatTwilightTag
} from '../../state/RocketLaunchTypes'
import { RocketLaunchSimHost } from './RocketLaunchSimModal'
import { RocketSkyTrackCanvas } from './RocketSkyTrackCanvas'
import { RocketPetalGlobeModal } from './RocketPetalGlobeModal'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 内嵌在天象日历统一事件详情页中的「火箭发射弹道与火箭云卡片」
// 与日食卡片 CalendarEclipseMapCard、行星大距卡片 CalendarElongationOrbitCard 完全一致的一等日历体验。
@Component
export struct CalendarRocketDetailCard {
  @Prop @Watch('onEventChanged') event: AstronomyCalendarEvent | undefined = undefined
  @Prop language: string = 'zh'
  @Prop earthMapUri: string = ''
  @Prop onlineMapAllowed: boolean = false
  host: RocketLaunchSimHost = {
    loadCatalog: () => {},
    runSimulation: () => {},
    previewInSky: () => {}
  }

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private simulation: RocketSimulationData | undefined = undefined
  @State private loading: boolean = true
  @State private timeOffsetMin: number = 0
  @State private globeOpen: boolean = false
  private offsetTimer: number = -1

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private t(zh: string, en: string): string {
    return this.isZh() ? zh : en
  }

  aboutToAppear(): void {
    this.runForEvent()
  }

  aboutToDisappear(): void {
    if (this.offsetTimer >= 0) {
      clearTimeout(this.offsetTimer)
      this.offsetTimer = -1
    }
  }

  private onEventChanged(): void {
    this.timeOffsetMin = 0
    this.runForEvent()
  }

  private runForEvent(): void {
    const ev = this.event
    if (!ev) return
    this.loading = true
    const req: RocketSimulationRequest = ev.rocketPresetId && ev.rocketPresetId.length > 0
      ? {
          presetId: ev.rocketPresetId,
          timeOffsetMin: this.timeOffsetMin,
          dispersionSamples: 120,
          includeFullTrack: true
        }
      : {
          siteId: ev.rocketSiteId ?? 'tslc',
          vehicleId: ev.rocketVehicleId ?? 'cz6a',
          launchTimeUtc: ev.rocketLaunchTimeUtc ?? new Date(ev.at).toISOString(),
          azimuthDeg: ev.rocketAzimuthDeg,
          timeOffsetMin: this.timeOffsetMin,
          dispersionSamples: 120,
          includeFullTrack: true
        }
    this.host.runSimulation(req, (res: RocketSimulationData | undefined) => {
      this.loading = false
      if (res && res.ok) {
        this.simulation = res
      }
    })
  }

  private scheduleOffset(val: number): void {
    this.timeOffsetMin = Math.round(val)
    if (this.offsetTimer >= 0) clearTimeout(this.offsetTimer)
    this.offsetTimer = setTimeout(() => {
      this.offsetTimer = -1
      this.runForEvent()
    }, 90)
  }

  private scoreColor(grade: string): string {
    if (grade === 'excellent') return '#3CE886'
    if (grade === 'good') return '#5AD4FF'
    if (grade === 'fair') return '#FFC14D'
    if (grade === 'flame_only') return '#FF8852'
    return '#94A3BD'
  }

  @Builder
  private globeModalBuilder() {
    RocketPetalGlobeModal({
      simulation: this.simulation,
      language: this.language,
      earthMapUri: this.earthMapUri,
      onlineMapAllowed: this.onlineMapAllowed,
      onClose: () => { this.globeOpen = false }
    })
  }

  build() {
    Column({ space: 10 }) {
      if (this.loading && this.simulation === undefined) {
        Row({ space: 8 }) {
          LoadingProgress().width(16).height(16).color(this.c.accent)
          Text(this.t('正在计算 3-DOF 弹道与本地火箭云可见度…', 'Computing 3-DOF trajectory & plume visibility…'))
            .fontSize(12).fontColor(this.c.sub)
        }.width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
      }

      if (this.simulation !== undefined) {
        // Plume score + metrics + time-offset sensitivity slider
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Column({ space: 2 }) {
              Text(String(this.simulation.summary.plumeScore))
                .fontSize(24).fontWeight(FontWeight.Bold)
                .fontColor(this.scoreColor(this.simulation.summary.plumeGrade))
              Text(this.t('火箭云指数', 'Plume')).fontSize(9).fontColor(this.c.sub)
            }
              .width(64).padding({ top: 5, bottom: 5 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .alignItems(HorizontalAlign.Center)

            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(this.isZh() ? this.simulation.summary.plumeGradeZh : this.simulation.summary.plumeGradeEn)
                  .fontSize(14).fontWeight(FontWeight.Bold)
                  .fontColor(this.scoreColor(this.simulation.summary.plumeGrade))
                Text(formatPropellantTag(this.simulation.vehicle.propellantClass, this.isZh()))
                  .fontSize(9).fontColor(this.c.text)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_PILL)
              }
              Text(this.isZh() ? this.simulation.summary.plumeAdviceZh : this.simulation.summary.plumeAdviceEn)
                .fontSize(11).fontColor(this.c.sub).maxLines(3)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').alignItems(VerticalAlign.Center)

          Row({ space: 6 }) {
            this.miniMetric(this.t('本地暮光', 'Twilight'), formatTwilightTag(this.simulation.observer.twilightStage, this.simulation.observer.sunAltDeg, this.isZh()))
            this.miniMetric(this.t('最大仰角', 'Max Alt'), this.simulation.summary.visibleFromObserver ? `${this.simulation.summary.maxAltDeg.toFixed(1)}°` : this.t('不可见', 'Hidden'))
            this.miniMetric(this.t('跃出地影', 'Sunlit'), this.simulation.summary.sunlitEntrySec >= 0 ? `${this.simulation.summary.sunlitEntryAltKm.toFixed(0)}km` : this.t('本影', 'Umbra'))
            this.miniMetric(this.t('焦段', 'Lens'), `${this.simulation.summary.recommendedFocalMm}mm`)
          }.width('100%')

          Column({ space: 2 }) {
            Row() {
              Text(this.t('发令时间偏移（测试推迟/提前对火箭云影响）', 'Launch Offset (Test Twilight Window)'))
                .fontSize(10).fontColor(this.c.sub).layoutWeight(1)
              Text((this.timeOffsetMin > 0 ? '+' : '') + `${this.timeOffsetMin} min`)
                .fontSize(10).fontWeight(FontWeight.Bold).fontColor(this.c.accent)
            }.width('100%')
            Slider({ value: this.timeOffsetMin, min: -60, max: 60, step: 5 })
              .width('100%')
              .onChange((val: number) => { this.scheduleOffset(val) })
          }.width('100%')
        }
          .width('100%').padding(12)
          .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
          .border({ width: 0.8, color: this.c.border })

        // Inline Az-Alt Sky Track chart (Reference Img 4)
        RocketSkyTrackCanvas({
          simulation: this.simulation,
          language: this.language
        })

        // Inline NOTAM / Debris summary + 3D Globe & Sky Preview triggers
        Column({ space: 6 }) {
          if (this.simulation.notam && this.simulation.notam.valid) {
            Text(`${this.t('航警落区', 'NOTAM')} ${this.simulation.notam.notamId} · ${this.t('反演射向', 'Az')} ${this.simulation.notam.invertedAzimuthDeg.toFixed(1)}° · ${this.t('距发射场', 'Range')} ${this.simulation.notam.downrangeKm.toFixed(0)} km`)
              .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#FF8A80')
          }
          ForEach(this.simulation.debris, (deb: RocketDebrisInfo) => {
            Text(`${this.isZh() ? deb.labelZh : deb.labelEn}：${deb.downrangeKm.toFixed(0)} km (${formatBeijingTimeFromIso(deb.impactTimeUtc).slice(11, 19)})${deb.insideNotam ? ' · 航警区内 ✓' : ''}`)
              .fontSize(10).fontColor(this.c.sub)
          }, (deb: RocketDebrisInfo) => deb.kind + '_' + deb.impactTimeSec)

          Row({ space: 8 }) {
            Text(this.t('花瓣 3D 卫星地球与落区 ↗', 'Petal 3D Satellite Globe ↗'))
              .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.c.onAccent)
              .textAlign(TextAlign.Center).layoutWeight(1)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.globeOpen = true })

            Text(this.t('星图 3D 预演', 'Sky Preview'))
              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text)
              .padding({ left: 14, right: 14, top: 9, bottom: 9 })
              .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_PILL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                if (this.simulation !== undefined) {
                  this.host.previewInSky(this.simulation)
                }
              })
          }.width('100%').padding({ top: 4 })
        }
          .width('100%').padding(12)
          .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
          .border({ width: 0.8, color: this.c.border })
          .alignItems(HorizontalAlign.Start)
      }
    }
      .width('100%')
      .bindContentCover($$this.globeOpen, this.globeModalBuilder(), {
        modalTransition: ModalTransition.DEFAULT
      })
  }

  @Builder
  private miniMetric(label: string, val: string) {
    Column({ space: 2 }) {
      Text(label).fontSize(9).fontColor(this.c.sub).maxLines(1)
      Text(val).fontSize(10).fontWeight(FontWeight.Bold).fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .layoutWeight(1).padding({ left: 4, right: 4, top: 5, bottom: 5 })
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      .alignItems(HorizontalAlign.Center)
  }
}
