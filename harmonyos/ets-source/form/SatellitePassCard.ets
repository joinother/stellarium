import {
  formatCountdownZh,
  formatShortDateZh,
  parseRemindedEventIds,
  routePlanetForCard
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
  SatellitePassArcView,
  StarfieldLayer,
  satelliteIconResource
} from './WidgetVisuals'

const satellitePassStorage: LocalStorage = new LocalStorage()

@Entry(satellitePassStorage)
@Component
struct SatellitePassCard {
  @LocalStorageProp('observerPlanet') observerPlanet: string = 'Earth'
  @LocalStorageProp('satellitePassesJson') satellitePassesJson: string = '[]'
  @LocalStorageProp('satPassIndex') satPassIndex: string = '0'
  @LocalStorageProp('remindedEventIds') remindedEventIds: string = '[]'
  @LocalStorageProp('reminderToast') reminderToast: string = ''
  @LocalStorageProp('cardThemeStyle') cardThemeStyle: string = 'sky'
  @LocalStorageProp('cardOverflowMode') cardOverflowMode: string = 'auto'

  @State cardWidth: number = 320
  @State cardHeight: number = 160

  private isWide(): boolean { return this.cardWidth >= 230 }
  private isTall(): boolean { return this.cardHeight >= 230 }

  private passes(): CompactSatellitePass[] {
    return parseSatellitePasses(this.satellitePassesJson, Date.now())
  }

  private activeIndex(): number {
    const list = this.passes()
    if (list.length === 0) return 0
    const raw = Math.floor(Number(this.satPassIndex))
    const safe = Number.isFinite(raw) && raw >= 0 ? raw : 0
    return safe % list.length
  }

  private activePass(): CompactSatellitePass {
    const list = this.passes()
    return list[this.activeIndex()]
  }

  private isReminded(pass: CompactSatellitePass): boolean {
    const rid = satellitePassReminderId(pass)
    return parseRemindedEventIds(this.remindedEventIds).includes(rid)
  }

  private magBadge(pass: CompactSatellitePass): string {
    if (!Number.isFinite(pass.mag) || pass.mag > 15) return pass.visible ? '日照可见' : '地影'
    const sign = pass.mag > 0 ? '+' : ''
    return sign + pass.mag.toFixed(1) + '等'
  }

  private clockOnly(ms: number): string {
    if (!Number.isFinite(ms) || ms <= 0) return '—'
    const d = new Date(ms)
    return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0')
  }

  private trajectorySummary(pass: CompactSatellitePass): string {
    return compassDirectionZh(pass.startAz) + ' → ' + compassDirectionZh(pass.endAz) +
      ' · 最高 ' + String(Math.round(pass.maxAlt)) + '°'
  }

  private topGradient(): string {
    return this.cardThemeStyle === 'deep' ? '#040710' : '#060E24'
  }

  private bottomGradient(): string {
    return this.cardThemeStyle === 'deep' ? '#0A1224' : '#0E2448'
  }

  private openPassInSky(pass: CompactSatellitePass): void {
    const rid = satellitePassReminderId(pass)
    postCardAction(this, {
      action: 'router',
      abilityName: 'QAbility',
      params: {
        panel: 'satellites',
        kind: 'satellite-pass',
        eventId: rid,
        target: pass.id,
        jd: pass.peakJd,
        eventAt: new Date(pass.peakAt).toISOString(),
        observerPlanet: routePlanetForCard(this.observerPlanet),
        landingTitle: pass.name + ' · ' + this.trajectorySummary(pass),
        landingSource: 'card'
      }
    })
  }

