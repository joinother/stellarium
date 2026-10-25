import { curves, Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureArtItem, SkyCultureDescriptionBlock, SkyCultureItem, SkyCultureTerritoryEntry } from '../../pages/StellariumTypes'
import { ConfigurationOption } from '../../pages/MainWindowModels'
import { LayerStore } from '../../state/LayerStore'
import { SkyCultureSettingsStore, SKY_CULTURE_LINE_COLOR, SKY_CULTURE_LABEL_COLOR, SKY_CULTURE_ZODIAC_COLOR, SKY_CULTURE_LUNAR_COLOR } from '../../state/SkyCultureSettingsStore'
import { SkyCultureViewStore } from '../../state/SkyCultureViewStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { LayerSwitchRow } from '../layers/LayerSwitchRow'
import { GraphLoadingRow } from '../../common/ui/GraphLoadingRow'
import { SkyCultureDescriptionBlockView } from '../../common/ui/SkyCultureDescriptionBlockView'
import { SkyCultureSectionHeader, SkyCultureMetaItem, SkyCultureLabelSettingCard, SkyCultureFilterPicker } from './SkyCultureViewParts'

// 「星空文化」视图标签页：图层 / 当前文化详情 / 标注 / 可读性等设置。
//
// 设置字段与纯计算由 SkyCultureSettingsStore、列表与当前选择由 SkyCultureViewStore 经 @ObjectLink 提供；
// 解码结果 / canvas 上下文等高频状态以 @Prop 或普通成员传入；一切 native 桥、定时器、解码、
// canvas 绘制经回调回注宿主。本文件不含 @BuilderParam 与参数化 @Builder，多根并列处包 Column({ space: 0 })。
@Component
export struct SkyCultureViewTab {
  @ObjectLink settings: SkyCultureSettingsStore
  @ObjectLink layerStore: LayerStore
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @Prop artStates: Record<string, string> = {}
  @Prop narrationParagraphs: Array<string> = []
  @State c: ThemeSlots = DEFAULT_SLOTS
  mapContextSettings: RenderingContextSettings = new RenderingContextSettings(true)
  mapContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.mapContextSettings)
  onToggleLayer: (actionId: string, cmd: string, value: boolean) => void = () => {}
  onLoadList: () => void = () => {}
  onSelectCulture: (id: string) => void = () => {}
  onRowArea: (id: string, area: Area) => void = () => {}
  onReloadList: () => void = () => {}
  onSelectLabelMode: (target: string, index: number) => void = () => {}
  onSetShortLabels: (enabled: boolean) => void = () => {}
  onSetCommonNames: (enabled: boolean) => void = () => {}
  onSetIsolation: (enabled: boolean) => void = () => {}
  onSetSinglePick: (enabled: boolean) => void = () => {}
  onConstellationSelection: (actionId: string, hint: string) => void = () => {}
  onSetStyleOption: (target: string, optionIndex: number, enabled: boolean) => void = () => {}
  getColorOptions: () => Array<ConfigurationOption> = () => []
  onSetVisualColor: (setting: string, color: string) => void = () => {}
  onSetVisualSetting: (setting: string, value: number) => void = () => {}
  onSetDefault: () => void = () => {}
  onSyncTimeFollowTimer: () => void = () => {}
  onRefreshSimulationYear: () => void = () => {}
  onLoadTerritoryMap: () => void = () => {}
  onMapReady: () => void = () => {}
  onMapAreaChange: (width: number, height: number) => void = () => {}
  onLoadObserverInfo: (force: boolean) => void = () => {}
  onArtDecodeError: (rawPath: string) => void = () => {}
  onOpenArtPreview: (art: SkyCultureArtItem) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private toggleLabelPicker(target: string): void {
    this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion(0.46, 0.86) }, () => {
      this.settings.skyCultureLabelPickerOpen = this.settings.skyCultureLabelPickerOpen === target ? '' : target
    })
  }

  private toggleFilter(kind: string): void {
    const opening = !this.settings.skyCultureFilterOpen(kind)
    this.getUIContext().animateTo({ duration: 220, curve: curves.springMotion(0.46, 0.88) }, () => {
      if (kind === 'classification') {
        this.settings.skyCultureClassificationFilterOpen = opening
        this.settings.skyCultureRegionFilterOpen = false
      } else {
        this.settings.skyCultureRegionFilterOpen = opening
        this.settings.skyCultureClassificationFilterOpen = false
      }
    })
  }

  private setFilterValue(kind: string, value: string): void {
    this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
      if (kind === 'classification') {
        this.settings.skyCultureClassificationFilter = value
        this.settings.skyCultureClassificationFilterOpen = false
      } else {
        this.settings.skyCultureRegionFilter = value
        this.settings.skyCultureRegionFilterOpen = false
      }
    })
  }

  private applyCustomColor(): void {
    this.onSetVisualColor(this.activeColorTarget(), this.settings.skyCultureColorInput)
  }

  private activeColorTarget(): string {
    const options = this.getColorOptions()
    for (const option of options) {
      if (option.id === this.settings.skyCultureColorTarget) return option.id
    }
    return options.length > 0 ? options[0].id : 'constellationLines'
  }

  private selectedSkyCultureId(): string {
    return this.skyCultureViewStore.pendingId.length > 0 ? this.skyCultureViewStore.pendingId : this.skyCultureViewStore.currentSkyCultureId
  }

  private artStatus(rawPath: string): string {
    const status = this.artStates[rawPath]
    return status === undefined ? 'preparing' : status
  }

  build() {
    Column({ space: 0 }) {
    SkyCultureSectionHeader({ title: I18n.t('culture_section_layers'), subtitle: I18n.t('culture_section_layers_hint') })
    Column({ space: 2 }) {
      LayerSwitchRow({ label: I18n.t('s0522'), isOn: this.layerStore.constellationLines, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Lines', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0523'), isOn: this.layerStore.constellationLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Labels', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0524'), isOn: this.layerStore.constellationBoundaries, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Boundaries', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0539'), isOn: this.layerStore.constellationHulls, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Hulls', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0525'), isOn: this.layerStore.constellationArt, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Art', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0526'), isOn: this.layerStore.zodiac, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Zodiac', '', value) } })
      LayerSwitchRow({ label: I18n.t('s0527'), isOn: this.layerStore.lunarSystem, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LunarSystem', '', value) } })
      if (this.settings.skyCultureHasAsterisms) {
        LayerSwitchRow({ label: I18n.t('s0528'), isOn: this.layerStore.asterismLines, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Asterism_Lines', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0529'), isOn: this.layerStore.asterismLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Asterism_Labels', '', value) } })
        LayerSwitchRow({ label: I18n.t('s0540'), isOn: this.layerStore.rayHelpers, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ray_Helpers', '', value) } })
      } else if (this.skyCultureViewStore.detailsReady && this.skyCultureViewStore.currentSkyCultureId.length > 0) {
        Text(I18n.t('culture_no_asterisms')).fontSize(10).fontColor(this.c.sub).width('100%')
          .padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 6 })
      }
    }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 3 })
      .backgroundColor(this.c.soft).border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
    Row()
      .width('100%').height(0.5)
      .backgroundColor(this.c.border)
      .margin({ top: 8, bottom: 8 })
    SkyCultureSectionHeader({ title: I18n.t('culture_section_current'), subtitle: I18n.t('culture_section_current_hint') })
    Row() {
      Text(this.skyCultureViewStore.currentSkyCulture.length > 0 ? this.skyCultureViewStore.currentSkyCulture : I18n.t('culture_reading'))
        .fontSize(15).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.skyCultureViewStore.detailsLoading && this.skyCultureViewStore.detailsReady) {
        LoadingProgress().width(16).height(16).color(this.c.accent).margin({ right: 8 })
      }
      Button(I18n.t('culture_refresh')).fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
        .onClick(() => { this.onLoadList() })
    }.height(40).width('100%').padding({ left: 8, right: 6 })
      .backgroundColor(this.c.rowBg).borderRadius(UI_RADIUS_CONTROL).margin({ top: 4, bottom: 4 })
    if (this.skyCultureViewStore.detailsLoading && !this.skyCultureViewStore.detailsReady) {
      GraphLoadingRow({ label: I18n.t('culture_loading') })
    } else if (this.skyCultureViewStore.detailError.length > 0 && !this.skyCultureViewStore.detailsReady) {
      Text(this.skyCultureViewStore.detailError).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 8, right: 8 }).margin({ top: 6, bottom: 6 })
    } else if (this.skyCultureViewStore.detailsReady && this.skyCultureViewStore.currentSkyCultureId.length > 0) {
      Column({ space: 5 }) {
        if (this.skyCultureViewStore.detailError.length > 0) {
          Text(this.skyCultureViewStore.detailError).fontSize(10).fontColor(this.c.sub).width('100%')
            .padding({ left: 9, right: 9, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
        }
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          SkyCultureMetaItem({ label: '地区', value: this.settings.skyCultureRegionText(this.settings.skyCultureRegions), accent: false })
          SkyCultureMetaItem({ label: '分类', value: this.settings.skyCultureClassificationText(this.settings.skyCultureClassification), accent: false })
          SkyCultureMetaItem({ label: '适用年代', value: this.settings.skyCultureTimeRange(), accent: false })
          SkyCultureMetaItem({ label: '时间匹配', value: this.settings.skyCultureSimulationTimeStatus(), accent: this.settings.skyCultureSimulationTimeMatches() })
          SkyCultureMetaItem({ label: '星座边界', value: this.settings.skyCultureBoundaryTypeText(this.settings.skyCultureBoundariesType), accent: false })
          SkyCultureMetaItem({ label: '通用名称', value: this.settings.skyCultureUsesCommonNames ? '已收录' : '未收录', accent: false })
          SkyCultureMetaItem({ label: '星座图形', value: this.settings.skyCultureConstellationCount + ' 个', accent: false })
          if (this.settings.skyCultureAsterismCount > 0) {
            SkyCultureMetaItem({ label: '星群', value: this.settings.skyCultureAsterismCount + ' 个', accent: false })
          }
          if (this.settings.skyCultureArtCount > 0) {
            SkyCultureMetaItem({ label: '星座绘图', value: this.settings.skyCultureArtCount + ' 幅', accent: false })
          }
          if (this.settings.skyCultureNativeNameCount > 0) {
            SkyCultureMetaItem({ label: '本土名称', value: this.settings.skyCultureNativeNameCount + ' 个', accent: false })
          }
        }.width('100%').padding({ top: 5, bottom: 2 })
        if (this.skyCultureViewStore.artItems.length > 0) {
          Row() {
            Column({ space: 1 }) {
              Text(I18n.t('culture_art_gallery')).fontSize(11).fontColor(this.c.text).width('100%')
              Text(this.skyCultureViewStore.artItems.length + ' ' + I18n.t('culture_offline_art')).fontSize(10).fontColor(this.c.sub).width('100%')
            }.layoutWeight(1)
            Button(this.skyCultureViewStore.artExpanded ? '收起' : '查看').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
              .onClick(() => { this.skyCultureViewStore.artExpanded = !this.skyCultureViewStore.artExpanded })
          }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          if (this.skyCultureViewStore.artExpanded) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.skyCultureViewStore.artItems.slice(0, 24), (art: SkyCultureArtItem) => {
                Column({ space: 3 }) {
                  if (this.skyCultureViewStore.artThumbnails[art.rawPath] !== undefined) {
                    Image(this.skyCultureViewStore.artThumbnails[art.rawPath]).width('100%').aspectRatio(1).objectFit(ImageFit.Contain)
                      .backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                      .onError(() => { this.onArtDecodeError(art.rawPath) })
                  } else if (this.artStatus(art.rawPath) === 'ready') {
                    Stack({ alignContent: Alignment.Center }) {
                      LoadingProgress().width(24).height(24).color(this.c.accent)
                    }.width('100%').aspectRatio(1).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                  } else if (this.artStatus(art.rawPath) === 'preparing') {
                    Stack({ alignContent: Alignment.Center }) {
                      LoadingProgress().width(24).height(24).color(this.c.accent)
                    }.width('100%').aspectRatio(1).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                  } else if (this.artStatus(art.rawPath) === 'decodeFailed') {
                    Text('图像解码失败').fontSize(10).fontColor(this.c.sub).width('100%').aspectRatio(1)
                      .textAlign(TextAlign.Center).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                  } else {
                    Text('绘图资源未安装').fontSize(10).fontColor(this.c.sub).width('100%').aspectRatio(1)
                      .textAlign(TextAlign.Center).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                  }
                  Text(art.name !== undefined && art.name.length > 0 ? art.name : '星座绘图 ' + art.index)
                    .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
                }.width('31%').padding(4).margin({ right: 1, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                  .onClick(() => {
                    this.onOpenArtPreview(art)
                  })
              }, (art: SkyCultureArtItem) => art.rawPath)
            }.width('100%').padding({ top: 5, bottom: 5 })
            if (this.skyCultureViewStore.artItems.length > 24) {
              Text('已显示前 24 幅，完整绘图仍由星图图层按需加载。').fontSize(10).fontColor(this.c.sub).width('100%')
            }
          }
        }
        if (this.skyCultureViewStore.narration.length > 0) {
          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Row().width(3).height(20).backgroundColor(this.c.accent).borderRadius(2)
              Text(I18n.t('culture_constellation_intro')).fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1)
            }.width('100%')
            Column({ space: 11 }) {
              ForEach(this.skyCultureViewStore.narrationExpanded ? this.narrationParagraphs : this.narrationParagraphs.slice(0, 2), (paragraph: string) => {
                Text(paragraph).fontSize(11).fontColor(this.c.text).width('100%').lineHeight(21)
              }, (paragraph: string, index: number) => 'narration-' + index + '-' + paragraph)
            }.width('100%')
            Row() {
              Button(I18n.t(this.skyCultureViewStore.narrationExpanded ? 'culture_collapse_intro' : 'culture_expand_intro')).fontSize(10).fontColor(this.c.accent)
                .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 11, right: 11 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.skyCultureViewStore.narrationExpanded = !this.skyCultureViewStore.narrationExpanded })
            }.width('100%').justifyContent(FlexAlign.End)
          }.width('100%').padding({ left: 13, right: 13, top: 12, bottom: 11 })
            .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.skyCultureViewStore.description.length > 0 && this.skyCultureViewStore.description !== this.skyCultureViewStore.narration) {
          Column({ space: 5 }) {
            Text(I18n.t('culture_full_material')).fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
            if (this.skyCultureViewStore.descriptionBlocks.length > 0) {
              Column({ space: 4 }) {
                ForEach(this.skyCultureViewStore.descriptionExpanded ? this.skyCultureViewStore.descriptionBlocks : this.skyCultureViewStore.descriptionBlocks.slice(0, 6), (block: SkyCultureDescriptionBlock) => {
                  SkyCultureDescriptionBlockView({ kind: block.kind, headingLarge: block.level !== undefined && block.level <= 1, text: block.text })
                }, (block: SkyCultureDescriptionBlock) => 'description-' + block.index)
              }.width('100%')
            } else {
              Text(this.skyCultureViewStore.description).fontSize(11).fontColor(this.c.text).width('100%')
                .lineHeight(20).maxLines(this.skyCultureViewStore.descriptionExpanded ? 999 : 6).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Button(this.skyCultureViewStore.descriptionExpanded ? I18n.t('culture_hide_full_material') : I18n.t('culture_read_full_material')).fontSize(10).fontColor(this.c.accent).backgroundColor(Color.Transparent)
              .height(28).padding({ left: 0, right: 8 }).onClick(() => { this.skyCultureViewStore.descriptionExpanded = !this.skyCultureViewStore.descriptionExpanded })
          }.width('100%').padding({ left: 10, right: 10, top: 10, bottom: 6 })
            .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL)
        }
        if (this.settings.skyCultureHasTerritoryArchive) {
          Text(I18n.t('culture_territory_archive')).fontSize(12).fontColor(this.c.sub).width('100%').margin({ top: 4 })
          Text('所选年份 ' + this.settings.skyCultureTimeFilterLabel() + '：' + this.settings.skyCultureTerritoryEntriesForSelectedYear().length + ' 个有效时期；共 ' + this.settings.skyCultureTerritorySegmentCount + ' 条档案')
            .fontSize(10).fontColor(this.c.sub).width('100%')
          if (this.settings.skyCultureTerritoryEntriesForSelectedYear().length === 0) {
            Text('该文化没有覆盖所选年份的地理档案。').fontSize(10).fontColor(this.c.sub).width('100%').margin({ top: 3 })
          }
          if (this.settings.skyCultureTerritoryExpanded) {
            Column({ space: 4 }) {
              ForEach(this.settings.skyCultureTerritoryEntriesForSelectedYear(), (entry: SkyCultureTerritoryEntry, index: number) => {
                Row({ space: 8 }) {
                  Column({ space: 1 }) {
                    Text(entry.name.length > 0 ? entry.name : '未命名地理档案').fontSize(10).fontColor(this.c.text).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.settings.skyCultureTerritoryRange(entry)).fontSize(10).fontColor(this.c.sub).width('100%')
                  }.layoutWeight(1)
                  if (entry.countryCode.length > 0) {
                    Text(entry.countryCode).fontSize(10).fontColor(this.c.accent).padding({ left: 5, right: 5, top: 2, bottom: 2 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                  }
                }.width('100%').padding({ left: 6, right: 6, top: 5, bottom: 5 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              }, (entry: SkyCultureTerritoryEntry, index: number) => entry.name + '-' + entry.beginTime + '-' + entry.endTime + '-' + index)
            }.width('100%').margin({ top: 5 })
          }
          Button(this.settings.skyCultureTerritoryExpanded ? '收起地理档案' : '查看地理档案').fontSize(10).fontColor(this.c.accent).backgroundColor(Color.Transparent)
            .height(26).padding({ left: 0, right: 8 }).onClick(() => { this.settings.skyCultureTerritoryExpanded = !this.settings.skyCultureTerritoryExpanded })
          Row({ space: 8 }) {
            Column({ space: 1 }) {
              Text(I18n.t('culture_map')).fontSize(11).fontColor(this.c.text).width('100%')
              Text('使用本地地图和文化资料，不联网；文化分布示意不代表现行行政区划或政治边界')
                .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
            }.layoutWeight(1)
            Button(this.settings.skyCultureTerritoryMapExpanded ? I18n.t('culture_update_map') : I18n.t('culture_view_map')).fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 }).enabled(!this.settings.skyCultureTerritoryMapLoading)
              .onClick(() => { this.onLoadTerritoryMap() })
          }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ top: 3, bottom: this.settings.skyCultureTerritoryMapExpanded ? 4 : 2 })
          if (this.settings.skyCultureTerritoryMapLoading) {
            GraphLoadingRow({ label: '正在绘制文化区域地图…' })
          } else if (this.settings.skyCultureTerritoryMapError.length > 0) {
            Text(this.settings.skyCultureTerritoryMapError).fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 })
          } else if (this.settings.skyCultureTerritoryMapExpanded) {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text('地图年份').fontSize(10).fontColor(this.c.text).width(52)
                TextInput({ text: this.settings.skyCultureTerritoryMapYearInput, placeholder: '年份' }).fontSize(11).fontColor(this.c.text).height(28).width(86)
                  .onChange((value: string) => { this.settings.skyCultureTerritoryMapYearInput = value })
                  .onSubmit(() => { this.settings.applySkyCultureTerritoryMapYearInput() })
                Button('同步星图时间').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 7, right: 7 })
                  .onClick(() => { this.settings.syncSkyCultureTerritoryMapYearToSimulation() })
                Button('更新').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
                  .enabled(!this.settings.skyCultureTerritoryMapLoading)
                  .onClick(() => { this.onLoadTerritoryMap() })
              }.width('100%')
              Text('地图年份独立于文化目录筛选；可按星图当前时间同步。').fontSize(10).fontColor(this.c.sub).width('100%')
              Row() {
                Column({ space: 1 }) {
                  Text('按观测地旋转地图').fontSize(10).fontColor(this.c.text).width('100%')
                  Text(this.settings.skyCultureMapUseLocationRotation
                    ? (this.settings.skyCultureObserverLatitude < 0 ? '南半球：地图已旋转 180°' : '北半球：保持标准方向')
                    : '关闭时保持标准方向').fontSize(10).fontColor(this.c.sub).width('100%')
                }.layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureMapUseLocationRotation }).width(38).height(21)
                  .onChange((enabled: boolean) => {
                    this.settings.skyCultureMapUseLocationRotation = enabled
                    this.onLoadObserverInfo(false)
                  })
              }.width('100%').padding({ top: 2, bottom: 2 })
              Slider({ value: this.settings.skyCultureTerritoryMapYear, min: -40000, max: this.settings.skyCultureTerritoryMapMaxYear(), step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                .height(24).width('100%')
                .onChange((year: number) => { this.settings.setSkyCultureTerritoryMapYear(year) })
              Text('地图年份：' + this.settings.skyCultureFormatYear(this.settings.skyCultureTerritoryMapYear) + ' · ' + this.settings.skyCultureTerritoryMapPolygons.length + ' 个区域轮廓')
                .fontSize(10).fontColor(this.c.sub).width('100%')
              if (this.settings.skyCultureTerritoryMapPolygons.length === 0) {
                Text('该年份没有可显示的文化区域。可调整年份后更新地图。').fontSize(10).fontColor(this.c.sub).width('100%')
              } else {
                Stack() {
                  Image($rawfile('worldmap.jpg')).width('100%').height('100%').objectFit(ImageFit.Fill)
                  Canvas(this.mapContext).width('100%').height('100%')
                    .onReady(() => { this.onMapReady() })
                    .onAreaChange((oldArea: Area, newArea: Area) => {
                      this.onMapAreaChange(Number(newArea.width), Number(newArea.height))
                    })
                }.width('100%').aspectRatio(2).clip(true).rotate({ angle: this.settings.skyCultureMapRotationAngle() }).backgroundColor(this.c.bg)
                  .border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL)
              }
            }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
          }
        }
        if (this.settings.skyCultureLicense.length > 0) {
          Text('资料许可：' + this.settings.skyCultureLicense).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      SkyCultureSectionHeader({ title: I18n.t('culture_section_labels'), subtitle: I18n.t('culture_section_labels_hint') })
      Column() {
        SkyCultureLabelSettingCard({
          target: 'screen',
          title: '星图标注',
          options: this.settings.skyCultureLabelModeOptions('screen'),
          mode: this.settings.skyCultureLabelModeForTarget('screen'),
          isOpen: this.settings.skyCultureLabelPickerOpen === 'screen',
          onToggle: (target: string) => { this.toggleLabelPicker(target) },
          onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
        })
      }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      Row() {
        Text('使用星座短名称').fontSize(11).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureShortLabels }).width(40).height(22)
          .onChange((enabled: boolean) => { this.onSetShortLabels(enabled) })
      }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      Row() {
        Column({ space: 1 }) {
          Text('显示国际通用名称').fontSize(11).fontColor(this.c.text).width('100%')
          Text(this.settings.skyCultureUsesCommonNames ? '当前文化包含可用的国际通用名称' : '当前文化没有可用的国际通用名称')
            .fontSize(10).fontColor(this.c.sub).width('100%')
        }.layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureOverrideCommonNames }).width(40).height(22)
          .enabled(this.settings.skyCultureUsesCommonNames)
          .opacity(this.settings.skyCultureUsesCommonNames ? 1 : 0.45)
          .onChange((enabled: boolean) => { this.onSetCommonNames(enabled) })
      }.height(42).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      Row() {
        Text('选中星座时单独显示').fontSize(11).fontColor(this.c.text).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureIsolateSelected }).width(40).height(22)
          .onChange((enabled: boolean) => { this.onSetIsolation(enabled) })
      }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 4 })
      Row() {
        Text('仅保留最后选中的星座').fontSize(11).fontColor(this.settings.skyCultureIsolateSelected ? this.c.text : this.c.sub).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureSinglePick }).width(40).height(22)
          .enabled(this.settings.skyCultureIsolateSelected)
          .opacity(this.settings.skyCultureIsolateSelected ? 1 : 0.45)
          .onChange((enabled: boolean) => { this.onSetSinglePick(enabled) })
      }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      Row({ space: 6 }) {
        Button('全选星座').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30)
          .layoutWeight(1).onClick(() => { this.onConstellationSelection('actionShow_Constellation_Select', '已选中全部星座') })
        Button('清除选择').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30)
          .layoutWeight(1).onClick(() => { this.onConstellationSelection('actionShow_Constellation_Deselect', '已清除星座选择') })
      }.width('100%').padding({ left: 8, right: 8 }).margin({ bottom: 8 })
      SkyCultureSectionHeader({ title: I18n.t('culture_section_readability'), subtitle: I18n.t('culture_section_readability_hint') })
      Row() {
        Text('星座标签字号').fontSize(11).fontColor(this.c.text).width(84)
        Text(this.settings.skyCultureConstellationFontSize.toFixed(0)).fontSize(11).fontColor(this.c.sub).width(28).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationFontSize, min: 8, max: 40, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationFontSize', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
      Row() {
        Text('星座连线粗细').fontSize(11).fontColor(this.c.text).width(84)
        Text(this.settings.skyCultureConstellationLineThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationLineThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationLineThickness', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
      Row() {
        Text('星座边界粗细').fontSize(11).fontColor(this.c.text).width(84)
        Text(this.settings.skyCultureConstellationBoundaryThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationBoundaryThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationBoundaryThickness', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
      Row() {
        Text('星座绘图亮度').fontSize(11).fontColor(this.c.text).width(84)
        Text(Math.round(this.settings.skyCultureConstellationArtIntensity * 100) + '%').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationArtIntensity, min: 0, max: 1, step: 0.05, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationArtIntensity', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
      if (this.settings.skyCultureHasAsterisms) {
        Row() {
          Text('星群标签字号').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureAsterismFontSize.toFixed(0)).fontSize(11).fontColor(this.c.sub).width(28).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureAsterismFontSize, min: 8, max: 40, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('asterismFontSize', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
        Row() {
          Text('星群连线粗细').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureAsterismLineThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureAsterismLineThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('asterismLineThickness', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.constellationHulls || this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.layerStore.constellationHulls) {
        Row() {
          Text('星座区域边界').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureConstellationHullsThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureConstellationHullsThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('constellationHullsThickness', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.settings.skyCultureHasAsterisms && this.layerStore.rayHelpers) {
        Row() {
          Text('辅助射线粗细').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureRayHelperThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureRayHelperThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('rayHelperThickness', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) {
        Row() {
          Text('黄道线粗细').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureZodiacThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureZodiacThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('zodiacThickness', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem ? 3 : 8 })
      }
      if (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) {
        Row() {
          Text('月宿线粗细').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureLunarSystemThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureLunarSystemThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('lunarSystemThickness', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Text('显示过渡').fontSize(12).fontColor(this.c.sub).width('100%').padding({ left: 2 }).margin({ top: 2, bottom: 4 })
      Row() {
        Text('星座连线').fontSize(11).fontColor(this.c.text).width(84)
        Text(this.settings.skyCultureConstellationLinesFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationLinesFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationLinesFadeDuration', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 3 })
      Row() {
        Text('星座标签').fontSize(11).fontColor(this.c.text).width(84)
        Text(this.settings.skyCultureConstellationLabelsFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
        Slider({ value: this.settings.skyCultureConstellationLabelsFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
          .onChange((value: number) => { this.onSetVisualSetting('constellationLabelsFadeDuration', value) })
      }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.constellationArt || this.layerStore.constellationBoundaries || this.layerStore.constellationHulls || this.layerStore.asterismLines || this.layerStore.asterismLabels || this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      if (this.layerStore.constellationArt) {
        Row() {
          Text('星座绘图').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureConstellationArtFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureConstellationArtFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('constellationArtFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.constellationBoundaries || this.layerStore.constellationHulls || this.layerStore.asterismLines || this.layerStore.asterismLabels || this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.layerStore.constellationBoundaries) {
        Row() {
          Text('星座边界').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureConstellationBoundariesFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureConstellationBoundariesFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('constellationBoundariesFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.constellationHulls || this.layerStore.asterismLines || this.layerStore.asterismLabels || this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.layerStore.constellationHulls) {
        Row() {
          Text('星座区域边界').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureConstellationHullsFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureConstellationHullsFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('constellationHullsFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.asterismLines || this.layerStore.asterismLabels || this.layerStore.rayHelpers || (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.settings.skyCultureHasAsterisms && this.layerStore.asterismLines) {
        Row() {
          Text('星群连线').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureAsterismLinesFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureAsterismLinesFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('asterismLinesFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.asterismLabels || this.layerStore.rayHelpers ? 3 : 8 })
      }
      if (this.settings.skyCultureHasAsterisms && this.layerStore.asterismLabels) {
        Row() {
          Text('星群标签').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureAsterismLabelsFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureAsterismLabelsFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('asterismLabelsFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.rayHelpers ? 3 : 8 })
      }
      if (this.settings.skyCultureHasAsterisms && this.layerStore.rayHelpers) {
        Row() {
          Text('辅助射线').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureRayHelperFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureRayHelperFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('rayHelperFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) || (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) ? 3 : 8 })
      }
      if (this.layerStore.zodiac && this.settings.skyCultureHasZodiac) {
        Row() {
          Text('黄道线').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureZodiacFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureZodiacFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('zodiacFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem ? 3 : 8 })
      }
      if (this.layerStore.lunarSystem && this.settings.skyCultureHasLunarSystem) {
        Row() {
          Text('月宿线').fontSize(11).fontColor(this.c.text).width(84)
          Text(this.settings.skyCultureLunarSystemFadeDuration.toFixed(1) + ' 秒').fontSize(11).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
          Slider({ value: this.settings.skyCultureLunarSystemFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
            .onChange((value: number) => { this.onSetVisualSetting('lunarSystemFadeDuration', value) })
        }.height(34).width('100%').padding({ left: 8, right: 10 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Row() {
        Column({ space: 1 }) {
          Text('图层颜色').fontSize(12).fontColor(this.c.sub).width('100%')
          Text('为当前显示的文化图层分别设置颜色').fontSize(10).fontColor(this.c.sub).width('100%')
        }.layoutWeight(1)
        Button(this.settings.skyCultureColorsExpanded ? '收起' : '展开').fontSize(10).fontColor(this.c.accent).height(28)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).padding({ left: 9, right: 9 })
          .onClick(() => { this.settings.skyCultureColorsExpanded = !this.settings.skyCultureColorsExpanded })
      }.width('100%').padding({ left: 2, right: 2, top: 3, bottom: 4 }).margin({ bottom: this.settings.skyCultureColorsExpanded ? 4 : 8 })
      if (this.settings.skyCultureColorsExpanded) {
        Column({ space: 5 }) {
          if (this.getColorOptions().length === 0) {
            Text('请先在"星空及显示"中开启星座、星群、黄道或月宿图层。').fontSize(10).fontColor(this.c.sub).width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          } else {
            Text('选择图层').fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
            ForEach(this.getColorOptions(), (option: ConfigurationOption) => {
              Row({ space: 8 }) {
                Stack() {
                  Circle().width(18).height(18).fill(this.settings.skyCultureVisualColor(option.id))
                  Circle().width(18).height(18).fillOpacity(0).stroke(this.c.text).strokeWidth(1)
                }.width(22).height(22)
                Text(option.label).fontSize(11).fontColor(this.c.text).layoutWeight(1)
                Text(this.settings.skyCultureVisualColor(option.id)).fontSize(10).fontColor(this.c.sub)
              }.height(34).width('100%').padding({ left: 8, right: 8 })
                .backgroundColor(option.id === this.activeColorTarget() ? this.c.softStrong : this.c.soft)
                .border({ width: option.id === this.activeColorTarget() ? 1 : 0, color: option.id === this.activeColorTarget() ? this.c.accent : Color.Transparent })
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.settings.selectSkyCultureColorTarget(option.id) })
            }, (option: ConfigurationOption) => option.id)
            Row({ space: 8 }) {
              Text('颜色值').fontSize(11).fontColor(this.c.text).width(48)
              TextInput({ text: this.settings.skyCultureColorInput, placeholder: '#RRGGBB' }).fontSize(11).fontColor(this.c.text).height(30).layoutWeight(1)
                .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).textAlign(TextAlign.Center)
                .onChange((value: string) => { this.settings.skyCultureColorInput = value.toUpperCase() })
                .onSubmit(() => { this.applyCustomColor() })
              Button('应用').fontSize(10).fontColor(this.c.textStrong).height(30).backgroundColor(this.c.accent).borderRadius(UI_RADIUS_CONTROL)
                .padding({ left: 9, right: 9 }).onClick(() => { this.applyCustomColor() })
            }.height(34).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
            Row({ space: 8 }) {
              ForEach([SKY_CULTURE_LINE_COLOR, SKY_CULTURE_LABEL_COLOR, SKY_CULTURE_ZODIAC_COLOR, SKY_CULTURE_LUNAR_COLOR, this.c.errorText, this.c.badgePurple, this.c.text], (color: string) => {
                Button() {
                  Circle().width(20).height(20).fill(color).stroke(this.c.text).strokeWidth(1)
                }.width(28).height(28).backgroundColor(Color.Transparent).padding(0)
                  .onClick(() => {
                    this.settings.skyCultureColorInput = color
                    this.onSetVisualColor(this.activeColorTarget(), color)
                  })
              }, (color: string) => color)
            }.width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ left: 5, right: 5, top: 2, bottom: 2 })
          }
        }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Column() {
        SkyCultureLabelSettingCard({
          target: 'info',
          title: '资料中的名称',
          options: this.settings.skyCultureLabelModeOptions('info'),
          mode: this.settings.skyCultureLabelModeForTarget('info'),
          isOpen: this.settings.skyCultureLabelPickerOpen === 'info',
          onToggle: (target: string) => { this.toggleLabelPicker(target) },
          onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
        })
      }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      if (this.settings.skyCultureHasZodiac) {
        Column() {
          SkyCultureLabelSettingCard({
            target: 'zodiac',
            title: '黄道十二宫名称',
            options: this.settings.skyCultureLabelModeOptions('zodiac'),
            mode: this.settings.skyCultureLabelModeForTarget('zodiac'),
            isOpen: this.settings.skyCultureLabelPickerOpen === 'zodiac',
            onToggle: (target: string) => { this.toggleLabelPicker(target) },
            onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
          })
        }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      if (this.settings.skyCultureHasLunarSystem) {
        Column() {
          SkyCultureLabelSettingCard({
            target: 'lunar',
            title: '月宿系统名称',
            options: this.settings.skyCultureLabelModeOptions('lunar'),
            mode: this.settings.skyCultureLabelModeForTarget('lunar'),
            isOpen: this.settings.skyCultureLabelPickerOpen === 'lunar',
            onToggle: (target: string) => { this.toggleLabelPicker(target) },
            onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
          })
        }.width('100%').padding({ left: 8, right: 8, top: 7, bottom: 7 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Row() {
        Column({ space: 2 }) {
          Text('组合名称显示').fontSize(11).fontColor(this.c.text).width('100%')
          Text('星图：' + this.settings.skyCultureStyleSummary(this.settings.skyCultureScreenStyleMask) + ' · 资料：' + this.settings.skyCultureStyleSummary(this.settings.skyCultureInfoStyleMask))
            .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1)
        Button(this.settings.skyCultureNameCombinationExpanded ? '收起' : '设置').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28)
          .padding({ left: 9, right: 9 }).onClick(() => { this.settings.skyCultureNameCombinationExpanded = !this.settings.skyCultureNameCombinationExpanded })
      }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.settings.skyCultureNameCombinationExpanded ? 4 : 8 })
      if (this.settings.skyCultureNameCombinationExpanded) {
        Column({ space: 3 }) {
          Text('星图标签').fontSize(11).fontColor(this.c.sub).width('100%')
          ForEach(this.settings.skyCultureStyleOptions(), (option: ConfigurationOption, optionIndex: number) => {
            Row() {
              Text(option.label).fontSize(10).fontColor(this.c.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureStyleMaskHas(this.settings.skyCultureScreenStyleMask, optionIndex) }).width(38).height(21)
                .onChange((enabled: boolean) => { this.onSetStyleOption('screen', optionIndex, enabled) })
            }.height(29).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          }, (option: ConfigurationOption) => 'screen-' + option.id)
          Text('资料卡标签').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 5 })
          ForEach(this.settings.skyCultureStyleOptions(), (option: ConfigurationOption, optionIndex: number) => {
            Row() {
              Text(option.label).fontSize(10).fontColor(this.c.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureStyleMaskHas(this.settings.skyCultureInfoStyleMask, optionIndex) }).width(38).height(21)
                .onChange((enabled: boolean) => { this.onSetStyleOption('info', optionIndex, enabled) })
            }.height(29).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          }, (option: ConfigurationOption) => 'info-' + option.id)
        }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
      }
      Row() {
        Text(this.settings.skyCultureDefaultId === this.skyCultureViewStore.currentSkyCultureId ? '当前已是默认文化' : '启动时使用此文化').fontSize(11).fontColor(this.c.sub).layoutWeight(1)
        Button('设为默认').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
          .enabled(this.settings.skyCultureDefaultId !== this.skyCultureViewStore.currentSkyCultureId)
          .onClick(() => { this.onSetDefault() })
        Button('重新载入').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
          .onClick(() => { this.onReloadList() })
      }.width('100%').padding({ top: 3, bottom: 7 })
    }
    SkyCultureSectionHeader({ title: I18n.t('culture_section_select'), subtitle: I18n.t('culture_section_select_hint') })
    Column({ space: 5 }) {
      TextInput({ text: this.settings.skyCultureSearchText, placeholder: I18n.t('culture_search_placeholder') }).fontSize(11).height(38)
        .width('100%').backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL)
        .onChange((value: string) => { this.settings.skyCultureSearchText = value })
      Column({ space: 6 }) {
        SkyCultureFilterPicker({
          kind: 'classification',
          labels: this.settings.skyCultureFilterLabels('classification'),
          selectedIndex: this.settings.skyCultureFilterSelectedIndex('classification'),
          isOpen: this.settings.skyCultureFilterOpen('classification'),
          onToggle: (kind: string) => { this.toggleFilter(kind) },
          onPick: (kind: string, index: number) => { this.setFilterValue(kind, this.settings.skyCultureFilterValues(kind)[index]) }
        })
        SkyCultureFilterPicker({
          kind: 'region',
          labels: this.settings.skyCultureFilterLabels('region'),
          selectedIndex: this.settings.skyCultureFilterSelectedIndex('region'),
          isOpen: this.settings.skyCultureFilterOpen('region'),
          onToggle: (kind: string) => { this.toggleFilter(kind) },
          onPick: (kind: string, index: number) => { this.setFilterValue(kind, this.settings.skyCultureFilterValues(kind)[index]) }
        })
      }.width('100%')
    }.width('100%').padding({ bottom: 5 })
    if (this.settings.skyCultureSearchText.trim().length > 0 || this.settings.skyCultureClassificationFilter !== 'all' || this.settings.skyCultureRegionFilter !== 'all' || this.settings.skyCultureTimeFiltering) {
      Text(I18n.t('culture_filter_summary') + '：' + this.settings.skyCultureClassificationFilterLabel() + ' · ' + this.settings.skyCultureRegionFilterLabel() + ' · ' + this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList).length + ' ' + I18n.t('culture_match_count'))
        .fontSize(10).fontColor(this.c.accent).width('100%').padding({ left: 9, right: 9, top: 6, bottom: 6 })
        .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 5 })
    }
    Row() {
      Column({ space: 1 }) {
        Text(I18n.t('culture_filter_by_year')).fontSize(11).fontColor(this.c.text).width('100%')
        Text(I18n.t('culture_filter_by_year_hint')).fontSize(10).fontColor(this.c.sub).width('100%')
      }.layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureTimeFiltering }).width(40).height(22)
        .onChange((enabled: boolean) => {
          this.settings.skyCultureTimeFiltering = enabled
          this.onSyncTimeFollowTimer()
        })
    }.height(42).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: this.settings.skyCultureTimeFiltering ? 4 : 7 })
    if (this.settings.skyCultureTimeFiltering) {
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          Text('筛选方式').fontSize(10).fontColor(this.c.sub).width(52)
          Row({ space: 4 }) {
            Button('单个年份').fontSize(10).fontColor(this.settings.skyCultureRangeFiltering ? this.c.sub : this.c.text)
              .backgroundColor(this.settings.skyCultureRangeFiltering ? this.c.bg : this.c.accentSoft)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 9, right: 9 })
              .onClick(() => {
                this.settings.skyCultureRangeFiltering = false
                this.settings.skyCultureTimeFollowSimulation = false
                this.onSyncTimeFollowTimer()
              })
            Button('年代范围').fontSize(10).fontColor(this.settings.skyCultureRangeFiltering ? this.c.text : this.c.sub)
              .backgroundColor(this.settings.skyCultureRangeFiltering ? this.c.accentSoft : this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 9, right: 9 })
              .onClick(() => {
                this.settings.skyCultureRangeFiltering = true
                this.settings.skyCultureTimeFollowSimulation = false
                this.settings.setSkyCultureRange(this.settings.skyCultureRangeStart, this.settings.skyCultureRangeEnd)
                this.onSyncTimeFollowTimer()
              })
          }.layoutWeight(1).justifyContent(FlexAlign.End)
        }.width('100%')
        if (!this.settings.skyCultureRangeFiltering) {
          Row({ space: 8 }) {
            Text('查看年份').fontSize(10).fontColor(this.c.sub).width(52)
            TextInput({ text: this.settings.skyCultureTimeYearInput, placeholder: '年份' }).fontSize(12).fontColor(this.c.text).height(28).width(76)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).textAlign(TextAlign.Center)
              .onChange((value: string) => { this.settings.skyCultureTimeYearInput = value })
              .onSubmit(() => { this.settings.applySkyCultureTimeYearInput() })
            Text(this.settings.skyCultureTimeFilterLabel()).fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Button() {
              Image($r('app.media.ic_refresh')).width(14).height(14).fillColor(this.c.sub)
            }.width(30).height(28).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.settings.setSkyCultureTimeYear(this.settings.skyCultureFilterMaxYear()) })
          }.width('100%')
          Row({ space: 6 }) {
            Column({ space: 1 }) {
              Text('按星图模拟时间').fontSize(10).fontColor(this.c.text).width('100%')
              Text(this.settings.skyCultureFormatYear(this.settings.skyCultureSimulationYear)).fontSize(10).fontColor(this.c.sub).width('100%')
            }.layoutWeight(1)
            Button('同步').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
              .onClick(() => {
                this.onRefreshSimulationYear()
                this.settings.setSkyCultureTimeYear(this.settings.skyCultureSimulationYear)
              })
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureTimeFollowSimulation }).width(38).height(21)
              .onChange((enabled: boolean) => {
                this.settings.skyCultureTimeFollowSimulation = enabled
                if (enabled) {
                  this.onRefreshSimulationYear()
                  this.settings.setSkyCultureTimeYear(this.settings.skyCultureSimulationYear)
                }
                this.onSyncTimeFollowTimer()
              })
          }.width('100%').height(34).padding({ left: 8, right: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
          Slider({ value: this.settings.skyCultureTimeYear, min: -40000, max: this.settings.skyCultureFilterMaxYear(), step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .trackColor(this.c.bg)
            .showSteps(false).showTips(false).width('100%')
            .onChange((year: number) => { this.settings.setSkyCultureTimeYear(year) })
          Row() {
            Text('公元前 40000 年').fontSize(10).fontColor(this.c.sub).layoutWeight(1)
            Text('当代').fontSize(10).fontColor(this.c.sub)
          }.width('100%')
        } else {
          Row({ space: 6 }) {
            Text('起止年代').fontSize(10).fontColor(this.c.sub).width(52)
            TextInput({ text: this.settings.skyCultureRangeStartInput, placeholder: '起始年' }).fontSize(11).fontColor(this.c.text).height(28).layoutWeight(1)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).textAlign(TextAlign.Center)
              .onChange((value: string) => { this.settings.skyCultureRangeStartInput = value })
              .onSubmit(() => { this.settings.applySkyCultureRangeInput() })
            Text('至').fontSize(10).fontColor(this.c.sub)
            TextInput({ text: this.settings.skyCultureRangeEndInput, placeholder: '结束年' }).fontSize(11).fontColor(this.c.text).height(28).layoutWeight(1)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).textAlign(TextAlign.Center)
              .onChange((value: string) => { this.settings.skyCultureRangeEndInput = value })
              .onSubmit(() => { this.settings.applySkyCultureRangeInput() })
            Button() {
              Image($r('app.media.ic_refresh')).width(14).height(14).fillColor(this.c.sub)
            }.width(30).height(28).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.settings.setSkyCultureRange(-40000, this.settings.skyCultureFilterMaxYear()) })
          }.width('100%')
          Text(this.settings.skyCultureRangeLabel()).fontSize(10).fontColor(this.c.text).width('100%')
        }
        Text('匹配 ' + this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList).length + ' 个文化').fontSize(10).fontColor(this.c.sub).width('100%')
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 7 })
    }
    if (this.skyCultureViewStore.skyCultureListLoading) {
      GraphLoadingRow({ label: I18n.t('culture_catalog_reading') })
    } else if (this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList).length === 0) {
      Text(I18n.t('culture_no_matching') + '。' + (this.settings.skyCultureTimeFiltering ? '请调整年份、类型或取消年代筛选。' : '请调整搜索或类型筛选。'))
        .fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 10, right: 10, top: 14, bottom: 14 })
        .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
    } else {
      Column({ space: 6 }) {
        ForEach(this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList), (sc: SkyCultureItem, index: number) => {
          Column({ space: 3 }) {
            if (this.settings.skyCultureRegionHeader(this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList), index).length > 0) {
              Row() {
                Text(this.settings.skyCultureRegionHeader(this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList), index)).fontSize(10).fontColor(this.c.sub).fontWeight(FontWeight.Medium)
                Divider().strokeWidth(1).color(this.c.border).layoutWeight(1).margin({ left: 8 })
              }.width('100%').height(24).padding({ left: 4, right: 4, top: 5 })
            }
            Row({ space: 10 }) {
              Stack({ alignContent: Alignment.Center }) {
                Row().width(3).height(38).backgroundColor(sc.id === this.selectedSkyCultureId() ? this.c.accent : this.c.border).borderRadius(2)
              }.width(3).height(42)
              Column({ space: 2 }) {
                Text(this.settings.skyCultureDisplayName(sc.id, sc.name)).fontSize(13).fontColor(this.c.text).fontWeight(sc.id === this.selectedSkyCultureId() ? FontWeight.Medium : FontWeight.Regular).width('100%').maxLines(2).lineHeight(18).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.settings.skyCultureRegionText(sc.region ?? []) + ' · ' + this.settings.skyCultureClassificationText(sc.classification ?? ''))
                  .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.layoutWeight(1)
              if (sc.id === this.selectedSkyCultureId()) {
                Row({ space: 4 }) {
                  if (sc.id === this.skyCultureViewStore.pendingId) {
                    LoadingProgress().width(12).height(12).color(this.c.accent)
                  }
                  Text(sc.id === this.skyCultureViewStore.pendingId ? I18n.t('c_loading') : '✓ ' + I18n.t('culture_current'))
                    .fontSize(10).fontColor(this.c.accent).maxLines(1)
                }.padding({ left: 7, right: 7, top: 4, bottom: 4 }).backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_CONTROL)
              }
            }
            .height(64).width('100%').padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(sc.id === this.selectedSkyCultureId() ? this.c.chipInactiveBg : Color.Transparent)
            .border({ width: 1, color: sc.id === this.selectedSkyCultureId() ? this.c.chipActiveBorder : this.c.border })
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
            .onAreaChange((oldArea: Area, newArea: Area) => { this.onRowArea(sc.id, newArea) })
            .onClick(() => { this.onSelectCulture(sc.id) })
          }.width('100%')
        }, (sc: SkyCultureItem) => sc.id)
      }.width('100%')
    }
  
    }.width('100%')
  }
}
