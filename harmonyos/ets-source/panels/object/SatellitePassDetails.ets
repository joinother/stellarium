import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_MEDIA } from '../../common/ui/UiTokens'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { SatellitePass, StationComplexMember } from '../../pages/StellariumTypes'
import {
  StationCrewCountryCount,
  StationCrewKey,
  StationCrewMember,
  StationCrewService,
  StationCrewSnapshot,
  flagEmojiForCountryCode,
  localizeAstronautName,
  localizeCountryName,
  localizeCrewPosition,
  localizeSpacecraftName,
  resolveStationCrewKey
} from '../../capability/StationCrewService'
import { Theme, curves } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 卫星过境段：过境卡片、时间线与加载 / 空 / 未请求态。
//
// 以 `@ObjectLink` 观察 `ObjectDetailStore`，`accent`（夜视强调色）等由宿主以 `@Prop` 注入；
// 单条过境的格式化用文件作用域函数实现，ForEach 的 key 由过境时间派生。

function satellitePassTime(value: string | undefined): string {
  if (value === undefined || value.length === 0) return '--'
  const cleaned = value.replace('T', ' ').replace(/\.000Z$/, '').replace(/Z$/, '')
  // Compact YYYY-MM-DD HH:mm:ss -> MM-DD HH:mm:ss for readable timeline display
  if (cleaned.length >= 19 && cleaned[4] === '-' && cleaned[7] === '-') {
    return cleaned.substring(5, 19)
  }
  return cleaned
}

function satelliteCompassDirection(deg: number | undefined): string {
  if (typeof deg !== 'number' || !Number.isFinite(deg)) return '--'
  const norm = ((deg % 360) + 360) % 360
  const dirs: string[] = ['北', '东北', '东', '东南', '南', '西南', '西', '西北']
  const idx = Math.floor((norm + 22.5) / 45) % 8
  return dirs[idx] + ' ' + Math.round(norm).toString() + '°'
}

function satelliteDurationText(sec: number | undefined): string {
  if (typeof sec !== 'number' || !Number.isFinite(sec) || sec <= 0) return ''
  const total = Math.round(sec)
  const mins = Math.floor(total / 60)
  const rem = total % 60
  if (mins <= 0) return rem.toString() + '秒'
  return mins.toString() + '分' + (rem > 0 ? rem.toString().padStart(2, '0') + '秒' : '')
}

function satellitePassHasJumpTarget(pass: SatellitePass): boolean {
  return (typeof pass.peakJD === 'number' && Number.isFinite(pass.peakJD) && pass.peakJD > 0) ||
    (typeof pass.startJD === 'number' && Number.isFinite(pass.startJD) && pass.startJD > 0)
}

function satellitePassVisibility(pass: SatellitePass): string {
  if (pass.visible === true || pass.peakVisible === true) return I18n.t('satellite_pass_visible')
  switch (pass.visibilityReason) {
    case 'observer_in_daylight': return I18n.t('satellite_pass_daylight')
    case 'satellite_in_earth_shadow': return I18n.t('satellite_pass_shadow')
    case 'below_horizon': return I18n.t('satellite_pass_below_horizon')
    case 'satellite_eclipsed': return I18n.t('satellite_pass_eclipsed')
    default: return I18n.t('satellite_pass_not_visible')
  }
}

function satellitePassAltitude(value: number | undefined): string {
  return typeof value === 'number' && Number.isFinite(value) ? value.toFixed(1) + '°' : '--'
}

function satellitePassAngle(value: number | undefined): string {
  return typeof value === 'number' && Number.isFinite(value) ? value.toFixed(1) + '°' : '--'
}

@Component
export struct SatellitePassTimelineRow {
  @Prop label: string
  @Prop time: string
  @Prop tablet: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Row({ space: 7 }) {
      Column() {
        Circle({ width: this.tablet ? 8 : 7, height: this.tablet ? 8 : 7 })
          .fill(this.c.accent)
        Divider().vertical(true).height(18).color(this.c.border)
      }.width(10).height(30).justifyContent(FlexAlign.Center)
      Column({ space: 1 }) {
        Text(this.label).fontSize(this.tablet ? 10 : 10).fontColor(this.c.tertiary)
        Text(satellitePassTime(this.time)).fontSize(this.tablet ? 12 : 11).fontColor(this.c.fourth)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1)
    }.width('100%').height(36)
  }
}