  private triggerOverflowOrOpen(): void {
    if (this.cardOverflowMode === 'off') {
      this.openPassInSky(this.activePass())
      return
    }
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'requestOverflow',
        formName: 'satellite_pass_card'
      }
    })
  }

  private stepPass(delta: number): void {
    const count = Math.max(1, this.passes().length)
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'stepSatPassIndex',
        formName: 'satellite_pass_card',
        delta: delta,
        count: count
      }
    })
  }

  private toggleReminder(pass: CompactSatellitePass): void {
    postCardAction(this, {
      action: 'message',
      abilityName: 'SkyInstrumentFormAbility',
      params: {
        message: 'toggleEventReminder',
        formName: 'satellite_pass_card',
        eventId: satellitePassReminderId(pass),
        kind: 'satellite-pass',
        title: pass.name + ' 过境',
        target: pass.id,
        observerPlanet: 'Earth',
        at: pass.startAt,
        jd: pass.peakJd
      }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      StarfieldLayer({ sunAlt: -24, themeStyle: 'deep' })

      if (!this.isWide() && !this.isTall()) {
        // 2x2 Compact Orbital Pass Radar
        Column() {
          Row({ space: 4 }) {
            Text(this.activePass().name)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.magBadge(this.activePass()))
              .fontSize(9.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(satelliteVisualProfile(this.activePass().archetype).accentHex)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor('#280B1830')
              .borderRadius(8)
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SatellitePassArcView({
              stageWidth: Math.max(124, Math.round(this.cardWidth - 18)),
              stageHeight: Math.max(76, Math.round(this.cardHeight - 62)),
              maxAlt: this.activePass().maxAlt,
              startAz: this.activePass().startAz,
              endAz: this.activePass().endAz,
              archetype: this.activePass().archetype,
              visible: this.activePass().visible,
              showCraft: true,
              craftSize: 38
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Row({ space: 5 }) {
            Text(formatCountdownZh(this.activePass().startAt, Date.now()))
              .fontSize(10.5)
              .fontWeight(FontWeight.Medium)
              .fontColor('#7CEEFF')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.isReminded(this.activePass()) ? '✓ 已约' : '提醒')
              .fontSize(9.5)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isReminded(this.activePass()) ? '#7FF5C4' : '#EAF4FF')
              .height(22)
              .padding({ left: 8, right: 8 })
              .backgroundColor(this.isReminded(this.activePass()) ? '#341A6E4E' : '#2E3B6DB8')
              .borderRadius(11)
              .onClick(() => this.toggleReminder(this.activePass()))
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 11, right: 11, top: 9, bottom: 9 })
      } else if (!this.isTall()) {
        // 2x4 Flagship Satellite Pass Tracker (Earth-limb trajectory + countdown + reminder + star-map track)
        Row({ space: 10 }) {
          Stack({ alignContent: Alignment.Center }) {
            SatellitePassArcView({
              stageWidth: Math.max(134, Math.round(this.cardWidth * 0.44)),
              stageHeight: Math.max(114, Math.round(this.cardHeight - 20)),
              maxAlt: this.activePass().maxAlt,
              startAz: this.activePass().startAz,
              endAz: this.activePass().endAz,
              archetype: this.activePass().archetype,
              visible: this.activePass().visible,
              showCraft: true,
              craftSize: 46
            })
          }
          .width(Math.max(134, Math.round(this.cardWidth * 0.44)))
          .height('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          Column({ space: 4 }) {
            Row({ space: 4 }) {
              Text(satelliteVisualProfile(this.activePass().archetype).categoryLabelZh)
                .fontSize(9.5)
                .fontWeight(FontWeight.Medium)
                .fontColor(satelliteVisualProfile(this.activePass().archetype).accentHex)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor('#2C13294E')
                .borderRadius(8)
              Text(this.magBadge(this.activePass()))
                .fontSize(9.5)
                .fontColor('#CFE4FF')
                .maxLines(1)
              Blank()
              if (this.passes().length > 1) {
                Row({ space: 3 }) {
                  Text('‹')
                    .fontSize(12)
                    .fontColor('#CFE4FF')
                    .width(20)
                    .height(20)
                    .textAlign(TextAlign.Center)
                    .backgroundColor('#22FFFFFF')
                    .borderRadius(10)
                    .onClick(() => this.stepPass(-1))
                  Text('›')
                    .fontSize(12)
                    .fontColor('#CFE4FF')
                    .width(20)
                    .height(20)
                    .textAlign(TextAlign.Center)
                    .backgroundColor('#22FFFFFF')
                    .borderRadius(10)
                    .onClick(() => this.stepPass(1))
                }
              }
            }
            .width('100%')

            Text(this.activePass().name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 6 }) {
              Text(formatCountdownZh(this.activePass().startAt, Date.now()))
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor('#6DF5F5')
                .maxLines(1)
              Text(this.clockOnly(this.activePass().startAt) + ' · ' + formatPassDurationZh(this.activePass().durationSec))
                .fontSize(10.5)
                .fontColor('#B8D6F5')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)

            Text(satelliteBrightnessGradeZh(this.activePass().mag, this.activePass().visible) + ' · 距 ' + String(Math.round(this.activePass().rangeKm)) + ' km')
              .fontSize(10)
              .fontColor('#9ABCE0')
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Blank()

            Row({ space: 6 }) {
              Text(this.isReminded(this.activePass()) ? '✓ 已约提醒' : '预约提醒')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.isReminded(this.activePass()) ? '#86F7C8' : '#FFFFFF')
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .height(27)
                .backgroundColor(this.isReminded(this.activePass()) ? '#341A6E4E' : '#323F76C8')
                .borderRadius(13.5)
                .onClick(() => this.toggleReminder(this.activePass()))

              Text('追踪 ↗')
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#8CEEFF')
                .textAlign(TextAlign.Center)
                .width(52)
                .height(27)
                .backgroundColor('#28163A6E')
                .borderRadius(13.5)
                .onClick(() => this.openPassInSky(this.activePass()))
            }
            .width('100%')
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ top: 2, bottom: 2 })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 10, right: 12, top: 9, bottom: 9 })
      } else {
        // 4x4 Full Orbital Radar + Upcoming Multi-Spacecraft Schedule
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(this.activePass().name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#FFFFFF')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(satelliteVisualProfile(this.activePass().archetype).categoryLabelZh)
                  .fontSize(9.5)
                  .fontColor(satelliteVisualProfile(this.activePass().archetype).accentHex)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor('#2C13294E')
                  .borderRadius(8)
              }
              Text(formatCountdownZh(this.activePass().startAt, Date.now()) + ' · ' +
                formatShortDateZh(this.activePass().startAt) + ' · ' +
                (Number.isFinite(this.activePass().mag) && this.activePass().mag <= 15
                  ? (this.magBadge(this.activePass()) + ' · ' + satelliteBrightnessGradeZh(this.activePass().mag, this.activePass().visible))
                  : satelliteBrightnessGradeZh(this.activePass().mag, this.activePass().visible)))
                .fontSize(10)
                .fontColor('#9CD4FF')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(this.isReminded(this.activePass()) ? '✓ 已约' : '提醒')
              .fontSize(10)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isReminded(this.activePass()) ? '#86F7C8' : '#FFFFFF')
              .height(26)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.isReminded(this.activePass()) ? '#341A6E4E' : '#363F76C8')
              .borderRadius(13)
              .onClick(() => this.toggleReminder(this.activePass()))
          }
          .width('100%')

          Stack({ alignContent: Alignment.Center }) {
            SatellitePassArcView({
              stageWidth: Math.max(250, Math.round(this.cardWidth - 26)),
              stageHeight: Math.max(106, Math.round(this.cardHeight - 186)),
              maxAlt: this.activePass().maxAlt,
              startAz: this.activePass().startAz,
              endAz: this.activePass().endAz,
              archetype: this.activePass().archetype,
              visible: this.activePass().visible,
              showCraft: true,
              craftSize: 52
            })
          }
          .layoutWeight(1)
          .width('100%')
          .onClick(() => this.triggerOverflowOrOpen())

          // Upcoming Multi-Spacecraft Schedule (up to 3 rows, each with its archetype SVG icon)
          Column({ space: 4 }) {
            ForEach(this.passes().slice(0, 3), (item: CompactSatellitePass, idx: number) => {
              Row({ space: 8 }) {
                Image(satelliteIconResource(item.archetype))
                  .width(24)
                  .height(24)
                  .objectFit(ImageFit.Contain)
                Column({ space: 1 }) {
                  Text(item.name)
                    .fontSize(11)
                    .fontWeight(idx === this.activeIndex() ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(idx === this.activeIndex() ? '#FFFFFF' : '#D4E6FA')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(formatShortDateZh(item.startAt) + ' · ' + compassDirectionZh(item.startAz) + '→' + compassDirectionZh(item.endAz) + ' · 最高 ' + String(Math.round(item.maxAlt)) + '°')
                    .fontSize(9.5)
                    .fontColor('#93B3D6')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Text(this.magBadge(item))
                  .fontSize(9.5)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(satelliteVisualProfile(item.archetype).accentHex)
                Text('↗')
                  .fontSize(11)
                  .fontColor('#8CEEFF')
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor(idx === this.activeIndex() ? '#2C274F8E' : '#18FFFFFF')
              .borderRadius(10)
              .onClick(() => this.openPassInSky(item))
            }, (item: CompactSatellitePass) => item.id + '_' + String(item.startAt))
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 13, right: 13, top: 11, bottom: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .linearGradient({
      angle: 162,
      colors: [
        [this.topGradient(), 0.0],
        [this.bottomGradient(), 1.0]
      ]
    })
    .border({ width: 0.6, color: '#2C6DF5F5' })
    .onSizeChange((_oldSize: SizeOptions, newSize: SizeOptions) => {
      if (typeof newSize.width === 'number' && newSize.width > 0) this.cardWidth = newSize.width
      if (typeof newSize.height === 'number' && newSize.height > 0) this.cardHeight = newSize.height
    })
    .onClick(() => this.openPassInSky(this.activePass()))
  }
}
