import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import {
  RocketCatalogData,
  RocketDebrisInfo,
  RocketFlightEventInfo,
  RocketLaunchPresetInfo,
  RocketLaunchSiteInfo,
  RocketSimulationData,
  RocketSimulationRequest,
  RocketVehicleInfo,
  formatBeijingTimeFromIso,
  formatPropellantTag,
  formatTwilightTag
} from '../../state/RocketLaunchTypes'
import { RocketSkyTrackCanvas } from './RocketSkyTrackCanvas'
import { RocketPetalGlobeModal } from './RocketPetalGlobeModal'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

export interface RocketLaunchSimHost {
  loadCatalog(onDone: (catalog: RocketCatalogData | undefined) => void): void
  runSimulation(req: RocketSimulationRequest, onDone: (sim: RocketSimulationData | undefined) => void): void
  previewInSky(sim: RocketSimulationData): void
}

@Component
export struct RocketLaunchSimModal {
  @Prop language: string = 'zh'
  @Prop earthMapUri: string = ''
  @Prop onlineMapAllowed: boolean = false
  host: RocketLaunchSimHost = {
    loadCatalog: () => {},
    runSimulation: () => {},
    previewInSky: () => {}
  }
  onClose: () => void = () => {}

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private catalog: RocketCatalogData | undefined = undefined
  @State private simulation: RocketSimulationData | undefined = undefined
  @State private loading: boolean = true
  @State private errorMsg: string = ''

