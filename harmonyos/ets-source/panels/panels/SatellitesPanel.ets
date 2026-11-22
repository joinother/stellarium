import { Theme, curves } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { SatelliteListItem, SatelliteSource, CatalogHealthEntry, OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { StationComplexMember } from '../../pages/StellariumTypes'
import { SatelliteGroupSelector } from '../satellite/SatelliteGroupSelector'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_MEDIA, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { SatelliteStore } from '../../state/SatelliteStore'
import { classifySatelliteArchetype, satelliteVisualProfile } from '../../form/SatelliteVisualRegistry'
import { satelliteIconResource } from '../../form/WidgetVisuals'

// 卫星面板，对应 `activePanel === 'satellites'`。
//
// 现代化极简信息架构：
// - 主屏只保留「精简状态条（含刷新与高级入口）＋ 搜索框 ＋ 横向分组胶囊 ＋ 清晰卫星卡片」；
// - 自动更新策略、在线源管理、本地 TLE 导入、显示与轨迹开关、手动倒计时和轨道诊断
//   全部收敛进「高级设置」二级菜单，保持主屏干净利落。

@Component
export struct SatellitesPanel {
  @ObjectLink satelliteStore: SatelliteStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private sectionDirection: number = 1
  @State private expandedComplexIds: string[] = []
  panelScroller: Scroller = new Scroller()
  groupScroller: Scroller = new Scroller()
  onPublishState: () => void = () => {}
  catalogHealthTextOf: (title: string, health: CatalogHealthEntry) => string = (title: string) => title
  catalogHealthColorOf: (health: CatalogHealthEntry) => ResourceColor = () => this.c.sub
  onDeleteSource: (index: number) => void = () => {}
  onEditSource: (index: number) => void = () => {}
  onToggleSourceEnabled: (index: number, enabled: boolean) => void = () => {}
  onRestoreSources: () => void = () => {}
  onSourceInput: (value: string) => void = () => {}
  onSourceAddNew: (value: boolean) => void = () => {}
  onAddSource: () => void = () => {}
  onRefreshCatalog: () => void = () => {}
  onTleFileInput: (value: string) => void = () => {}
  onImportTle: () => void = () => {}
  onPickTleFile: () => void = () => {}
  onSetAllSources: (enabled: boolean) => void = () => {}
  // 卫星倒计时（用户主动设置并开启）
  onCountdownTarget: (target: string) => void = () => {}
  onCountdownAdjust: (deltaSeconds: number) => void = () => {}
  onCountdownStart: () => void = () => {}
  onCountdownStop: () => void = () => {}
  onCountdownRemind: (minutesBefore: number) => void = () => {}
  onSetUpdateSetting: (key: string, value: boolean | number) => void = () => {}
  onUpdateFrequencyInput: (value: string) => void = () => {}
  onSubmitUpdateFrequency: () => void = () => {}
  onSetFlag: (flag: string, isOn: boolean) => void = () => {}
  onSelectGroup: (group: string) => void = () => {}
  onQueryChange: (value: string) => void = () => {}
  onSubmitQuery: () => void = () => {}
  onSearchObject: (item: SatelliteListItem) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void { this.satelliteStore.observePanel(true) }
  aboutToDisappear(): void { this.satelliteStore.observePanel(false) }

  private isZh(): boolean {
    return I18n.getLanguage().toLowerCase().startsWith('zh')
  }

  private isComplexExpanded(id: string): boolean {
    return this.expandedComplexIds.includes(id)
  }

  private toggleComplexExpanded(id: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, () => {
      if (this.expandedComplexIds.includes(id)) {
        this.expandedComplexIds = this.expandedComplexIds.filter((existing: string) => existing !== id)
      } else {
        this.expandedComplexIds = this.expandedComplexIds.concat([id])
      }
    })
  }

  private dockedMembersOf(item: SatelliteListItem): StationComplexMember[] {
    if (item.complexMembers === undefined) return []
    return item.complexMembers.filter((m: StationComplexMember) => !m.isPrimary)
  }

  private memberToListItem(member: StationComplexMember, fallbackHeightKm: number): SatelliteListItem {
    return {
      id: member.id,
      name: member.name,
      englishName: member.englishName,
      displayed: member.displayed ?? true,
      outdated: member.outdated ?? false,
      tleEpoch: '',
      lastUpdated: '',
      heightKm: fallbackHeightKm
    }
  }

  private countdownText(): string {
    const total = this.satelliteStore.countdownRemainingSeconds
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const sec = total % 60
    const mm = String(m).padStart(2, '0')
    const ss = String(sec).padStart(2, '0')
    return h > 0 ? h.toString() + ':' + mm + ':' + ss : mm + ':' + ss
  }

  private statusDotColor(): ResourceColor {
    if (this.c.isNight) return this.c.accent
    if (!this.satelliteStore.satObserverIsEarth || !this.satelliteStore.satDateInRange || this.satelliteStore.satOutdatedCount > 0) {
      return this.c.warning
    }
    return '#4DD0E1'
  }

  private compactStatusSubtitle(): string {
    if (!this.satelliteStore.satObserverIsEarth) {
      return this.isZh() ? '仅支持地球观测位置' : 'Earth observer only'
    }
    if (!this.satelliteStore.satDateInRange) {
      return this.isZh() ? '当前日期超出轨道历元范围' : 'Date outside orbit epoch range'
    }
    if (this.satelliteStore.satUpdateSettings.updateState === 0) {
      return this.isZh() ? '正在从国内镜像同步最新轨道…' : 'Syncing orbits from mirror…'
    }
    const raw = this.satelliteStore.satelliteUpdateStatusText()
    if (raw.length > 0) return raw
    return this.isZh() ? '内置轨道库就绪' : 'Built-in orbit catalog ready'
  }

  @Builder
  countdownContent() {
    Column({ space: 12 }) {
      Text(this.isZh() ? '过境倒计时' : 'Pass Countdown')
        .fontSize(15).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 8 }) {
        Button(this.isZh() ? '国际空间站' : 'ISS', { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(this.satelliteStore.countdownTarget === 'ISS' ? this.c.onAccent : this.c.text)
          .backgroundColor(this.satelliteStore.countdownTarget === 'ISS' ? this.c.accent : this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onCountdownTarget('ISS') })
        Button(this.isZh() ? '铱星闪光' : 'Iridium', { type: ButtonType.Normal })
          .fontSize(12)
          .fontColor(this.satelliteStore.countdownTarget === 'IRIDIUM' ? this.c.onAccent : this.c.text)
          .backgroundColor(this.satelliteStore.countdownTarget === 'IRIDIUM' ? this.c.accent : this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onCountdownTarget('IRIDIUM') })
      }.width('100%')
      Text(this.satelliteStore.countdownRunning
        ? (this.isZh() ? '距离设定时刻还有' : 'Time remaining')
        : (this.isZh() ? '设定时长后点击「开始」，可预约到点前 1 分钟提醒。' : 'Adjust duration and tap Start.'))
        .fontSize(12).fontColor(this.c.sub).width('100%')
      Text(this.countdownText())
        .fontSize(42).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 6, bottom: 6 })
      Row({ space: 8 }) {
        Button('−1 分', { type: ButtonType.Normal }).fontSize(12).fontColor(this.c.text).backgroundColor(this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .enabled(!this.satelliteStore.countdownRunning)
          .onClick(() => { this.onCountdownAdjust(-60) })
        Button('＋1 分', { type: ButtonType.Normal }).fontSize(12).fontColor(this.c.text).backgroundColor(this.c.input)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .enabled(!this.satelliteStore.countdownRunning)
          .onClick(() => { this.onCountdownAdjust(60) })
      }.width('100%')
      Row({ space: 8 }) {
        Button(this.satelliteStore.countdownRunning ? (this.isZh() ? '停止' : 'Stop') : (this.isZh() ? '开始' : 'Start'),
          { type: ButtonType.Normal })
          .fontSize(13).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
          .onClick(() => {
            if (this.satelliteStore.countdownRunning) this.onCountdownStop()
            else this.onCountdownStart()
          })
        Button(this.isZh() ? '提前 1 分钟提醒' : 'Remind 1m before', { type: ButtonType.Normal })
          .fontSize(12).fontColor(this.c.text).backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_CONTROL).height(38).layoutWeight(1)
          .onClick(() => { this.onCountdownRemind(1) })
      }.width('100%')
    }
      .width('100%')
      .padding(14)
      .backgroundColor(this.c.soft)
      .border({ width: 0.6, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)
  }

  @Builder
  diagnosticRow(label: string, value: string, warn: boolean = false) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).fontColor(this.c.sub).layoutWeight(1)
      Text(value)
        .fontSize(12)
        .fontColor(warn ? this.c.warning : this.c.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
    }
      .width('100%')
      .padding({ top: 6, bottom: 6 })
  }

  @Builder
  diagnosticContent() {
    Column({ space: 10 }) {
      Column({ space: 4 }) {
        Text(I18n.t('sat_data_details'))
          .fontSize(15).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%').margin({ bottom: 4 })
        this.diagnosticRow(I18n.t('c_total_count').toString(), this.satelliteStore.satCount.toString() + ' 颗')
        this.diagnosticRow(this.isZh() ? '最近检查结果' : 'Last check', this.satelliteStore.lastCheckResultText())
        if ((this.satelliteStore.satUpdateSettings.mirrorCheckedAt ?? '').length > 0) {
          this.diagnosticRow(this.isZh() ? '国内镜像状态' : 'Mirror status', this.satelliteStore.mirrorStatusText())
        }
        if ((this.satelliteStore.satUpdateSettings.lastCheckedAt ?? '').length > 0) {
          this.diagnosticRow(I18n.t('sat_last_checked').toString(),
            (this.satelliteStore.satUpdateSettings.lastCheckedAt ?? '').replace('T', ' ').replace('Z', ' UTC'))
        }
        if (this.satelliteStore.satNewestUpdate.length > 0) {
          this.diagnosticRow(I18n.t('sat_last_changed').toString(),
            this.satelliteStore.satNewestUpdate.replace('T', ' ').replace('Z', ' UTC'))
        }
        if (this.satelliteStore.satCatalogCreator.length > 0) {
          this.diagnosticRow(this.isZh() ? '内置目录版本' : 'Catalog version', this.satelliteStore.satCatalogCreator)
        }
        if (this.satelliteStore.satCatalogSnapshot.length > 0) {
          this.diagnosticRow(this.isZh() ? '内置快照时间' : 'Snapshot',
            this.satelliteStore.satCatalogSnapshot.replace('T', ' ').replace('Z', ' UTC'))
        }
      }
        .width('100%')
        .padding(14)
        .backgroundColor(this.c.soft)
        .border({ width: 0.6, color: this.c.border })
        .borderRadius(UI_RADIUS_CARD)

      Text(I18n.t('sat_checked_hint')).fontSize(12).fontColor(this.c.sub).width('100%').padding({ left: 4, right: 4 })

      if (this.satelliteStore.satOutdatedCount > 0 || !this.satelliteStore.satDateInRange || !this.satelliteStore.satObserverIsEarth) {
        Text(!this.satelliteStore.satObserverIsEarth
          ? '人造卫星仅支持地球观测位置'
          : (!this.satelliteStore.satDateInRange ? '当前模拟日期超出内置轨道数据范围' : '部分轨道历元可能已过期，建议执行一次刷新'))
          .fontSize(12)
          .fontColor(this.c.warning)
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.errorBg)
          .borderRadius(UI_RADIUS_CONTROL)
      }
    }.width('100%')
  }

  @Builder
  sourceContent() {
    Column({ space: 10 }) {
      Column({ space: 8 }) {
        Row() {
          Text(I18n.t('sat_sources_title')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
          Text(this.satelliteStore.satSourceEnabledCount() + ' / ' + this.satelliteStore.satSources.length)
            .fontSize(12).fontColor(this.c.sub)
        }.width('100%')
        Text(I18n.t('sat_merge_policy')).fontSize(12).fontColor(this.c.sub).width('100%')

        if (!OFFLINE_APPGALLERY_BUILD) {
          TextInput({ text: this.satelliteStore.satSourceInput, placeholder: I18n.t('sat_source_placeholder') })
            .height(38).fontSize(12).fontColor(this.c.text).placeholderColor(this.c.sub).width('100%')
            .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
            .onChange((value: string) => { this.onSourceInput(value) })
          Row({ space: 8 }) {
            Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satSourceAddNew }).width(42).height(24)
              .onChange((value: boolean) => { this.onSourceAddNew(value) })
            Text(I18n.t('sat_source_add_new')).fontSize(11).fontColor(this.c.sub).layoutWeight(1)
            Button(this.satelliteStore.editingSatelliteSourceIndex >= 0 ? I18n.t('sat_source_save') : I18n.t('sat_source_add'),
              { type: ButtonType.Normal })
              .fontSize(12).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 12, right: 12 })
              .onClick(() => { this.onAddSource() })
          }.width('100%').alignItems(VerticalAlign.Center)
        }

        Row({ space: 8 }) {
          Button(I18n.t('sat_source_restore'), { type: ButtonType.Normal })
            .fontSize(11).fontColor(this.c.warning).backgroundColor(this.c.errorBg)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .onClick(() => { this.onRestoreSources() })
          Text(this.satelliteStore.satelliteUpdateStatusText())
            .fontSize(11).fontColor(this.c.sub).layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').alignItems(VerticalAlign.Center)
      }
        .width('100%').padding(12).backgroundColor(this.c.soft)
        .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

      // 同步策略微调（自动收录新卫星、自动显示、自定义周期）
      Column({ space: 8 }) {
        Row() {
          Text(I18n.t('sat_auto_add')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.autoAddEnabled }).width(42).height(24)
            .onChange((value: boolean) => { this.onSetUpdateSetting('autoAddEnabled', value) })
        }.width('100%')
        Row() {
          Text(I18n.t('sat_auto_display')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.autoDisplayEnabled }).width(42).height(24)
            .onChange((value: boolean) => { this.onSetUpdateSetting('autoDisplayEnabled', value) })
        }.width('100%')
        Row({ space: 6 }) {
          Text(I18n.t('sat_update_frequency')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          TextInput({ text: this.satelliteStore.satUpdateFrequencyInput, placeholder: '24' }).height(32).fontSize(12)
            .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).width(64)
            .onChange((value: string) => { this.onUpdateFrequencyInput(value) })
            .onSubmit(() => { this.onSubmitUpdateFrequency() })
          Text(I18n.t('sat_hours')).fontSize(12).fontColor(this.c.sub)
        }.width('100%').alignItems(VerticalAlign.Center)
        Row() {
          Text(I18n.t('sat_online_updates')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.updatesEnabled })
            .enabled(!this.satelliteStore.satOffline).width(42).height(24)
            .onChange((value: boolean) => { this.onSetUpdateSetting('updatesEnabled', value) })
        }.width('100%')
      }
        .width('100%').padding(12).backgroundColor(this.c.soft)
        .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

      if (!OFFLINE_APPGALLERY_BUILD && this.satelliteStore.satSources.length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(I18n.t('sat_add_from_sources')).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.text)
              Text(this.satelliteStore.satSourceEnabledCount() + ' / ' + this.satelliteStore.satSources.length)
                .fontSize(11).fontColor(this.c.sub)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satSourceEnabledCount() === this.satelliteStore.satSources.length })
              .width(44).height(24)
              .onChange((value: boolean) => { this.onSetAllSources(value) })
          }
            .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)

          ForEach(this.satelliteStore.satSources, (source: SatelliteSource, sourceIndex: number) => {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Column({ space: 2 }) {
                  Text((source.local ? I18n.t('sat_source_local') : I18n.t('sat_source_remote')) + ' · ' + source.scheme.toUpperCase())
                    .fontSize(11).fontColor(source.valid ? this.c.fourth : this.c.warning).maxLines(1)
                  Text(source.url).fontSize(10.5).fontColor(this.c.sub)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: source.addNew }).width(40).height(22)
                  .onChange((value: boolean) => { this.onToggleSourceEnabled(sourceIndex, value) })
                Button(I18n.t('sat_source_edit'), { type: ButtonType.Normal })
                  .fontSize(10.5).fontColor(this.c.text).backgroundColor(this.c.softStrong)
                  .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
                  .onClick(() => {
                    this.onEditSource(sourceIndex)
                    this.panelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
                  })
                Button(I18n.t('sat_source_delete'), { type: ButtonType.Normal })
                  .fontSize(10.5).fontColor(this.c.warning).backgroundColor(this.c.errorBg)
                  .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
                  .onClick(() => { this.onDeleteSource(sourceIndex) })
              }.width('100%').alignItems(VerticalAlign.Center)
              Text(this.satelliteStore.satelliteSourcePreview(source.url)).fontSize(10).fontColor(this.c.sub).width('100%')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).height(14)
            }
              .width('100%').padding({ left: 10, right: 10, top: 7, bottom: 7 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
          }, (source: SatelliteSource) => source.index.toString() + ':' + source.url)
        }
          .width('100%').padding(10).backgroundColor(this.c.soft)
          .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
      }

      if (this.satelliteStore.satSourceStatus.length > 0) {
        Text(this.satelliteStore.satSourceStatus).fontSize(11).fontColor(this.c.fourth).width('100%').maxLines(3)
      }
    }.width('100%')
  }

  @Builder
  importContent() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Text(I18n.t('sat_import_settings')).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%')
        Text(I18n.t('sat_merge_policy')).fontSize(12).fontColor(this.c.sub).width('100%')
        Button(I18n.t('sat_choose_orbit_file'), { type: ButtonType.Normal })
          .fontSize(14).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_CONTROL).height(42).width('100%')
          .enabled(this.satelliteStore.satUpdateSettings.updateState !== 0)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onPickTleFile() })
        TextInput({ text: this.satelliteStore.satTleFileInput, placeholder: I18n.t('sat_tle_path_placeholder') })
          .height(40).fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub)
          .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL).width('100%')
          .onChange((value: string) => { this.onTleFileInput(value) })
        Button(I18n.t('sat_tle_import'), { type: ButtonType.Normal })
          .fontSize(13).fontColor(this.c.text).backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_CONTROL).height(40).width('100%')
          .enabled(this.satelliteStore.satTleFileInput.trim().length > 0 && this.satelliteStore.satUpdateSettings.updateState !== 0)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onImportTle() })
      }
        .width('100%').padding(14).backgroundColor(this.c.soft)
        .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

      if (this.satelliteStore.satSourceStatus.length > 0) {
        Text(this.satelliteStore.satSourceStatus).fontSize(12).fontColor(this.c.fourth).width('100%')
      }
    }.width('100%')
  }

  @Builder
  displayToggleRow(label: ResourceStr, isOn: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(14).fontColor(this.c.text).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange((v: boolean) => { onChange(v) })
    }
      .width('100%')
      .constraintSize({ minHeight: 46 })
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.c.bg)
      .borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  displayContent() {
    Column({ space: 8 }) {
      Text(I18n.t('sat_display_settings'))
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.text).width('100%').padding({ left: 2 })
      this.displayToggleRow(I18n.t('c_show_labels'), this.satelliteStore.satLabels, (v: boolean) => { this.onSetFlag('labels', v) })
      this.displayToggleRow(I18n.t('c_show_orbits'), this.satelliteStore.satOrbitLines, (v: boolean) => { this.onSetFlag('orbitLines', v) })
      Text(I18n.t('sat_orbit_preview_hint')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 4, right: 4 })
      this.displayToggleRow(I18n.t('c_show_hints'), this.satelliteStore.satHints, (v: boolean) => { this.onSetFlag('hints', v) })
      this.displayToggleRow(I18n.t('c_icon_mode'), this.satelliteStore.satIconicMode, (v: boolean) => { this.onSetFlag('iconicMode', v) })
      this.displayToggleRow(I18n.t('c_hide_invisible'), this.satelliteStore.satHideInvisible, (v: boolean) => { this.onSetFlag('hideInvisible', v) })
    }
      .width('100%').padding(12).backgroundColor(this.c.soft)
      .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
  }

  @Builder
  catalogContent() {
    Column({ space: 10 }) {
      // 现代搜索框（带一键清空）
      Row({ space: 6 }) {
        TextInput({
          text: this.satelliteStore.satQuery,
          placeholder: this.isZh() ? '搜索空间站、卫星名称或 NORAD 编号' : 'Search station, satellite or NORAD ID'
        })
          .height(38)
          .fontSize(13)
          .fontColor(this.c.text)
          .placeholderColor(this.c.sub)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .onChange((value: string) => { this.onQueryChange(value) })
          .onSubmit(() => { this.onSubmitQuery() })
        if (this.satelliteStore.satQuery.length > 0) {
          Button('×', { type: ButtonType.Circle })
            .width(24).height(24).fontSize(14).fontColor(this.c.sub).backgroundColor(this.c.softStrong)
            .onClick(() => { this.onQueryChange('') })
        }
      }
        .width('100%')
        .padding({ left: 8, right: 8 })
        .backgroundColor(this.c.input)
        .border({ width: 1, color: this.c.inputBorder })
        .borderRadius(UI_RADIUS_CONTROL)
        .alignItems(VerticalAlign.Center)

      // 横向分组胶囊条（无嵌套竖向滚动）
      SatelliteGroupSelector({
        groups: this.satelliteStore.satGroups,
        activeGroup: this.satelliteStore.activeSatGroup,
        loading: this.satelliteStore.satelliteListLoading,
        scroller: this.groupScroller,
        onGroupScroll: () => { this.onPublishState() },
        onSelect: (group: string) => { this.onSelectGroup(group) }
      })

      if (this.satelliteStore.satItems.length > 0) {
        Row() {
          Text(this.isZh()
            ? `共匹配 ${this.satelliteStore.satMatchedCount} 颗 · 点击直飞星图追踪`
            : `${this.satelliteStore.satMatchedCount} matched · tap to track`)
            .fontSize(11.5)
            .fontColor(this.c.sub)
            .layoutWeight(1)
        }.width('100%').padding({ left: 2, right: 2 })

        ForEach(this.satelliteStore.satItems, (item: SatelliteListItem) => {
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              Stack({ alignContent: Alignment.Center }) {
                Circle()
                  .width(38)
                  .height(38)
                  .fill(satelliteVisualProfile(classifySatelliteArchetype(item.englishName + ' ' + item.name, item.id, this.satelliteStore.activeSatGroup)).glowHex)
                  .opacity(0.24)
                Image(satelliteIconResource(classifySatelliteArchetype(item.englishName + ' ' + item.name, item.id, this.satelliteStore.activeSatGroup)))
                  .width(26)
                  .height(26)
                  .objectFit(ImageFit.Contain)
                  .draggable(false)
              }
                .width(38)
                .height(38)

              Column({ space: 3 }) {
                Row({ space: 6 }) {
                  Text(item.name)
                    .fontSize(14)
                    .fontColor(this.c.text)
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                  Text(satelliteVisualProfile(classifySatelliteArchetype(item.englishName + ' ' + item.name, item.id, this.satelliteStore.activeSatGroup)).categoryLabelZh)
                    .fontSize(10)
                    .fontColor(satelliteVisualProfile(classifySatelliteArchetype(item.englishName + ' ' + item.name, item.id, this.satelliteStore.activeSatGroup)).accentHex)
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                    .backgroundColor(this.c.input)
                    .borderRadius(UI_RADIUS_PILL)
                  if (item.outdated) {
                    Text(this.isZh() ? '历元旧' : 'Old')
                      .fontSize(10)
                      .fontColor(this.c.warning)
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .backgroundColor(this.c.errorBg)
                      .borderRadius(UI_RADIUS_PILL)
                  }
                }.width('100%').alignItems(VerticalAlign.Center)

                Text('NORAD ' + item.id + (item.heightKm > 0 ? ' · 轨道 ' + item.heightKm.toFixed(0) + ' km' : '') + (item.englishName !== item.name ? (' · ' + item.englishName) : ''))
                  .fontSize(11)
                  .fontColor(this.c.sub)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if ((item.complexParentName ?? '').length > 0) {
                  Text('对接于 · ' + (item.complexParentName ?? '') + ((item.complexRole ?? '').length > 0 ? ' · ' + (item.complexRole ?? '') : ''))
                    .fontSize(10.5)
                    .fontColor(this.c.accent)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                } else if ((item.deployedFrom ?? '').length > 0) {
                  Text('释放自 · ' + (item.deployedFrom ?? '') + ((item.deploymentDate ?? '').length > 0 ? ' · ' + (item.deploymentDate ?? '') : ''))
                    .fontSize(10.5)
                    .fontColor(this.c.tertiary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)

              Text('›').fontSize(16).fontColor(this.c.sub).opacity(0.75)
            }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .onClick(() => { this.onSearchObject(item) })

            if (item.complexMembers !== undefined && item.complexMembers.length > 1) {
              Row({ space: 6 }) {
                Text((item.complexName ?? '空间站组合体') + ' · 共 ' + (item.complexCount ?? item.complexMembers.length).toString() + ' 个在轨舱段/飞船')
                  .fontSize(11)
                  .fontColor(this.c.accent)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(this.isComplexExpanded(item.id) ? '收起 ▴' : '展开舱段 ▾')
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.accent)
              }
                .id('sat-complex-toggle-' + item.id)
                .width('100%')
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .backgroundColor(this.c.softStrong)
                .border({ width: 0.5, color: this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.toggleComplexExpanded(item.id) })

              if (this.isComplexExpanded(item.id)) {
                Column({ space: 5 }) {
                  ForEach(this.dockedMembersOf(item), (member: StationComplexMember) => {
                    Row({ space: 8 }) {
                      Column()
                        .width(2)
                        .height(26)
                        .backgroundColor(this.c.accent)
                        .opacity(0.45)
                        .borderRadius(1)
                      Column({ space: 2 }) {
                        Row({ space: 6 }) {
                          Text(member.name)
                            .fontSize(12.5)
                            .fontColor(this.c.text)
                            .maxLines(1)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .layoutWeight(1)
                          Text(member.roleLabel)
                            .fontSize(10)
                            .fontColor(this.c.sub)
                            .padding({ left: 6, right: 6, top: 1.5, bottom: 1.5 })
                            .backgroundColor(this.c.input)
                            .borderRadius(UI_RADIUS_MEDIA)
                        }.width('100%').alignItems(VerticalAlign.Center)
                        Text('NORAD ' + member.id + (member.englishName !== member.name ? ' · ' + member.englishName : ''))
                          .fontSize(10)
                          .fontColor(this.c.sub)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                      Text('›').fontSize(14).fontColor(this.c.sub)
                    }
                      .width('100%')
                      .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                      .backgroundColor(this.c.soft)
                      .borderRadius(UI_RADIUS_CONTROL)
                      .onClick(() => { this.onSearchObject(this.memberToListItem(member, item.heightKm)) })
                  }, (member: StationComplexMember) => item.id + '-member-' + member.id)
                }
                  .width('100%')
                  .padding({ left: 4, top: 2 })
              }
            }
          }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c.bg)
            .border({ width: 0.6, color: this.c.border })
            .borderRadius(UI_RADIUS_CARD)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.99 })
        }, (item: SatelliteListItem) => item.id)
      } else if (this.satelliteStore.satQuery.length > 0) {
        Column({ space: 6 }) {
          Text(this.isZh() ? '未找到匹配的卫星' : 'No matching satellites')
            .fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium)
          Text(this.isZh() ? '可尝试切换上方分组，或在高级设置中刷新最新轨道目录。' : 'Try another group or refresh orbits in Advanced.')
            .fontSize(11.5).fontColor(this.c.sub)
        }
          .width('100%').padding(14).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
          .alignItems(HorizontalAlign.Start)
      }
    }.width('100%')
  }

  private sectionDepth(section: string): number {
    if (section === 'main') return 0
    if (section === 'settings') return 1
    return 2
  }

  private sectionTransition(): TransitionEffect {
    const enterX = this.sectionDirection >= 0 ? 22 : -22
    const exitX = this.sectionDirection >= 0 ? -16 : 16
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: enterX, y: 0 }).animation({ duration: 260, curve: curves.springMotion(0.55, 0.88) })),
      TransitionEffect.OPACITY.animation({ duration: 140, curve: Curve.EaseIn })
        .combine(TransitionEffect.translate({ x: exitX, y: 0 }).animation({ duration: 180, curve: Curve.EaseIn }))
    )
  }

  private openSection(section: string): void {
    const prevDepth = this.sectionDepth(this.satelliteStore.satPanelSection)
    const nextDepth = this.sectionDepth(section)
    this.sectionDirection = nextDepth >= prevDepth ? 1 : -1
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.satelliteStore.satPanelSection = section
    })
    if (section === 'diagnostics') this.satelliteStore.loadSatellites(true)
    this.panelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: true })
    this.onPublishState()
  }

  @Builder
  advancedMenuItem(titleKey: string, subtitle: string, section: string, compactPill: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      if (compactPill) {
        Text(this.isZh() ? '高级' : 'More')
          .fontSize(12)
          .fontColor(this.c.text)
      } else {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(I18n.t(titleKey))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.text)
              .maxLines(1)
            Text(subtitle)
              .fontSize(11.5)
              .fontColor(this.c.sub)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Text('›').fontSize(18).fontColor(this.c.sub)
        }
          .width('100%')
          .padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .alignItems(VerticalAlign.Center)
      }
    }
      .id('satellites-' + section)
      .width(compactPill ? 'auto' : '100%')
      .height(compactPill ? 32 : 'auto')
      .padding(compactPill ? { left: 11, right: 11 } : 0)
      .backgroundColor(compactPill ? this.c.softStrong : this.c.bg)
      .border(compactPill ? { width: 0 } : { width: 0.6, color: this.c.border })
      .borderRadius(compactPill ? UI_RADIUS_PILL : UI_RADIUS_CARD)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: compactPill ? 0.96 : 0.99 })
      .onClick(() => { this.openSection(section) })
  }

  @Builder
  advancedSettingsContent() {
    Column({ space: 12 }) {
      // 1. 轨道自动同步卡片（从主屏收纳至此，保持主屏极简）
      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Text(this.isZh() ? '轨道自动同步' : 'Auto Orbit Sync')
            .fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.text)
          InfoTipButton({
            title: this.isZh() ? '轨道自动同步' : 'Auto Orbit Sync',
            tip: this.isZh()
              ? '开启后按设定周期通过国内镜像 skyinstrument.cn 校验 SHA-256 并静默更新轨道，不上传观测位置或设备标识。'
              : 'Periodically updates satellite orbits via domestic mirror skyinstrument.cn with SHA-256 verification and zero personal data upload.'
          })
          Blank()
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.updatesEnabled })
            .enabled(!this.satelliteStore.satOffline && this.satelliteStore.satUpdateSettings.updateState !== 0)
            .onChange((value: boolean) => { this.onSetUpdateSetting('updatesEnabled', value) })
        }.width('100%').alignItems(VerticalAlign.Center)

        if (this.satelliteStore.satUpdateSettings.updatesEnabled && !this.satelliteStore.satOffline) {
          Row({ space: 6 }) {
            Text(this.isZh() ? '刷新周期' : 'Interval').fontSize(12).fontColor(this.c.sub).layoutWeight(1)
            ForEach([2, 6, 12, 24], (hours: number) => {
              Text(`${hours}h`)
                .fontSize(11.5)
                .fontWeight(this.satelliteStore.satUpdateSettings.updateFrequencyHours === hours ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.satelliteStore.satUpdateSettings.updateFrequencyHours === hours ? this.c.onAccent : this.c.text)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor(this.satelliteStore.satUpdateSettings.updateFrequencyHours === hours ? this.c.accent : this.c.softStrong)
                .borderRadius(UI_RADIUS_PILL)
                .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
                .onClick(() => { this.onSetUpdateSetting('updateFrequencyHours', hours) })
            }, (hours: number) => String(hours))
          }.width('100%').alignItems(VerticalAlign.Center)
        }
      }
        .width('100%').padding(14).backgroundColor(this.c.soft)
        .border({ width: 0.6, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

      // 2. 进阶功能导航卡片组
      Column({ space: 8 }) {
        this.advancedMenuItem('sat_display_settings',
          this.isZh() ? '轨道线、名称标签、图标模式与可见性过滤' : 'Orbit lines, labels, icons & visibility',
          'display')
        this.advancedMenuItem('sat_sources_title',
          this.isZh()
            ? `管理镜像与自定义轨道源（已启用 ${this.satelliteStore.satSourceEnabledCount()}/${this.satelliteStore.satSources.length}）`
            : `Manage mirror & custom TLE sources (${this.satelliteStore.satSourceEnabledCount()}/${this.satelliteStore.satSources.length})`,
          'sources')
        this.advancedMenuItem('sat_import_settings',
          this.isZh() ? '从本机文件手动导入 TLE / 3LE / CSV 轨道' : 'Import local TLE / 3LE / CSV orbit files',
          'imports')
        this.advancedMenuItem('sat_timer_settings',
          this.isZh() ? '手动设置过境倒计时与提前提醒' : 'Manual pass countdown & alert',
          'countdown')
        this.advancedMenuItem('sat_data_details',
          this.isZh() ? '查看镜像健康状态、同步时间与内置快照' : 'Mirror health, sync times & snapshot info',
          'diagnostics')
      }.width('100%')
    }.width('100%')
  }

  build() {
    Scroll(this.panelScroller) {
      Column({ space: 12 }) {
        if (this.satelliteStore.satPanelSection !== 'main') {
          Button(this.satelliteStore.satPanelSection === 'settings'
            ? (this.isZh() ? '‹  返回卫星列表' : '‹  Satellites')
            : (this.isZh() ? '‹  返回高级设置' : '‹  Advanced'), { type: ButtonType.Normal })
            .id('satellites-back')
            .fontSize(13).fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL).height(36).padding({ left: 14, right: 14 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .transition(TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -10, y: 0 }).animation({ duration: 200, curve: Curve.EaseOut })))
            .onClick(() => { this.openSection(this.satelliteStore.satPanelSection === 'settings' ? 'main' : 'settings') })
        }
        if (this.satelliteStore.satPanelSection === 'main') {
          Column({ space: 10 }) {
            // 极简顶部状态与操作条（所有复杂选项收敛在「高级」里）
            Row({ space: 8 }) {
              if (this.satelliteStore.satUpdateSettings.updateState === 0) {
                LoadingProgress().width(16).height(16).color(this.c.accent)
              } else {
                Circle({ width: 8, height: 8 }).fill(this.statusDotColor())
              }
              Column({ space: 2 }) {
                Text((this.isZh() ? '在轨目录' : 'Orbit Catalog') + ' · ' + this.satelliteStore.satCount.toString())
                  .fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(this.c.text).maxLines(1)
                Text(this.compactStatusSubtitle())
                  .fontSize(11).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)

              Button(this.satelliteStore.satUpdateSettings.updateState === 0
                ? (this.isZh() ? '同步中' : 'Syncing')
                : (this.isZh() ? '刷新' : 'Sync'), { type: ButtonType.Normal })
                .id('satellites-refresh')
                .height(32).padding({ left: 11, right: 11 }).fontSize(12)
                .fontColor(this.c.onAccent).backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_PILL)
                .enabled(!this.satelliteStore.satOffline && this.satelliteStore.satUpdateSettings.updateState !== 0)
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onRefreshCatalog() })

              this.advancedMenuItem('sat_advanced', '', 'settings', true)
            }
              .width('100%')
              .padding({ left: 12, right: 10, top: 10, bottom: 10 })
              .backgroundColor(this.c.soft)
              .border({ width: 0.6, color: this.c.border })
              .borderRadius(UI_RADIUS_CARD)
              .alignItems(VerticalAlign.Center)

            this.catalogContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'settings') {
          Column({ space: 12 }) {
            this.advancedSettingsContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'sources') {
          Column({ space: 10 }) {
            this.sourceContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'imports') {
          Column({ space: 10 }) {
            this.importContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'display') {
          Column({ space: 10 }) {
            this.displayContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'countdown') {
          Column({ space: 10 }) {
            this.countdownContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        } else if (this.satelliteStore.satPanelSection === 'diagnostics') {
          Column({ space: 10 }) {
            this.diagnosticContent()
          }.width('100%').alignItems(HorizontalAlign.Start).transition(this.sectionTransition())
        }
      }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
      .align(Alignment.TopStart)
      .onScroll(() => { this.onPublishState() })
  }
}