@Component
export struct SatellitePassCard {
  @Prop pass: SatellitePass
  @Prop tablet: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onJumpToPass: (pass: SatellitePass) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 5 }) {
      Row({ space: 6 }) {
        Text(satellitePassVisibility(this.pass)).fontSize(this.tablet ? 11 : 10).fontWeight(FontWeight.Medium)
          .fontColor(this.pass.visible === true || this.pass.peakVisible === true
            ? this.c.success
            : this.c.warning)
        Text(this.pass.ongoing === true ? '· 正在过境' : (satelliteDurationText(this.pass.durationSeconds).length > 0 ? '· ' + satelliteDurationText(this.pass.durationSeconds) : ''))
          .fontSize(10).fontColor(this.c.tertiary).layoutWeight(1)
        Text(typeof this.pass.maxMagnitude === 'number' && Number.isFinite(this.pass.maxMagnitude) && this.pass.maxMagnitude < 90
          ? '星等 ' + this.pass.maxMagnitude.toFixed(1)
          : '')
          .fontSize(10).fontColor(this.c.detailSub)
      }.width('100%')
      Column({ space: 1 }) {
        SatellitePassTimelineRow({ label: I18n.t('satellite_pass_appearance') + ' · ' + satelliteCompassDirection(this.pass.startAzimuth), time: this.pass.start ?? this.pass.appearance ?? '', tablet: this.tablet })
        SatellitePassTimelineRow({ label: I18n.t('satellite_pass_peak') + ' · 仰角 ' + satellitePassAltitude(this.pass.maxAltitude), time: this.pass.peak ?? '', tablet: this.tablet })
        SatellitePassTimelineRow({ label: I18n.t('satellite_pass_disappearance') + ' · ' + satelliteCompassDirection(this.pass.endAzimuth), time: this.pass.end ?? this.pass.disappearance ?? '', tablet: this.tablet })
      }.width('100%')
      Row({ space: 8 }) {
        Column({ space: 1 }) {
          Text(I18n.t('satellite_pass_max_altitude')).fontSize(10).fontColor(this.c.tertiary)
          Text(satellitePassAltitude(this.pass.maxAltitude)).fontSize(this.tablet ? 12 : 11).fontColor(this.c.fourth)
        }.layoutWeight(1)
        Column({ space: 1 }) {
          Text('过境方位').fontSize(10).fontColor(this.c.tertiary)
          Text(satelliteCompassDirection(this.pass.peakAzimuth)).fontSize(this.tablet ? 12 : 11).fontColor(this.c.fourth)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1)
        if (satellitePassHasJumpTarget(this.pass)) {
          Button('预演过境')
            .fontSize(10.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.accent)
            .backgroundColor(this.c.softStrong)
            .border({ width: 0.5, color: this.c.border })
            .borderRadius(UI_RADIUS_CONTROL)
            .height(28)
            .padding({ left: 10, right: 10 })
            .onClick(() => { this.onJumpToPass(this.pass) })
        }
      }.width('100%').alignItems(VerticalAlign.Center)
    }
      .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .backgroundColor(this.c.soft)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct StationComplexSection {
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSelectMember: (member: StationComplexMember) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private isCurrentMember(member: StationComplexMember): boolean {
    if (this.store.selectedEnglishName.length > 0 && member.englishName === this.store.selectedEnglishName) {
      return true
    }
    return this.store.selectedName.length > 0 && member.name === this.store.selectedName
  }

  build() {
    if (this.store.selectedStationComplex !== undefined && this.store.selectedStationComplex.members.length > 1) {
      Column({ space: 7 }) {
        Row({ space: 6 }) {
          Text(this.store.selectedStationComplex.complexName)
            .fontSize(this.tablet ? 13 : 12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.fourth)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('共 ' + this.store.selectedStationComplex.memberCount.toString() + ' 舱段/飞船')
            .fontSize(10)
            .fontColor(this.c.accent)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_MEDIA)
        }.width('100%').alignItems(VerticalAlign.Center)

        Text('同轨组合体舱段与在轨对接飞船 · 点选切换查看独立轨道与根数')
          .fontSize(10.5)
          .fontColor(this.c.tertiary)
          .width('100%')

        Column({ space: 5 }) {
          ForEach(this.store.selectedStationComplex.members, (member: StationComplexMember) => {
            Row({ space: 8 }) {
              Circle({ width: 6, height: 6 })
                .fill(this.isCurrentMember(member) ? this.c.accent : (member.isPrimary ? this.c.fourth : this.c.border))
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(member.name)
                    .fontSize(this.tablet ? 12 : 11.5)
                    .fontWeight(this.isCurrentMember(member) ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.isCurrentMember(member) ? this.c.fourth : this.c.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(member.roleLabel)
                    .fontSize(9.5)
                    .fontColor(member.isPrimary ? this.c.accent : this.c.sub)
                    .padding({ left: 6, right: 6, top: 1.5, bottom: 1.5 })
                    .backgroundColor(this.c.input)
                    .borderRadius(UI_RADIUS_MEDIA)
                }.width('100%').alignItems(VerticalAlign.Center)
                Text('NORAD ' + member.id + (member.englishName !== member.name ? ' · ' + member.englishName : ''))
                  .fontSize(9.5)
                  .fontColor(this.c.tertiary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)

              Text(this.isCurrentMember(member) ? '当前' : '›')
                .fontSize(this.isCurrentMember(member) ? 10 : 14)
                .fontColor(this.isCurrentMember(member) ? this.c.accent : this.c.tertiary)
            }
              .width('100%')
              .padding({ left: 9, right: 9, top: 7, bottom: 7 })
              .backgroundColor(this.isCurrentMember(member) ? this.c.softStrong : this.c.bg)
              .border({ width: 0.5, color: this.isCurrentMember(member) ? this.c.accent : this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => {
                if (!this.isCurrentMember(member)) {
                  this.onSelectMember(member)
                }
              })
          }, (member: StationComplexMember) => 'station-complex-member-' + member.id)
        }.width('100%')
      }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .backgroundColor(this.c.soft)
        .border({ width: 0.5, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
    }
  }
}

@Component
export struct StationCrewSection {
  @StorageProp('stellariumI18nLang') i18nLang: string = 'zh'
  @StorageProp('stellariumSimDateLabel') simDateLabel: string = ''
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private refreshing: boolean = false

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private isZh(): boolean {
    return this.i18nLang.toLowerCase().startsWith('zh')
  }

  private resolveKey(): StationCrewKey {
    // 显式读取 stationCrewRevision，确保镜像同步完成后触发细粒度重绘。
    const _rev = this.store.stationCrewRevision
    if (_rev < 0) return ''
    const primaryId = this.store.selectedStationComplex !== undefined ? this.store.selectedStationComplex.primaryId : ''
    return resolveStationCrewKey(
      this.store.selectedCatalogId,
      this.store.selectedEnglishName,
      this.store.selectedName,
      primaryId
    )
  }

  private currentSnapshot(): StationCrewSnapshot {
    return StationCrewService.getInstance().getSnapshotForStation(this.resolveKey())
  }

  private isHistoricalSimDate(): boolean {
    const raw = this.simDateLabel.trim()
    if (raw.length < 10) return false
    const match = /^(\d{4})[-/](\d{1,2})[-/](\d{1,2})/.exec(raw)
    if (match === null) return false
    const simMs = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
    if (!Number.isFinite(simMs)) return false
    return Math.abs(Date.now() - simMs) > 21 * 24 * 3600 * 1000
  }

  private formatCountrySummary(countries: StationCrewCountryCount[], isZh: boolean): string {
    const parts: string[] = []
    for (let i = 0; i < countries.length; i++) {
      const item = countries[i]
      const flag = flagEmojiForCountryCode(item.flagCode, item.country)
      const label = localizeCountryName(item.country, item.flagCode, isZh)
      parts.push(flag + ' ' + label + ' ' + item.count.toString())
    }
    return parts.join(' · ')
  }

  private formatSourceTag(snap: StationCrewSnapshot, isZh: boolean): string {
    if (this.refreshing) {
      return isZh ? '正在从阿里云镜像同步…' : 'Syncing from mirror…'
    }
    if (snap.sourceKind === 'mirror' && snap.syncedAtMs > 0) {
      const d = new Date(snap.syncedAtMs)
      const hh = String(d.getHours()).padStart(2, '0')
      const mm = String(d.getMinutes()).padStart(2, '0')
      return isZh ? ('阿里云镜像 · ' + hh + ':' + mm) : ('Mirror · ' + hh + ':' + mm)
    }
    if (snap.sourceKind === 'cache') {
      return isZh ? '本地镜像缓存 · 点击刷新' : 'Cached mirror · Tap to refresh'
    }
    return isZh ? '实时在轨名单 · 点击同步' : 'Onboard roster · Tap to sync'
  }

  private triggerManualRefresh(): void {
    if (this.refreshing) return
    this.refreshing = true
    void StationCrewService.getInstance().syncIfNeeded(true).then(() => {
      this.refreshing = false
      this.store.stationCrewRevision += 1
    }).catch(() => {
      this.refreshing = false
    })
  }

  build() {
    if (this.resolveKey() !== '' && this.currentSnapshot().members.length > 0) {
      Column({ space: 7 }) {
        Row({ space: 6 }) {
          Text(this.isZh()
            ? ('在轨航天员' + (this.currentSnapshot().stationKey === 'iss' && this.currentSnapshot().issExpedition > 0
              ? (' · 第 ' + this.currentSnapshot().issExpedition.toString() + ' 远征队')
              : (this.currentSnapshot().stationKey === 'tiangong' ? ' · 天宫乘组' : '')))
            : ('Onboard Crew' + (this.currentSnapshot().stationKey === 'iss' && this.currentSnapshot().issExpedition > 0
              ? (' · Exp. ' + this.currentSnapshot().issExpedition.toString())
              : (this.currentSnapshot().stationKey === 'tiangong' ? ' · Tiangong' : ''))))
            .fontSize(this.tablet ? 13 : 12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.fourth)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.isZh()
            ? ('共 ' + this.currentSnapshot().members.length.toString() + ' 人')
            : (this.currentSnapshot().members.length.toString() + ' onboard'))
            .fontSize(10)
            .fontColor(this.c.accent)
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_MEDIA)
        }.width('100%').alignItems(VerticalAlign.Center)

        Row({ space: 6 }) {
          Text(this.formatCountrySummary(this.currentSnapshot().countries, this.isZh()))
            .fontSize(10.5)
            .fontColor(this.c.sub)
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.formatSourceTag(this.currentSnapshot(), this.isZh()))
            .fontSize(9.5)
            .fontColor(this.c.tertiary)
            .onClick(() => { this.triggerManualRefresh() })
        }.width('100%').alignItems(VerticalAlign.Center)

        Column({ space: 5 }) {
          ForEach(this.currentSnapshot().members, (member: StationCrewMember) => {
            Row({ space: 8 }) {
              Text(flagEmojiForCountryCode(member.flagCode, member.country))
                .fontSize(this.tablet ? 18 : 16)
                .width(26)
                .textAlign(TextAlign.Center)
              Column({ space: 2 }) {
                Row({ space: 6 }) {
                  Text(localizeAstronautName(member.name, member.flagCode, this.isZh()))
                    .fontSize(this.tablet ? 12 : 11.5)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.c.fourth)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  if (member.position.length > 0) {
                    Text(localizeCrewPosition(member.position, this.isZh()))
                      .fontSize(9.5)
                      .fontColor(member.position.toLowerCase() === 'commander' ? this.c.accent : this.c.sub)
                      .padding({ left: 6, right: 6, top: 1.5, bottom: 1.5 })
                      .backgroundColor(this.c.input)
                      .borderRadius(UI_RADIUS_MEDIA)
                  }
                }.width('100%').alignItems(VerticalAlign.Center)
                Text(
                  localizeCountryName(member.country, member.flagCode, this.isZh())
                  + (member.agency.length > 0 ? (' · ' + member.agency) : '')
                  + (member.spacecraft.length > 0 ? (' · ' + localizeSpacecraftName(member.spacecraft, this.isZh())) : '')
                )
                  .fontSize(10)
                  .fontColor(this.c.tertiary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }
              .width('100%')
              .padding({ left: 9, right: 9, top: 7, bottom: 7 })
              .backgroundColor(this.c.bg)
              .border({ width: 0.5, color: this.c.border })
              .borderRadius(UI_RADIUS_CONTROL)
          }, (member: StationCrewMember) => 'station-crew-' + member.id)
        }.width('100%')

        if (this.isHistoricalSimDate()) {
          Text(this.isZh()
            ? '注：以上为当前实时在轨乘组名单，不随历史时间轴回溯。'
            : 'Note: Shows current real-time onboard crew, not historical expedition crew.')
            .fontSize(9.5)
            .fontColor(this.c.tertiary)
            .width('100%')
        }
      }
        .width('100%')
        .padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .backgroundColor(this.c.soft)
        .border({ width: 0.5, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
        .margin({ top: 4, bottom: 4 })
    }
  }
}

@Component
export struct SatellitePassDetails {
  @ObjectLink store: ObjectDetailStore
  @Prop tablet: boolean
  @Prop visible: boolean
  @Prop tleEpoch: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onLoad: () => void = () => {}
  onJumpToPass: (pass: SatellitePass) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    if (this.visible) {
      Column({ space: 7 }) {
        Row() {
          Text(I18n.t('satellite_passes_title')).fontSize(this.tablet ? 13 : 12).fontWeight(FontWeight.Medium)
            .fontColor(this.c.fourth).layoutWeight(1)
          Text(this.store.selectedSatellitePassesLoaded ? this.store.selectedSatellitePasses.length.toString() : '')
            .fontSize(10).fontColor(this.c.tertiary)
        }.width('100%')
        if (!this.store.selectedSatellitePassesRequested) {
          Row({ space: 8 }) {
            Text(I18n.t('satellite_passes_lazy_hint')).fontSize(11).fontColor(this.c.tertiary)
              .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Button(I18n.t('satellite_passes_load'))
              .fontSize(11).fontColor(this.c.fourth)
              .backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => {
                this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
                  this.onLoad()
                })
              })
          }.width('100%').alignItems(VerticalAlign.Center).padding({ top: 6, bottom: 6 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
        } else if (!this.store.selectedSatellitePassesLoaded) {
          Row({ space: 7 }) {
            LoadingProgress().width(16).height(16).color(this.c.spinner)
            Text(I18n.t('satellite_pass_preparing')).fontSize(11).fontColor(this.c.tertiary)
          }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseOut }))
        } else if (this.store.selectedSatellitePasses.length === 0) {
          Text(I18n.t('satellite_pass_no_data')).fontSize(11).fontColor(this.c.tertiary)
            .lineHeight(17).width('100%').padding({ top: 6, bottom: 6 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut }))
        } else {
          Column({ space: 6 }) {
            Text(I18n.t('satellite_next_pass')).fontSize(10).fontColor(this.c.tertiary).width('100%')
            ForEach(this.store.selectedSatellitePasses.slice(0, 5), (pass: SatellitePass) => {
              SatellitePassCard({ pass: pass, tablet: this.tablet, onJumpToPass: (target: SatellitePass) => { this.onJumpToPass(target) } })
            }, (pass: SatellitePass, index: number) => 'satellite-pass-' + index.toString() + '-' + satellitePassTime(pass.start))
          }.width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ y: 8 }).animation({ duration: 260, curve: curves.springMotion(0.55, 0.88) })))
        }
        if (this.store.selectedSatellitePassesLoaded && this.tleEpoch.length > 0) {
          Text(I18n.format('satellite_pass_offline_source', [this.tleEpoch])).fontSize(10).fontColor(this.c.detailSub)
            .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
        .width('100%').padding({ left: 10, right: 10, top: 10, bottom: 10 })
        .backgroundColor(this.c.soft)
        .border({ width: 0.5, color: this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
    }
  }
}