  @State private selectedPresetId: string = 'preset_cz6a_taiyuan_twilight'
  @State private customMode: boolean = false
  @State private customSiteId: string = 'tslc'
  @State private customVehicleId: string = 'cz6a'
  @State private customAzimuthDeg: number = 255
  @State private customNotamText: string = ''
  @State private includeDispersion: boolean = true
  @State private timeOffsetMin: number = 0
  @State private activeTab: number = 0 // 0=天空轨迹与火箭云, 1=落区与残骸, 2=飞行事件
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
    this.loading = true
    this.host.loadCatalog((cat: RocketCatalogData | undefined) => {
      this.catalog = cat
      if (cat && cat.presets.length > 0) {
        this.selectedPresetId = cat.presets[0].id
        this.customSiteId = cat.presets[0].siteId
        this.customVehicleId = cat.presets[0].vehicleId
        this.customAzimuthDeg = Math.round(cat.presets[0].azimuthDeg)
      }
      this.triggerSimulation()
    })
  }

  aboutToDisappear(): void {
    if (this.offsetTimer >= 0) {
      clearTimeout(this.offsetTimer)
      this.offsetTimer = -1
    }
  }

  private triggerSimulation(): void {
    this.loading = true
    this.errorMsg = ''
    const req: RocketSimulationRequest = this.customMode
      ? {
          siteId: this.customSiteId,
          vehicleId: this.customVehicleId,
          azimuthDeg: this.customNotamText.trim().length > 0 ? undefined : this.customAzimuthDeg,
          notamText: this.customNotamText.trim().length > 0 ? this.customNotamText.trim() : undefined,
          timeOffsetMin: this.timeOffsetMin,
          dispersionSamples: this.includeDispersion ? 120 : 0,
          includeFullTrack: true
        }
      : {
          presetId: this.selectedPresetId,
          timeOffsetMin: this.timeOffsetMin,
          dispersionSamples: this.includeDispersion ? 120 : 0,
          includeFullTrack: true
        }
    this.host.runSimulation(req, (res: RocketSimulationData | undefined) => {
      this.loading = false
      if (res && res.ok) {
        this.simulation = res
        if (this.customMode) {
          this.customAzimuthDeg = Math.round(res.launchAzimuthDeg)
        }
      } else {
        this.errorMsg = (res && res.error) ? res.error : this.t('弹道仿真计算失败，请重试', 'Trajectory simulation failed')
      }
    })
  }

  private scheduleOffsetSimulation(minutes: number): void {
    this.timeOffsetMin = Math.round(minutes)
    if (this.offsetTimer >= 0) {
      clearTimeout(this.offsetTimer)
    }
    this.offsetTimer = setTimeout(() => {
      this.offsetTimer = -1
      this.triggerSimulation()
    }, 90)
  }

  private scoreAccentColor(grade: string): string {
    if (grade === 'excellent') return '#3CE886'
    if (grade === 'good') return '#5AD4FF'
    if (grade === 'fair') return '#FFC14D'
    if (grade === 'flame_only') return '#FF8852'
    return '#8E9BB5'
  }

  private dispersionHitSummary(sim: RocketSimulationData): string {
    if (!Array.isArray(sim.dispersion) || sim.dispersion.length === 0) return ''
    let inside = 0
    for (let i = 0; i < sim.dispersion.length; i++) {
      if (sim.dispersion[i][2] === 1) inside++
    }
    const pct = Math.round((inside / sim.dispersion.length) * 100)
    return this.isZh()
      ? `敏感性散布：${inside}/${sim.dispersion.length} (${pct}%) 命中航警危险区`
      : `Dispersion: ${inside}/${sim.dispersion.length} (${pct}%) inside NOTAM`
  }

  @Builder
  globeModalBuilder() {
    RocketPetalGlobeModal({
      simulation: this.simulation,
      language: this.language,
      earthMapUri: this.earthMapUri,
      onlineMapAllowed: this.onlineMapAllowed,
      onClose: () => { this.globeOpen = false }
    })
  }

  private modalBg(): string {
    return this.c.isNight ? '#100608' : '#0B1220'
  }

  private cardBg(): string {
    return this.c.isNight ? '#1D0C10' : '#141F35'
  }

  private innerBg(): string {
    return this.c.isNight ? '#15080B' : '#0E1728'
  }

  build() {
    Column() {
      // Top Header
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(this.t('火箭弹道与火箭云仿真', 'Rocket Trajectory & Plume Sim'))
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.c.textStrong)
          Text(this.t('3-DOF 球面弹道 · 6 类推进剂羽流物理 · 花瓣 3D 卫星地球', '3-DOF Ascent · 6 Propellant Plumes · Petal 3D Globe'))
            .fontSize(11)
            .fontColor(this.c.sub)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)

        Text(this.customMode ? this.t('经典案例', 'Presets') : this.t('自定义/NOTAM', 'Custom/NOTAM'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.customMode ? this.c.onAccent : this.c.accent)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.customMode ? this.c.accent : this.c.softStrong)
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => {
            this.customMode = !this.customMode
            this.triggerSimulation()
          })

        Text('✕')
          .fontSize(16)
          .fontColor(this.c.sub)
          .padding({ left: 10, right: 6, top: 6, bottom: 6 })
          .onClick(() => { this.onClose() })
      }
        .width('100%')
        .padding({ left: 16, right: 14, top: 14, bottom: 10 })

      // Main Scrollable Body
      Scroll() {
        Column({ space: 12 }) {
          // Mode 1: Preset selector chips
          if (!this.customMode && this.catalog && this.catalog.presets.length > 0) {
            Scroll() {
              Row({ space: 8 }) {
                ForEach(this.catalog.presets, (p: RocketLaunchPresetInfo) => {
                  Column({ space: 3 }) {
                    Text(this.isZh() ? p.badgeZh : p.badgeEn)
                      .fontSize(10)
                      .fontColor(this.selectedPresetId === p.id ? this.c.onAccent : this.c.accent)
                    Text(this.isZh() ? p.titleZh : p.titleEn)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.selectedPresetId === p.id ? this.c.onAccent : this.c.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                    .width(200)
                    .alignItems(HorizontalAlign.Start)
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.selectedPresetId === p.id ? this.c.accent : this.cardBg())
                    .borderRadius(UI_RADIUS_CONTROL)
                    .border({ width: 0.8, color: this.selectedPresetId === p.id ? this.c.accent : this.c.border })
                    .onClick(() => {
                      if (this.selectedPresetId !== p.id) {
                        this.selectedPresetId = p.id
                        this.timeOffsetMin = 0
                        this.triggerSimulation()
                      }
                    })
                }, (p: RocketLaunchPresetInfo) => p.id)
              }
            }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
          }

          // Mode 2: Custom launch site / vehicle / azimuth / NOTAM paste panel
          if (this.customMode && this.catalog) {
            Column({ space: 10 }) {
              Text(this.t('发射场', 'Launch Site')).fontSize(11).fontColor(this.c.sub)
              Scroll() {
                Row({ space: 6 }) {
                  ForEach(this.catalog.sites, (site: RocketLaunchSiteInfo) => {
                    Text(this.isZh() ? site.nameZh : site.nameEn)
                      .fontSize(11)
                      .fontColor(this.customSiteId === site.id ? this.c.onAccent : this.c.text)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .backgroundColor(this.customSiteId === site.id ? this.c.accent : this.c.bg)
                      .borderRadius(UI_RADIUS_PILL)
                      .onClick(() => {
                        this.customSiteId = site.id
                        this.customAzimuthDeg = Math.round(site.defaultAzimuthDeg)
                      })
                  }, (site: RocketLaunchSiteInfo) => site.id)
                }
              }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

              Text(this.t('运载火箭（含 6 类推进剂模型）', 'Launch Vehicle (6 Propellant Models)')).fontSize(11).fontColor(this.c.sub)
              Scroll() {
                Row({ space: 6 }) {
                  ForEach(this.catalog.vehicles, (veh: RocketVehicleInfo) => {
                    Column({ space: 2 }) {
                      Text(this.isZh() ? veh.nameZh : veh.nameEn)
                        .fontSize(11)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.customVehicleId === veh.id ? this.c.onAccent : this.c.text)
                      Text(formatPropellantTag(veh.propellantClass, this.isZh()))
                        .fontSize(9)
                        .fontColor(this.customVehicleId === veh.id ? this.c.onAccent : this.c.sub)
                    }
                      .alignItems(HorizontalAlign.Start)
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .backgroundColor(this.customVehicleId === veh.id ? this.c.accent : this.c.bg)
                      .borderRadius(UI_RADIUS_CONTROL)
                      .onClick(() => { this.customVehicleId = veh.id })
                  }, (veh: RocketVehicleInfo) => veh.id)
                }
              }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

              Row({ space: 8 }) {
                Text(`${this.t('发射方位角', 'Azimuth')}: ${this.customAzimuthDeg}°`)
                  .fontSize(12).fontColor(this.c.text)
                Slider({ value: this.customAzimuthDeg, min: 0, max: 359, step: 1 })
                  .layoutWeight(1)
                  .onChange((val: number) => { this.customAzimuthDeg = Math.round(val) })
              }.width('100%').alignItems(VerticalAlign.Center)

              TextArea({
                text: this.customNotamText,
                placeholder: this.t('可选：粘贴 ICAO NOTAM 报文（自动解析 Q 行圆与 E 行落区多边形并反演发射射向）', 'Optional: Paste ICAO NOTAM text to parse hazard polygon & invert launch azimuth')
              })
                .width('100%')
                .height(72)
                .fontSize(11)
                .fontColor(this.c.text)
                .placeholderColor(this.c.sub)
                .backgroundColor(this.c.bg)
                .borderRadius(UI_RADIUS_CONTROL)
                .onChange((val: string) => { this.customNotamText = val })

              Row({ space: 10 }) {
                Row({ space: 6 }) {
                  Toggle({ type: ToggleType.Switch, isOn: this.includeDispersion })
                    .onChange((on: boolean) => { this.includeDispersion = on })
                  Text(this.t('120 点散布', '120-pt Scatter')).fontSize(11).fontColor(this.c.sub)
                }
                Blank()
                Text(this.t('开始 3-DOF 仿真', 'Run 3-DOF Sim'))
                  .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.c.onAccent)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_PILL)
                  .onClick(() => { this.triggerSimulation() })
              }.width('100%').alignItems(VerticalAlign.Center)
            }
              .width('100%')
              .padding(12)
              .backgroundColor(this.cardBg())
              .borderRadius(UI_RADIUS_CARD)
              .border({ width: 0.8, color: this.c.border })
          }

          // Loading indicator / error banner
          if (this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color(this.c.accent)
              Text(this.t('正在进行 3-DOF 球面弹道与火箭云物理积分…', 'Integrating 3-DOF trajectory & plume physics…'))
                .fontSize(12).fontColor(this.c.sub)
            }.width('100%').padding(12)
          }
          if (this.errorMsg.length > 0) {
            Text(this.errorMsg).fontSize(12).fontColor('#FF7A7A').width('100%')
          }

          // Simulation results
          if (this.simulation !== undefined) {
            // 1. Plume Prediction Hero Card
            Column({ space: 10 }) {
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(String(this.simulation.summary.plumeScore))
                    .fontSize(28)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.scoreAccentColor(this.simulation.summary.plumeGrade))
                  Text(this.t('火箭云指数', 'Plume Score'))
                    .fontSize(10)
                    .fontColor(this.c.sub)
                }
                  .width(74)
                  .padding({ top: 6, bottom: 6 })
                  .backgroundColor(this.innerBg())
                  .borderRadius(UI_RADIUS_CONTROL)
                  .alignItems(HorizontalAlign.Center)

                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(this.isZh() ? this.simulation.summary.plumeGradeZh : this.simulation.summary.plumeGradeEn)
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.scoreAccentColor(this.simulation.summary.plumeGrade))
                    Text(formatPropellantTag(this.simulation.vehicle.propellantClass, this.isZh()))
                      .fontSize(10)
                      .fontColor(this.c.text)
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .backgroundColor(this.c.softStrong)
                      .borderRadius(UI_RADIUS_PILL)
                  }
                  Text(this.isZh() ? this.simulation.summary.plumeAdviceZh : this.simulation.summary.plumeAdviceEn)
                    .fontSize(11)
                    .fontColor(this.c.sub)
                    .maxLines(3)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').alignItems(VerticalAlign.Center)

              // Key physics metrics row
              Row({ space: 6 }) {
                this.metricTile(
                  this.t('本地暮光', 'Twilight'),
                  formatTwilightTag(this.simulation.observer.twilightStage, this.simulation.observer.sunAltDeg, this.isZh())
                )
                this.metricTile(
                  this.t('最大仰角', 'Max Alt'),
                  this.simulation.summary.visibleFromObserver
                    ? `${this.simulation.summary.maxAltDeg.toFixed(1)}° @${Math.round(this.simulation.summary.maxAltSec)}s`
                    : this.t('地平线下', 'Below Hor')
                )
                this.metricTile(
                  this.t('跃出地影', 'Sunlit'),
                  this.simulation.summary.sunlitEntrySec >= 0
                    ? `${this.simulation.summary.sunlitEntryAltKm.toFixed(0)}km @${Math.round(this.simulation.summary.sunlitEntrySec)}s`
                    : this.t('全段地影', 'In Umbra')
                )
                this.metricTile(
                  this.t('推荐焦段', 'Lens'),
                  `${this.simulation.summary.recommendedFocalMm}mm`
                )
              }.width('100%')

              // Launch time offset slider (±60 min live twilight/plume sensitivity test!)
              Column({ space: 4 }) {
                Row() {
                  Text(this.t('发射时刻微调（测试推迟/提前对火箭云影响）', 'Launch Time Offset (Test Twilight Sensitivity)'))
                    .fontSize(11).fontColor(this.c.sub).layoutWeight(1)
                  Text((this.timeOffsetMin > 0 ? '+' : '') + `${this.timeOffsetMin} min`)
                    .fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.c.accent)
                }.width('100%')
                Slider({ value: this.timeOffsetMin, min: -60, max: 60, step: 5 })
                  .width('100%')
                  .onChange((val: number) => { this.scheduleOffsetSimulation(val) })
                Text(`${this.t('仿真发令时刻', 'T0')}: ${formatBeijingTimeFromIso(this.simulation.launchTimeUtc)} · ${this.t('射向', 'Az')} ${this.simulation.launchAzimuthDeg.toFixed(1)}° · ${this.simulation.computeMs.toFixed(1)} ms`)
                  .fontSize(10).fontColor(this.c.sub)
              }.width('100%').padding({ top: 4 })
            }
              .width('100%')
              .padding(12)
              .backgroundColor(this.cardBg())
              .borderRadius(UI_RADIUS_CARD)
              .border({ width: 0.8, color: this.c.border })

            // 2. Three detail tabs
            Row({ space: 8 }) {
              this.tabButton(0, this.t('天空轨迹与火箭云', 'Sky Track & Plume'))
              this.tabButton(1, this.t('3D 地球与落区', '3D Globe & Drop'))
              this.tabButton(2, this.t('飞行事件表', 'Events'))
            }.width('100%')

            // Tab 0: Az-Alt Sky Track + Propellant Plume Details
            if (this.activeTab === 0) {
              Column({ space: 10 }) {
                RocketSkyTrackCanvas({
                  simulation: this.simulation,
                  language: this.language
                })
                Column({ space: 4 }) {
                  Text(`${this.t('推进剂形态', 'Propellant Plume')}: ${this.isZh() ? this.simulation.vehicle.plumeTypeZh : this.simulation.vehicle.plumeTypeEn}`)
                    .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text)
                  Text(this.isZh() ? this.simulation.vehicle.summaryZh : this.simulation.vehicle.summaryEn)
                    .fontSize(11).fontColor(this.c.sub)
                  if (this.simulation.summary.plumeWindowStartSec >= 0) {
                    Text(`${this.t('最佳火箭云拍摄窗', 'Best Plume Window')}: T+${Math.round(this.simulation.summary.plumeWindowStartSec)}s ~ T+${Math.round(this.simulation.summary.plumeWindowEndSec)}s · ${this.t('峰值方位/仰角', 'Peak Az/Alt')} ${this.simulation.summary.peakPlumeAzDeg.toFixed(0)}° / ${this.simulation.summary.peakPlumeAltDeg.toFixed(1)}°`)
                      .fontSize(11).fontColor(this.c.accent)
                  }
                }
                  .width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
                  .alignItems(HorizontalAlign.Start)
              }.width('100%')
            }

            // Tab 1: Petal Maps 3D Globe Launch Entry + NOTAM + Debris Impact Cards
            if (this.activeTab === 1) {
              Column({ space: 10 }) {
                // Big launch button for Petal 3D Satellite Globe
                Row({ space: 10 }) {
                  Column({ space: 3 }) {
                    Text(this.t('打开花瓣 3D 卫星地球视图 ↗', 'Open Petal 3D Satellite Globe ↗'))
                      .fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.c.onAccent)
                    Text(this.t('3D 球面晨昏线 · 凌空百公里上升/回落弧 · NOTAM 红区与散布云', '3D Globe Terminator · Elevated 3D Arcs · NOTAM Polygon & Scatter'))
                      .fontSize(10).fontColor(this.c.onAccent).opacity(0.88)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_CARD)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.globeOpen = true })

                if (this.simulation.notam && this.simulation.notam.valid) {
                  Column({ space: 4 }) {
                    Text(`${this.t('航行通告落区', 'NOTAM Hazard Zone')} ${this.simulation.notam.notamId}`)
                      .fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FF7A7A')
                    Text(`${this.t('落区中心', 'Center')}: ${this.simulation.notam.centerLatDeg.toFixed(3)}°N, ${this.simulation.notam.centerLonDeg.toFixed(3)}°E · ${this.t('反演射向', 'Inverted Az')} ${this.simulation.notam.invertedAzimuthDeg.toFixed(1)}° · ${this.t('距发射场', 'Downrange')} ${this.simulation.notam.downrangeKm.toFixed(1)} km`)
                      .fontSize(11).fontColor(this.c.text)
                    if (this.dispersionHitSummary(this.simulation).length > 0) {
                      Text(this.dispersionHitSummary(this.simulation))
                        .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#46E27E')
                    }
                  }
                    .width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
                    .alignItems(HorizontalAlign.Start)
                }

                ForEach(this.simulation.debris, (deb: RocketDebrisInfo) => {
                  Column({ space: 4 }) {
                    Row() {
                      Text(this.isZh() ? deb.labelZh : deb.labelEn)
                        .fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.c.text).layoutWeight(1)
                      if (deb.distanceToNotamKm >= 0) {
                        Text(deb.insideNotam ? this.t('航警区内 ✓', 'In NOTAM ✓') : this.t('区外', 'Outside'))
                          .fontSize(10)
                          .fontColor(deb.insideNotam ? '#46E27E' : '#FFBE55')
                          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                          .backgroundColor(this.c.bg)
                          .borderRadius(UI_RADIUS_PILL)
                      }
                    }.width('100%')
                    Text(`${this.t('落点时刻', 'Impact')}: ${formatBeijingTimeFromIso(deb.impactTimeUtc)} (T+${Math.round(deb.impactTimeSec)}s)`)
                      .fontSize(11).fontColor(this.c.sub)
                    Text(`${this.t('落点坐标', 'Coords')}: ${deb.impactLonDeg.toFixed(4)}°E, ${deb.impactLatDeg.toFixed(4)}°N · ${this.t('射程', 'Downrange')} ${deb.downrangeKm.toFixed(1)} km`)
                      .fontSize(11).fontColor(this.c.sub)
                  }
                    .width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
                    .alignItems(HorizontalAlign.Start)
                }, (deb: RocketDebrisInfo) => deb.kind + '_' + deb.impactTimeSec)
              }.width('100%')
            }

            // Tab 2: Flight Events Timeline
            if (this.activeTab === 2) {
              Column({ space: 6 }) {
                ForEach(this.simulation.events, (ev: RocketFlightEventInfo) => {
                  Row({ space: 10 }) {
                    Text(`T+${Math.round(ev.tSec)}s`)
                      .fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.c.accent).width(54)
                    Column({ space: 2 }) {
                      Text(this.isZh() ? ev.labelZh : ev.labelEn)
                        .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.c.text)
                      Text(`${this.t('高度', 'Alt')} ${ev.altKm.toFixed(1)} km · ${this.t('速度', 'Vel')} ${ev.speedKmS.toFixed(2)} km/s · ${this.t('方位/仰角', 'Az/Alt')} ${ev.azDeg.toFixed(0)}°/${ev.altDeg.toFixed(1)}°`)
                        .fontSize(10).fontColor(this.c.sub)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  }
                    .width('100%')
                    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                    .backgroundColor(this.c.soft)
                    .borderRadius(UI_RADIUS_CONTROL)
                }, (ev: RocketFlightEventInfo) => ev.code + '_' + Math.round(ev.tSec))
              }.width('100%')
            }
          }
        }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
      }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)

      // Bottom Action Bar
      if (this.simulation !== undefined) {
        Row({ space: 10 }) {
          Text(this.t('3D 地球落区', '3D Globe'))
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.text)
            .padding({ left: 16, right: 16, top: 11, bottom: 11 })
            .backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL)
            .onClick(() => { this.globeOpen = true })

          Text(this.t('在星图中 3D 预演火箭云 ↗', 'Preview Plume in Sky ↗'))
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.c.onAccent)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: 11, bottom: 11 })
            .backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              if (this.simulation !== undefined) {
                this.host.previewInSky(this.simulation)
                this.onClose()
              }
            })
        }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 18 })
          .border({ width: { top: 0.6 }, color: this.c.border })
      }
    }
      .width('100%')
      .height('100%')
      .backgroundColor(this.modalBg())
      .bindContentCover($$this.globeOpen, this.globeModalBuilder(), {
        modalTransition: ModalTransition.DEFAULT
      })
  }

  @Builder
  private metricTile(label: string, value: string) {
    Column({ space: 3 }) {
      Text(label).fontSize(10).fontColor(this.c.sub).maxLines(1)
      Text(value).fontSize(11).fontWeight(FontWeight.Bold).fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .layoutWeight(1)
      .padding({ left: 6, right: 6, top: 6, bottom: 6 })
      .backgroundColor(this.innerBg())
      .borderRadius(UI_RADIUS_CONTROL)
      .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private tabButton(index: number, title: string) {
    Text(title)
      .fontSize(12)
      .fontWeight(this.activeTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.activeTab === index ? this.c.onAccent : this.c.sub)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.activeTab === index ? this.c.accent : this.cardBg())
      .borderRadius(UI_RADIUS_PILL)
      .onClick(() => { this.activeTab = index })
  }
}
