import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { SatelliteListItem, SatelliteSource, SatelliteUpdateSettings, CatalogHealthEntry, OFFLINE_APPGALLERY_BUILD } from '../../pages/MainWindowModels'
import { SatelliteGroupSelector } from '../satellite/SatelliteGroupSelector'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { SatelliteStore } from '../../state/SatelliteStore'

// 卫星面板，对应 `activePanel === 'satellites'`。
//
// 域状态集中在 SatelliteStore（@ObjectLink），刷新粒度收缩到订阅该 store 的组件；
// 文本输入/开关/刷新/导入/删除/分组选择/检索等动作回调注入宿主，组件不修改 store。
// 两个 Scroller 以普通成员传入：宿主仍持有同一实例供 publishSatellitePanelState 读取。

@Component
export struct SatellitesPanel {
  @ObjectLink satelliteStore: SatelliteStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
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

  // 倒计时文本（mm:ss / h:mm:ss）
  private countdownText(): string {
    const total = this.satelliteStore.countdownRemainingSeconds
    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const sec = total % 60
    const mm = String(m).padStart(2, '0')
    const ss = String(sec).padStart(2, '0')
    return h > 0 ? h.toString() + ':' + mm + ':' + ss : mm + ':' + ss
  }

  @Builder
  countdownContent() {
        // —— 卫星倒计时：用户选目标、设定时长、主动开始 ——
        Column({ space: 8 }) {
          Text('卫星倒计时').fontSize(13).fontColor(this.c.text).width('100%').fontWeight(FontWeight.Medium)
          Row({ space: 8 }) {
            Button('国际空间站')
              .fontSize(11).fontColor(this.satelliteStore.countdownTarget === 'ISS' ? '#FFFFFF' : this.c.text)
              .backgroundColor(this.satelliteStore.countdownTarget === 'ISS' ? this.c.accent : this.c.input)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .onClick(() => { this.onCountdownTarget('ISS') })
            Button('铱星闪光')
              .fontSize(11).fontColor(this.satelliteStore.countdownTarget === 'IRIDIUM' ? '#FFFFFF' : this.c.text)
              .backgroundColor(this.satelliteStore.countdownTarget === 'IRIDIUM' ? this.c.accent : this.c.input)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .onClick(() => { this.onCountdownTarget('IRIDIUM') })
          }.width('100%')
          Text(this.satelliteStore.countdownRunning ? '距离你设定的时刻还有' : '设定时长后点「开始」，到点前按提前量提醒。')
            .fontSize(10).fontColor(this.c.sub).width('100%')
          Text(this.countdownText())
            .fontSize(40).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
            .textAlign(TextAlign.Center)
          Row({ space: 8 }) {
            Button('−1 分').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.input)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .enabled(!this.satelliteStore.countdownRunning)
              .onClick(() => { this.onCountdownAdjust(-60) })
            Button('＋1 分').fontSize(11).fontColor(this.c.text).backgroundColor(this.c.input)
              .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .enabled(!this.satelliteStore.countdownRunning)
              .onClick(() => { this.onCountdownAdjust(60) })
          }.width('100%')
          Row({ space: 8 }) {
            Button(this.satelliteStore.countdownRunning ? '停止' : '开始')
              .fontSize(12).fontColor('#FFFFFF').backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
              .onClick(() => {
                if (this.satelliteStore.countdownRunning) this.onCountdownStop()
                else this.onCountdownStart()
              })
            Button('提前 1 分钟提醒')
              .fontSize(11).fontColor(this.c.text).backgroundColor(this.c.input)
              .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
              .onClick(() => { this.onCountdownRemind(1) })
          }.width('100%')
        }
        .width('100%').padding(12)
        .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
        .margin({ bottom: 4 })
  }

  @Builder
  diagnosticContent() {
        Column({ space: 3 }) {
          Text(I18n.t('sat_orbital_data') + ' · ' + this.satelliteStore.satCount.toString())
            .fontSize(15).fontColor(this.c.text).fontWeight(FontWeight.Medium)
          Text(this.satelliteStore.lastCheckResultText()).fontSize(13).fontColor(this.c.sub).width('100%')
          if ((this.satelliteStore.satUpdateSettings.mirrorCheckedAt ?? '').length > 0) {
            Text(this.satelliteStore.mirrorStatusText()).fontSize(12).fontColor(this.c.sub).width('100%')
          }
          if ((this.satelliteStore.satUpdateSettings.lastCheckedAt ?? '').length > 0) {
            Text(I18n.t('sat_last_checked') + ': ' + (this.satelliteStore.satUpdateSettings.lastCheckedAt ?? '').replace('T', ' ').replace('Z', ' UTC'))
              .fontSize(12).fontColor(this.c.sub).width('100%')
          }
          if (this.satelliteStore.satNewestUpdate.length > 0) {
            Text(I18n.t('sat_last_changed') + ': ' + this.satelliteStore.satNewestUpdate.replace('T', ' ').replace('Z', ' UTC'))
              .fontSize(12).fontColor(this.c.sub).width('100%')
          }
          Text(I18n.t('sat_checked_hint')).fontSize(12).fontColor(this.c.sub).width('100%')
          if (this.satelliteStore.satCatalogCreator.length > 0) {
            Text('内置目录版本：' + this.satelliteStore.satCatalogCreator).fontSize(11).fontColor(this.c.sub).width('100%')
          }
          if (this.satelliteStore.satCatalogSnapshot.length > 0) {
            Text('内置快照：' + this.satelliteStore.satCatalogSnapshot.replace('T', ' ').replace('Z', ' UTC')).fontSize(10).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          if (this.satelliteStore.satOutdatedCount > 0 || !this.satelliteStore.satDateInRange || !this.satelliteStore.satObserverIsEarth) {
            Text(!this.satelliteStore.satObserverIsEarth ? '人造卫星仅支持地球观测位置' : (!this.satelliteStore.satDateInRange ? '当前模拟日期超出内置轨道数据范围' : '部分轨道历元可能已过期'))
              .fontSize(11).fontColor(this.c.warning).maxLines(2)
          }
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  sourceContent() {
        Column({ space: 7 }) {
          Row() {
            Text(I18n.t('sat_sources_title')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
            Text(this.satelliteStore.satSources.length.toString()).fontSize(11).fontColor(this.c.sub)
          }.width('100%')
          Text(I18n.t('sat_merge_policy')).fontSize(12).fontColor(this.c.sub).width('100%')
          if (!OFFLINE_APPGALLERY_BUILD) {
            TextInput({ text: this.satelliteStore.satSourceInput, placeholder: I18n.t('sat_source_placeholder') })
              .height(36).fontSize(11).fontColor(this.c.text).placeholderColor(this.c.sub).width('100%')
              .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.onSourceInput(value) })
            Row({ space: 6 }) {
              Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satSourceAddNew }).width(42).height(24)
                .onChange((value: boolean) => { this.onSourceAddNew(value) })
              Text(I18n.t('sat_source_add_new')).fontSize(10).fontColor(this.c.chipInactiveText).layoutWeight(1)
              Button(this.satelliteStore.editingSatelliteSourceIndex >= 0 ? I18n.t('sat_source_save') : I18n.t('sat_source_add')).fontSize(11).fontColor(this.c.fourth).backgroundColor(this.c.softStrong)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onAddSource() })
            }.width('100%')
          }
          if (!OFFLINE_APPGALLERY_BUILD && this.satelliteStore.satSources.length > 0) {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(I18n.t('sat_add_from_sources')).fontSize(12).fontColor(this.c.text)
                Text(this.satelliteStore.satSourceEnabledCount() + ' / ' + this.satelliteStore.satSources.length)
                  .fontSize(10).fontColor(this.c.sub)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satSourceEnabledCount() === this.satelliteStore.satSources.length })
                .width(44).height(24)
                .onChange((value: boolean) => { this.onSetAllSources(value) })
            }
            .width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
            .margin({ bottom: 4 })
            ForEach(this.satelliteStore.satSources, (source: SatelliteSource, sourceIndex: number) => {
              Column({ space: 4 }) {
                Row({ space: 6 }) {
                  Column({ space: 2 }) {
                    Text((source.local ? I18n.t('sat_source_local') : I18n.t('sat_source_remote')) + ' · ' + source.scheme.toUpperCase())
                      .fontSize(11).fontColor(source.valid ? this.c.fourth : this.c.warning).maxLines(1)
                    // 单行省略：这里以前用了 layoutWeight(1)，在垂直 Column 里会撑满剩余高度，
                    // 每条来源被拉成半屏高，列表看着“特别大”。
                    Text(source.url).fontSize(10).fontColor(this.c.sub)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (source.addNew) Text(I18n.t('sat_source_add_new')).fontSize(10).fontColor(this.c.chipInactiveText)
                  Toggle({ type: ToggleType.Switch, isOn: source.addNew }).width(40).height(22)
                    .onChange((value: boolean) => { this.onToggleSourceEnabled(sourceIndex, value) })
                  Button(I18n.t('sat_source_edit')).fontSize(10).fontColor(this.c.fourth).backgroundColor(this.c.softStrong)
                    .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
                    .onClick(() => {
                      this.onEditSource(sourceIndex)
                      this.panelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
                    })
                  Button(I18n.t('sat_source_delete')).fontSize(10).fontColor(this.c.warning).backgroundColor(this.c.errorBg)
                    .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
                    .onClick(() => { this.onDeleteSource(sourceIndex) })
                }.width('100%')
                Text(this.satelliteStore.satelliteSourcePreview(source.url)).fontSize(10).fontColor(this.c.sub).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).height(14)
              }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            }, (source: SatelliteSource) => source.index.toString() + ':' + source.url)
          }
          Row({ space: 6 }) {
            Button(I18n.t('sat_source_restore')).fontSize(10).fontColor(this.c.warning).backgroundColor(this.c.errorBg)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 }).onClick(() => { this.onRestoreSources() })
            Text(this.satelliteStore.satelliteUpdateStatusText()).fontSize(10).fontColor(this.c.detailSub).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%')
          Row() {
            Text(I18n.t('sat_auto_add')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.autoAddEnabled }).width(42).height(24)
              .onChange((value: boolean) => { this.onSetUpdateSetting('autoAddEnabled', value) })
          }.width('100%')
          Row() {
            Text(I18n.t('sat_auto_display')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.autoDisplayEnabled }).width(42).height(24)
              .onChange((value: boolean) => { this.onSetUpdateSetting('autoDisplayEnabled', value) })
          }.width('100%')
          Row({ space: 6 }) {
            Text(I18n.t('sat_update_frequency')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
            TextInput({ text: this.satelliteStore.satUpdateFrequencyInput, placeholder: '72' }).height(30).fontSize(11)
              .fontColor(this.c.text).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).width(66)
              .onChange((value: string) => { this.onUpdateFrequencyInput(value) })
              .onSubmit(() => { this.onSubmitUpdateFrequency() })
            Text(I18n.t('sat_hours')).fontSize(10).fontColor(this.c.sub)
          }.width('100%')
          Row() {
            Text(I18n.t('sat_online_updates')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.updatesEnabled })
              .enabled(!this.satelliteStore.satOffline).width(42).height(24)
              .onChange((value: boolean) => { this.onSetUpdateSetting('updatesEnabled', value) })
          }.width('100%')
          if (this.satelliteStore.satSourceStatus.length > 0) Text(this.satelliteStore.satSourceStatus).fontSize(10).fontColor(this.c.fourth).width('100%').maxLines(3)
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  importContent() {
    Column({ space: 12 }) {
      Text(I18n.t('sat_import_settings')).fontSize(16).fontColor(this.c.text).width('100%')
      Text(I18n.t('sat_merge_policy')).fontSize(13).fontColor(this.c.sub).width('100%')
          Column({ space: 10 }) {
            Button(I18n.t('sat_choose_orbit_file')).fontSize(14).fontColor(this.c.text).backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL).height(44).width('100%')
              .enabled(this.satelliteStore.satUpdateSettings.updateState !== 0)
              .onClick(() => { this.onPickTleFile() })
            TextInput({ text: this.satelliteStore.satTleFileInput, placeholder: I18n.t('sat_tle_path_placeholder') }).height(44).fontSize(14)
              .fontColor(this.c.text).placeholderColor(this.c.sub).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).width('100%')
              .onChange((value: string) => { this.onTleFileInput(value) })
            Button(I18n.t('sat_tle_import')).fontSize(14).fontColor(this.c.fourth).backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL).height(44).width('100%').padding({ left: 8, right: 8 })
              .enabled(this.satelliteStore.satTleFileInput.trim().length > 0 && this.satelliteStore.satUpdateSettings.updateState !== 0)
              .onClick(() => { this.onImportTle() })
          }.width('100%')

      if (this.satelliteStore.satSourceStatus.length > 0) {
        Text(this.satelliteStore.satSourceStatus).fontSize(13).fontColor(this.c.fourth).width('100%')
      }
    }.width('100%')
  }

  @Builder
  displayContent() {
        Row() {
          Text(I18n.t('c_total_count')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Text(this.satelliteStore.satCount.toString()).fontSize(13).fontColor(this.c.sub)
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_show_labels')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satLabels })

            .onChange((isOn: boolean) => { this.onSetFlag('labels', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_show_orbits')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satOrbitLines })

            .onChange((isOn: boolean) => { this.onSetFlag('orbitLines', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Text(I18n.t('sat_orbit_preview_hint')).fontSize(11).fontColor(this.c.sub).width('100%')
        Row() {
          Text(I18n.t('c_show_hints')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satHints })

            .onChange((isOn: boolean) => { this.onSetFlag('hints', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_icon_mode')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satIconicMode })

            .onChange((isOn: boolean) => { this.onSetFlag('iconicMode', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('c_hide_invisible')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satHideInvisible })

            .onChange((isOn: boolean) => { this.onSetFlag('hideInvisible', isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
  }

  @Builder
  catalogContent() {
        SatelliteGroupSelector({
          groups: this.satelliteStore.satGroups,
          activeGroup: this.satelliteStore.activeSatGroup,
          loading: this.satelliteStore.satelliteListLoading,
          scroller: this.groupScroller,
          onGroupScroll: () => { this.onPublishState() },
          onSelect: (group: string) => { this.onSelectGroup(group) }
        })
        TextInput({ text: this.satelliteStore.satQuery, placeholder: '搜索卫星名称或 NORAD 编号' })
          .height(36).fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub)
          .backgroundColor(this.c.input).border({ width: 1, color: this.c.inputBorder }).borderRadius(UI_RADIUS_CONTROL)
          .width('100%')
          .onChange((value: string) => { this.onQueryChange(value) })
          .onSubmit(() => { this.onSubmitQuery() })
        if (this.satelliteStore.satItems.length > 0) {
          Text('匹配卫星 ' + this.satelliteStore.satMatchedCount.toString() + ' 颗').fontSize(12).fontColor(this.c.sub).width('100%').padding({ left: 2 })
          ForEach(this.satelliteStore.satItems, (item: SatelliteListItem) => {
            Column({ space: 3 }) {
              Row({ space: 8 }) {
                Column({ space: 1 }) {
                  Text(item.name).fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (item.englishName !== item.name) {
                    Text(item.englishName).fontSize(10).fontColor(this.c.sub).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (item.outdated) {
                  Text('历元过期').fontSize(10).fontColor(this.c.warning)
                }
              }.width('100%')
              Text('NORAD ' + item.id + (item.heightKm > 0 ? ' · 高度 ' + item.heightKm.toFixed(0) + ' km' : ''))
                .fontSize(10).fontColor(this.c.sub).maxLines(1)
            }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onSearchObject(item) })
          }, (item: SatelliteListItem) => item.id)
        } else if (this.satelliteStore.satQuery.length > 0) {
          Text('未找到匹配的内置卫星').fontSize(12).fontColor(this.c.sub).width('100%').padding({ left: 4, top: 4, bottom: 4 })
        }
  }

  private openSection(section: string): void {
    this.satelliteStore.satPanelSection = section
    if (section === 'diagnostics') this.satelliteStore.loadSatellites(true)
    this.panelScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false })
    this.onPublishState()
  }

  @Builder
  sectionButton(title: string, section: string) {
    Button(I18n.t(title) + '  ›')
      .id('satellites-' + section).fontSize(15).fontColor(this.c.text)
      .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
      .width('100%').height(46)
      .onClick(() => { this.openSection(section) })
  }

  build() {
    Scroll(this.panelScroller) {
      Column({ space: 12 }) {
        if (this.satelliteStore.satPanelSection !== 'main') {
          Button(I18n.t('sat_back'))
            .id('satellites-back').fontSize(14).fontColor(this.c.fourth)
            .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).height(40)
            .onClick(() => { this.openSection(this.satelliteStore.satPanelSection === 'settings' ? 'main' : 'settings') })
        }
        if (this.satelliteStore.satPanelSection === 'main') {
          Column({ space: 8 }) {
            Row() {
              Text(I18n.t('sat_orbital_data')).fontSize(16).fontColor(this.c.text).layoutWeight(1)
              Text(this.satelliteStore.satCount.toString()).fontSize(14).fontColor(this.c.sub)
            }.width('100%')
            Text(this.satelliteStore.satelliteUpdateStatusText()).fontSize(13).fontColor(this.c.sub).width('100%')
            if (this.satelliteStore.satOutdatedCount > 0) {
              Text(I18n.t('sat_old_orbits')).fontSize(13).fontColor(this.c.warning).width('100%')
            }
            Button(I18n.t('sat_refresh'))
              .id('satellites-refresh').fontSize(15).fontColor(this.c.text)
              .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL).height(44).width('100%')
              .enabled(!this.satelliteStore.satOffline && this.satelliteStore.satUpdateSettings.updateState !== 0)
              .onClick(() => { this.onRefreshCatalog() })
            Row() {
              Text(I18n.t('sat_auto_updates')).fontSize(14).fontColor(this.c.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.satelliteStore.satUpdateSettings.updatesEnabled })
                .enabled(!this.satelliteStore.satOffline && this.satelliteStore.satUpdateSettings.updateState !== 0)
                .onChange((value: boolean) => { this.onSetUpdateSetting('updatesEnabled', value) })
            }.width('100%')
            Text(I18n.t('sat_auto_update_hint')).fontSize(12).fontColor(this.c.sub).width('100%')
          }.width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          if (this.satelliteStore.satSourceStatus.length > 0 && this.satelliteStore.satSourceStatus !== this.satelliteStore.satelliteUpdateStatusText()) {
            Text(this.satelliteStore.satSourceStatus).fontSize(13).fontColor(this.c.fourth).width('100%')
          }
          this.sectionButton('sat_advanced', 'settings')
          this.catalogContent()
        } else if (this.satelliteStore.satPanelSection === 'settings') {
          Text(I18n.t('sat_advanced')).fontSize(16).fontColor(this.c.text).width('100%')
          this.sectionButton('sat_import_settings', 'imports')
          this.sectionButton('sat_sources_title', 'sources')
          this.sectionButton('sat_display_settings', 'display')
          this.sectionButton('sat_timer_settings', 'countdown')
          this.sectionButton('sat_data_details', 'diagnostics')
        } else if (this.satelliteStore.satPanelSection === 'sources') {
          this.sourceContent()
        } else if (this.satelliteStore.satPanelSection === 'imports') {
          this.importContent()
        } else if (this.satelliteStore.satPanelSection === 'display') {
          this.displayContent()
        } else if (this.satelliteStore.satPanelSection === 'countdown') {
          this.countdownContent()
        } else if (this.satelliteStore.satPanelSection === 'diagnostics') {
          this.diagnosticContent()
        }
      }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
      .align(Alignment.TopStart)
      .onScroll(() => { this.onPublishState() })
  }
}
