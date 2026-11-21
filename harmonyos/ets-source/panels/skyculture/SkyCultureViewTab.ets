import { curves, Theme } from '@kit.ArkUI'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { getSkyCultureStoryZh, SkyCultureStoryZh } from '../../common/derive/SkyCultureStoriesZh'
import {
  formatShortEraRange,
  recommendedYearForCulture,
  recommendSkyCultures,
  SkyCultureRecommendation,
  splitAiryParagraphs,
  splitHighlightTags
} from '../../common/derive/SkyCultureRecommender'
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
import { SkyCultureSectionHeader, SkyCultureLabelSettingCard, SkyCultureFilterPicker } from './SkyCultureViewParts'
import { SkyCulturePetalMapCard } from './SkyCulturePetalMapCard'

// 「星空文化」视图标签页：三段式轻量导览 + 渐进式阅读排版 + 时空智能推荐：
//   0 · 探索文化（默认）：当前文化快捷条 + 「此时此地推荐」胶囊 + 搜索/地区胶囊 + 64 套精炼扫读卡片；
//   1 · 文化详情：三列单行核心指标 + 一键跳至历史年代 + 一句话导读/代表星象胶囊/按需展开透气短段故事 + 华为花瓣地图单点渊源坐标 + 绘像画廊；
//   2 · 显示与标注：常用图层/标注/外观 + 时空推荐开关 + 可折叠高级微调。

interface QuickCultureGroup {
  id: string
  label: string
}

const QUICK_CULTURE_GROUPS: Array<QuickCultureGroup> = [
  { id: 'all', label: '全部' },
  { id: 'chinese', label: '中国' },
  { id: 'modern', label: '现代标准' },
  { id: 'east_asia', label: '亚洲其他' },
  { id: 'europe', label: '欧洲' },
  { id: 'oceania', label: '大洋洲' },
  { id: 'americas', label: '美洲与极地' },
  { id: 'west_asia_africa', label: '西亚与非洲' }
]

@Component
export struct SkyCultureViewTab {
  @ObjectLink settings: SkyCultureSettingsStore
  @ObjectLink layerStore: LayerStore
  @ObjectLink skyCultureViewStore: SkyCultureViewStore
  @Prop artStates: Record<string, string> = {}
  @Prop narrationParagraphs: Array<string> = []
  @Prop previewMapAllowed: boolean = false
  @Prop observerLatitude: number = 0
  @Prop observerLongitude: number = 0
  @Prop earthObserver: boolean = true
  @State c: ThemeSlots = DEFAULT_SLOTS
  @State private subTab: number = 0
  @State private quickGroup: string = 'all'
  @State private advancedFilterOpen: boolean = false
  @State private storyExpanded: boolean = false
  @State private academicRefOpen: boolean = false
  @State private advancedDisplayOpen: boolean = false
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
  onJumpToCultureYear: (year: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    if ((this.skyCultureViewStore.skyCultureList.length === 0 || !this.skyCultureViewStore.detailsReady) &&
      !this.skyCultureViewStore.skyCultureListLoading) {
      this.onLoadList()
    }
  }

  private switchSubTab(next: number): void {
    if (this.subTab === next) return
    this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
      this.subTab = next
    })
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

  private currentCultureStory(): SkyCultureStoryZh | undefined {
    return getSkyCultureStoryZh(this.skyCultureViewStore.currentSkyCultureId)
  }

  private cultureSummary(id: string): string {
    const story = getSkyCultureStoryZh(id)
    return story !== undefined ? story.summaryZh : ''
  }

  private cultureHemisphere(id: string): string {
    const story = getSkyCultureStoryZh(id)
    return story !== undefined ? story.hemisphereZh : ''
  }

  private cultureDisplayNameById(id: string): string {
    for (const item of this.skyCultureViewStore.skyCultureList) {
      if (item.id === id) {
        return this.settings.skyCultureDisplayName(item.id, item.name)
      }
    }
    return this.settings.skyCultureDisplayName(id, id)
  }

  private spacetimeRecommendations(): Array<SkyCultureRecommendation> {
    if (this.skyCultureViewStore.skyCultureList.length === 0) return []
    const lat = this.observerLatitude !== 0 ? this.observerLatitude : this.settings.skyCultureObserverLatitude
    return recommendSkyCultures({
      latitude: lat,
      longitude: this.observerLongitude,
      simulationYear: this.settings.skyCultureSimulationYear,
      earthObserver: this.earthObserver,
      currentCultureId: this.selectedSkyCultureId(),
      items: this.skyCultureViewStore.skyCultureList
    })
  }

  private targetJumpYear(): number {
    return recommendedYearForCulture(
      this.settings.skyCultureBeginTime,
      this.settings.skyCultureEndTime,
      this.skyCultureViewStore.currentSkyCultureId
    )
  }

  private formatJumpYearLabel(year: number): string {
    if (year < 0) return '公元前 ' + Math.abs(year) + ' 年'
    return '公元 ' + year + ' 年'
  }

  private displayedCultures(): Array<SkyCultureItem> {
    const base = this.settings.filteredSkyCultureList(this.skyCultureViewStore.skyCultureList)
    if (this.quickGroup === 'all') return base
    return base.filter((sc: SkyCultureItem) => {
      const story = getSkyCultureStoryZh(sc.id)
      return story !== undefined && story.quickGroup === this.quickGroup
    })
  }

  private hasActiveAdvancedFilter(): boolean {
    return this.settings.skyCultureClassificationFilter !== 'all' ||
      this.settings.skyCultureRegionFilter !== 'all' ||
      this.settings.skyCultureTimeFiltering
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
    Column({ space: 8 }) {
      // 顶部三段清晰导览
      Row({ space: 4 }) {
        Button('探索文化' + (this.skyCultureViewStore.skyCultureList.length > 0 ? ' (' + this.skyCultureViewStore.skyCultureList.length + ')' : ''))
          .fontSize(11).fontWeight(this.subTab === 0 ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.subTab === 0 ? this.c.onAccent : this.c.text)
          .backgroundColor(this.subTab === 0 ? this.c.accent : Color.Transparent)
          .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).padding({ left: 6, right: 6 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.switchSubTab(0) })
        Button('文化详情')
          .fontSize(11).fontWeight(this.subTab === 1 ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.subTab === 1 ? this.c.onAccent : this.c.text)
          .backgroundColor(this.subTab === 1 ? this.c.accent : Color.Transparent)
          .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).padding({ left: 6, right: 6 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.switchSubTab(1) })
        Button('显示与标注')
          .fontSize(11).fontWeight(this.subTab === 2 ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.subTab === 2 ? this.c.onAccent : this.c.text)
          .backgroundColor(this.subTab === 2 ? this.c.accent : Color.Transparent)
          .borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1).padding({ left: 6, right: 6 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.switchSubTab(2) })
      }
      .width('100%').padding(3).backgroundColor(this.c.soft)
      .border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

      // ================= 分区一：探索文化（默认首屏） =================
      if (this.subTab === 0) {
        // 当前文化精简快捷条
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text('当前').fontSize(10).fontColor(this.c.accent)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
              Text(this.skyCultureViewStore.currentSkyCulture.length > 0 ? this.skyCultureViewStore.currentSkyCulture : I18n.t('culture_reading'))
                .fontSize(14).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.width('100%').alignItems(VerticalAlign.Center)
            if (this.currentCultureStory() !== undefined) {
              Text(this.currentCultureStory()!.regionZh + ' · ' + this.currentCultureStory()!.hemisphereZh)
                .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }.layoutWeight(1)
          Button('详情与地图 ›')
            .fontSize(11).fontColor(this.c.accent).backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.switchSubTab(1) })
        }
        .width('100%').padding({ left: 12, right: 10, top: 10, bottom: 10 })
        .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

        // 此时此地智能推荐条（按当前观测地 + 模拟年份动态匹配，绝不强行自动切换）
        if (this.spacetimeRecommendations().length > 0) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('✦ 此时此地推荐 · ' + this.settings.skyCultureFormatYear(this.settings.skyCultureSimulationYear))
                .fontSize(10).fontColor(this.c.accent).fontWeight(FontWeight.Medium).layoutWeight(1)
              InfoTipButton({
                title: '此时此地智能推荐',
                tip: '结合当前观测地经纬度与模拟年份，为你推荐最契合当地与该历史时期的星空文化。系统不会强行自动切换，点按胶囊即可一键体验。'
              })
            }.width('100%').alignItems(VerticalAlign.Center)
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.spacetimeRecommendations(), (rec: SkyCultureRecommendation) => {
                  Row({ space: 5 }) {
                    Text(this.cultureDisplayNameById(rec.id))
                      .fontSize(11).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1)
                    Text(rec.reasonZh)
                      .fontSize(9).fontColor(this.c.accent).maxLines(1)
                      .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                      .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
                  }
                  .height(30).padding({ left: 9, right: 7 })
                  .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_PILL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.storyExpanded = false; this.onSelectCulture(rec.id) })
                }, (rec: SkyCultureRecommendation) => rec.id + '-' + rec.reasonZh)
              }
            }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
          }
          .width('100%').padding({ left: 11, right: 11, top: 8, bottom: 9 })
          .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
        }

        // 搜索框 + 快捷分组胶囊
        Column({ space: 7 }) {
          Row({ space: 6 }) {
            TextInput({ text: this.settings.skyCultureSearchText, placeholder: '搜索 64 套文化（如：中国、宋代、玛雅、毛利）' })
              .fontSize(11).height(36).layoutWeight(1).backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL)
              .onChange((value: string) => { this.settings.skyCultureSearchText = value })
            Button(this.advancedFilterOpen ? '收起' : (this.hasActiveAdvancedFilter() ? '细筛 · 开' : '细筛 ▾'))
              .fontSize(10)
              .fontColor(this.hasActiveAdvancedFilter() || this.advancedFilterOpen ? this.c.accent : this.c.sub)
              .backgroundColor(this.hasActiveAdvancedFilter() ? this.c.accentSoft : this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 9, right: 9 })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
                  this.advancedFilterOpen = !this.advancedFilterOpen
                })
              })
          }.width('100%')

          Scroll() {
            Row({ space: 6 }) {
              ForEach(QUICK_CULTURE_GROUPS, (g: QuickCultureGroup) => {
                Button(g.label)
                  .fontSize(11)
                  .fontColor(this.quickGroup === g.id ? this.c.onAccent : this.c.text)
                  .backgroundColor(this.quickGroup === g.id ? this.c.accent : this.c.soft)
                  .border({ width: 0.5, color: this.quickGroup === g.id ? this.c.accent : this.c.border })
                  .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 11, right: 11 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.getUIContext().animateTo({ duration: 160, curve: curves.springMotion(0.46, 0.88) }, () => {
                      this.quickGroup = g.id
                    })
                  })
              }, (g: QuickCultureGroup) => g.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')

          if (this.advancedFilterOpen) {
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
              Row() {
                Text(I18n.t('culture_filter_by_year')).fontSize(11).fontColor(this.c.text).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureTimeFiltering }).width(40).height(22)
                  .onChange((enabled: boolean) => {
                    this.settings.skyCultureTimeFiltering = enabled
                    this.onSyncTimeFollowTimer()
                  })
              }.height(36).width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)

              if (this.settings.skyCultureTimeFiltering) {
                Column({ space: 5 }) {
                  Row({ space: 8 }) {
                    Text('筛选方式').fontSize(10).fontColor(this.c.sub).width(52)
                    Row({ space: 4 }) {
                      Button('单个年份').fontSize(10).fontColor(this.settings.skyCultureRangeFiltering ? this.c.sub : this.c.text)
                        .backgroundColor(this.settings.skyCultureRangeFiltering ? this.c.bg : this.c.accentSoft)
                        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
                        .onClick(() => {
                          this.settings.skyCultureRangeFiltering = false
                          this.settings.skyCultureTimeFollowSimulation = false
                          this.onSyncTimeFollowTimer()
                        })
                      Button('年代范围').fontSize(10).fontColor(this.settings.skyCultureRangeFiltering ? this.c.text : this.c.sub)
                        .backgroundColor(this.settings.skyCultureRangeFiltering ? this.c.accentSoft : this.c.bg)
                        .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
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
                      TextInput({ text: this.settings.skyCultureTimeYearInput, placeholder: '年份' }).fontSize(11).fontColor(this.c.text).height(28).width(76)
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
                      Text('跟随星图模拟时间').fontSize(10).fontColor(this.c.text).layoutWeight(1)
                      Button('同步').fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(26).padding({ left: 8, right: 8 })
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
                    }.width('100%').height(32).padding({ left: 8, right: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                    Slider({ value: this.settings.skyCultureTimeYear, min: -40000, max: this.settings.skyCultureFilterMaxYear(), step: 1, style: SliderStyle.OutSet })
                      .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                      .trackColor(this.c.bg).showSteps(false).showTips(false).width('100%')
                      .onChange((year: number) => { this.settings.setSkyCultureTimeYear(year) })
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
                  }
                }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
              }
            }.width('100%').padding(8).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
          }
        }.width('100%')

        // 64 套文化列表：精炼单行摘要，扫读效率高、不拥挤
        if (this.skyCultureViewStore.skyCultureListLoading) {
          GraphLoadingRow({ label: I18n.t('culture_catalog_reading') })
        } else if (this.displayedCultures().length === 0) {
          Column({ space: 8 }) {
            Text(I18n.t('culture_no_matching') + '。可重置筛选查看全部 64 套星空文化。')
              .fontSize(11).fontColor(this.c.sub).width('100%')
            Button('重置筛选').fontSize(11).fontColor(this.c.accent).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 })
              .onClick(() => {
                this.quickGroup = 'all'
                this.settings.skyCultureSearchText = ''
                this.settings.skyCultureClassificationFilter = 'all'
                this.settings.skyCultureRegionFilter = 'all'
                this.settings.skyCultureTimeFiltering = false
              })
          }
          .width('100%').padding(12).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CARD)
        } else {
          Column({ space: 6 }) {
            Text('匹配 ' + this.displayedCultures().length + ' 套文化 · 点按卡片切换')
              .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
            ForEach(this.displayedCultures(), (sc: SkyCultureItem) => {
              Row({ space: 10 }) {
                Row().width(3).height(38)
                  .backgroundColor(sc.id === this.selectedSkyCultureId() ? this.c.accent : this.c.border).borderRadius(2)
                Column({ space: 3 }) {
                  Row({ space: 6 }) {
                    Text(this.settings.skyCultureDisplayName(sc.id, sc.name))
                      .fontSize(13).fontColor(this.c.text)
                      .fontWeight(sc.id === this.selectedSkyCultureId() ? FontWeight.Medium : FontWeight.Regular)
                      .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    if (sc.id === this.selectedSkyCultureId()) {
                      Row({ space: 4 }) {
                        if (sc.id === this.skyCultureViewStore.pendingId) {
                          LoadingProgress().width(11).height(11).color(this.c.accent)
                        }
                        Text(sc.id === this.skyCultureViewStore.pendingId ? I18n.t('c_loading') : '✓ ' + I18n.t('culture_current'))
                          .fontSize(10).fontColor(this.c.accent).maxLines(1)
                      }.padding({ left: 7, right: 7, top: 2, bottom: 2 }).backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
                    } else if (this.cultureHemisphere(sc.id).length > 0) {
                      Text(this.cultureHemisphere(sc.id))
                        .fontSize(9).fontColor(this.c.tertiary).maxLines(1)
                    }
                  }.width('100%').alignItems(VerticalAlign.Center)
                  if (this.cultureSummary(sc.id).length > 0) {
                    Text(this.cultureSummary(sc.id))
                      .fontSize(11).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.layoutWeight(1)
              }
              .constraintSize({ minHeight: 58 }).width('100%').padding({ left: 11, right: 11, top: 8, bottom: 8 })
              .backgroundColor(sc.id === this.selectedSkyCultureId() ? this.c.chipInactiveBg : this.c.soft)
              .border({ width: 1, color: sc.id === this.selectedSkyCultureId() ? this.c.chipActiveBorder : this.c.border })
              .borderRadius(UI_RADIUS_CARD)
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
              .onAreaChange((oldArea: Area, newArea: Area) => { this.onRowArea(sc.id, newArea) })
              .onClick(() => { this.storyExpanded = false; this.onSelectCulture(sc.id) })
            }, (sc: SkyCultureItem) => sc.id)
          }.width('100%')
        }
      }

      // ================= 分区二：文化详情（精简三列指标 + 导读/胶囊/透气短段 + 花瓣地图 + 画廊） =================
      if (this.subTab === 1) {
        // 1. 当前文化精简头卡（极简三列指标，杜绝多行挤压）
        Column({ space: 9 }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(this.skyCultureViewStore.currentSkyCulture.length > 0 ? this.skyCultureViewStore.currentSkyCulture : I18n.t('culture_reading'))
                .fontSize(16).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(this.settings.skyCultureClassificationText(this.settings.skyCultureClassification) + ' · ' + this.settings.skyCultureRegionText(this.settings.skyCultureRegions))
                .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1)
            if (this.skyCultureViewStore.detailsLoading) {
              LoadingProgress().width(16).height(16).color(this.c.accent)
            }
          }.width('100%')

          if (this.skyCultureViewStore.detailsReady && this.skyCultureViewStore.currentSkyCultureId.length > 0) {
            // 三列单行极简数据栏
            Row({ space: 6 }) {
              Column({ space: 2 }) {
                Text(this.settings.skyCultureConstellationCount + ' 个').fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1)
                Text('星座图形').fontSize(10).fontColor(this.c.sub)
              }.layoutWeight(1).padding({ top: 7, bottom: 7 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)

              Column({ space: 2 }) {
                Text(this.settings.skyCultureArtCount > 0 ? (this.settings.skyCultureArtCount + ' 幅') : '无绘像').fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1)
                Text('星座绘像').fontSize(10).fontColor(this.c.sub)
              }.layoutWeight(1).padding({ top: 7, bottom: 7 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)

              Column({ space: 2 }) {
                Text(formatShortEraRange(this.settings.skyCultureBeginTime, this.settings.skyCultureEndTime))
                  .fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text('适用年代').fontSize(10).fontColor(this.c.sub)
              }.layoutWeight(1).padding({ top: 7, bottom: 7, left: 4, right: 4 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            }.width('100%')

            // 时光一键对齐：仅当模拟时间不在该文化历史年代内时出现，化被动提示为主动穿越体验
            if (!this.settings.skyCultureSimulationTimeMatches()) {
              Row({ space: 8 }) {
                Text('当前模拟年份不在该文化历史年代内')
                  .fontSize(10).fontColor(this.c.sub).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Button('跳至 ' + this.formatJumpYearLabel(this.targetJumpYear()))
                  .fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.accentSoft)
                  .borderRadius(UI_RADIUS_PILL).height(26).padding({ left: 10, right: 10 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.onJumpToCultureYear(this.targetJumpYear()) })
              }
              .width('100%').padding({ left: 10, right: 8, top: 6, bottom: 6 })
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).alignItems(VerticalAlign.Center)
            }
          }

          Row({ space: 8 }) {
            Button(this.settings.skyCultureDefaultId === this.skyCultureViewStore.currentSkyCultureId ? '✓ 已设为默认文化' : '设为启动默认')
              .fontSize(11).fontColor(this.settings.skyCultureDefaultId === this.skyCultureViewStore.currentSkyCultureId ? this.c.accent : this.c.text)
              .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1)
              .enabled(this.settings.skyCultureDefaultId !== this.skyCultureViewStore.currentSkyCultureId)
              .onClick(() => { this.onSetDefault() })
            Button('切换其他文化')
              .fontSize(11).fontColor(this.c.accent).backgroundColor(this.c.accentSoft)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 })
              .onClick(() => { this.switchSubTab(0) })
          }.width('100%')
        }
        .width('100%').padding({ left: 12, right: 12, top: 11, bottom: 11 })
        .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

        if (this.skyCultureViewStore.detailsLoading && !this.skyCultureViewStore.detailsReady) {
          GraphLoadingRow({ label: I18n.t('culture_loading') })
        } else if (this.skyCultureViewStore.detailError.length > 0 && !this.skyCultureViewStore.detailsReady) {
          Text(this.skyCultureViewStore.detailError).fontSize(11).fontColor(this.c.sub).width('100%').padding(10)
        } else {
          // 2. 渐进式杂志排版导览卡：1 句精华导读 + 代表星象胶囊 + 按需展开透气短段故事
          if (this.currentCultureStory() !== undefined) {
            Column({ space: 9 }) {
              Row({ space: 8 }) {
                Row().width(3).height(16).backgroundColor(this.c.accent).borderRadius(2)
                Text('人类共同的星空 · 文化导览').fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1)
                InfoTipButton({
                  title: '星空文化平等互鉴说明',
                  tip: '全球各文明与世居族群仰望同一片苍穹，共同铸就了全人类共享的天文文化遗产。地域称谓仅反映历史天文渊源，不代表现行行政区划。'
                })
              }.width('100%')

              // 一句话核心导读（2 秒读懂该文化精髓，绝不默认堆大段密字）
              Text(this.currentCultureStory()!.summaryZh)
                .fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%').lineHeight(20)

              // 代表星象独立胶囊标签
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(splitHighlightTags(this.currentCultureStory()!.highlightsZh), (tag: string) => {
                  Text(tag)
                    .fontSize(10).fontColor(this.c.accent)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .margin({ right: 6, bottom: 5 })
                    .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_PILL)
                }, (tag: string) => tag)
              }.width('100%')

              // 按需展开完整故事（拆分为透气短段，行距 22vp，读起来舒展不累眼）
              if (this.storyExpanded) {
                Column({ space: 8 }) {
                  ForEach(splitAiryParagraphs(this.currentCultureStory()!.storyZh), (para: string, idx: number) => {
                    Text(para).fontSize(12).fontColor(this.c.text).width('100%').lineHeight(21)
                  }, (para: string, idx: number) => 'story-p-' + idx)
                }
                .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
                .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
              }

              Row() {
                Text(this.currentCultureStory()!.hemisphereZh).fontSize(10).fontColor(this.c.sub).layoutWeight(1)
                Button(this.storyExpanded ? '收起文化故事 ▴' : '阅读文化故事 ▾')
                  .fontSize(11).fontColor(this.c.accent).backgroundColor(this.c.soft)
                  .borderRadius(UI_RADIUS_PILL).height(28).padding({ left: 11, right: 11 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
                      this.storyExpanded = !this.storyExpanded
                    })
                  })
              }.width('100%').alignItems(VerticalAlign.Center)
            }
            .width('100%').padding({ left: 12, right: 12, top: 11, bottom: 11 })
            .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

            // 3. 观星渊源坐标 · 华为花瓣地图（官方深色审图底图 + 居中单点坐标标靶，零疆域多边形）
            SkyCulturePetalMapCard({
              cultureId: this.skyCultureViewStore.currentSkyCultureId,
              originLabelZh: this.currentCultureStory()!.originLabelZh,
              regionZh: this.currentCultureStory()!.regionZh,
              hemisphereZh: this.currentCultureStory()!.hemisphereZh,
              latitude: this.currentCultureStory()!.originLat,
              longitude: this.currentCultureStory()!.originLon,
              zoomLevel: this.currentCultureStory()!.originZoom,
              isGlobal: this.currentCultureStory()!.isGlobal === true,
              onlineAllowed: this.previewMapAllowed
            })
          }

          // 4. 星座绘像画廊
          if (this.skyCultureViewStore.artItems.length > 0) {
            Column({ space: 6 }) {
              Row() {
                Column({ space: 1 }) {
                  Text(I18n.t('culture_art_gallery')).fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
                  Text(this.skyCultureViewStore.artItems.length + ' ' + I18n.t('culture_offline_art')).fontSize(10).fontColor(this.c.sub).width('100%')
                }.layoutWeight(1)
                Button(this.skyCultureViewStore.artExpanded ? '收起画廊' : '展开画廊')
                  .fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
                  .onClick(() => { this.skyCultureViewStore.artExpanded = !this.skyCultureViewStore.artExpanded })
              }.width('100%')
              if (this.skyCultureViewStore.artExpanded) {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(this.skyCultureViewStore.artItems.slice(0, 24), (art: SkyCultureArtItem) => {
                    Column({ space: 3 }) {
                      if (this.skyCultureViewStore.artThumbnails[art.rawPath] !== undefined) {
                        Image(this.skyCultureViewStore.artThumbnails[art.rawPath]).width('100%').aspectRatio(1).objectFit(ImageFit.Contain)
                          .backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                          .onError(() => { this.onArtDecodeError(art.rawPath) })
                      } else if (this.artStatus(art.rawPath) === 'ready' || this.artStatus(art.rawPath) === 'preparing') {
                        Stack({ alignContent: Alignment.Center }) {
                          LoadingProgress().width(22).height(22).color(this.c.accent)
                        }.width('100%').aspectRatio(1).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                      } else {
                        Text(this.artStatus(art.rawPath) === 'decodeFailed' ? '解码失败' : '未安装')
                          .fontSize(10).fontColor(this.c.sub).width('100%').aspectRatio(1)
                          .textAlign(TextAlign.Center).backgroundColor(this.c.thumbBg).borderRadius(UI_RADIUS_CONTROL)
                      }
                      Text(art.name !== undefined && art.name.length > 0 ? art.name : '星座绘图 ' + art.index)
                        .fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).textAlign(TextAlign.Center)
                    }.width('31%').padding(4).margin({ right: 2, bottom: 8 }).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
                      .onClick(() => { this.onOpenArtPreview(art) })
                  }, (art: SkyCultureArtItem) => art.rawPath)
                }.width('100%').padding({ top: 4 })
                if (this.skyCultureViewStore.artItems.length > 24) {
                  Text('已展示前 24 幅，其余绘图随星图图层按需加载。').fontSize(10).fontColor(this.c.sub).width('100%')
                }
              }
            }
            .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
          }

          // 5. 默认折叠的原始学术参考与历史年代纯文字档案
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('学术原典与历史年代档案').fontSize(12).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1)
              Button(this.academicRefOpen ? '收起 ▴' : '展开 ▾')
                .fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL).height(26).padding({ left: 9, right: 9 })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
                    this.academicRefOpen = !this.academicRefOpen
                  })
                })
            }.width('100%').alignItems(VerticalAlign.Center)

            if (this.academicRefOpen) {
              if (this.skyCultureViewStore.narration.length > 0) {
                Column({ space: 8 }) {
                  Text(I18n.t('culture_constellation_intro')).fontSize(11).fontColor(this.c.sub).width('100%')
                  ForEach(this.skyCultureViewStore.narrationExpanded ? this.narrationParagraphs : this.narrationParagraphs.slice(0, 2), (paragraph: string) => {
                    Text(paragraph).fontSize(12).fontColor(this.c.text).width('100%').lineHeight(21)
                  }, (paragraph: string, index: number) => 'narration-' + index + '-' + paragraph)
                  if (this.narrationParagraphs.length > 2) {
                    Button(I18n.t(this.skyCultureViewStore.narrationExpanded ? 'culture_collapse_intro' : 'culture_expand_intro'))
                      .fontSize(10).fontColor(this.c.accent).backgroundColor(Color.Transparent).height(26).padding(0)
                      .onClick(() => { this.skyCultureViewStore.narrationExpanded = !this.skyCultureViewStore.narrationExpanded })
                  }
                }.width('100%').padding(10).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
              }

              if (this.skyCultureViewStore.description.length > 0 && this.skyCultureViewStore.description !== this.skyCultureViewStore.narration) {
                Column({ space: 6 }) {
                  Text(I18n.t('culture_full_material')).fontSize(11).fontColor(this.c.sub).width('100%')
                  if (this.skyCultureViewStore.descriptionBlocks.length > 0) {
                    Column({ space: 6 }) {
                      ForEach(this.skyCultureViewStore.descriptionExpanded ? this.skyCultureViewStore.descriptionBlocks : this.skyCultureViewStore.descriptionBlocks.slice(0, 5), (block: SkyCultureDescriptionBlock) => {
                        SkyCultureDescriptionBlockView({
                          kind: block.kind,
                          headingLarge: block.level !== undefined && block.level <= 1,
                          text: block.text,
                          cells: block.cells !== undefined ? block.cells : []
                        })
                      }, (block: SkyCultureDescriptionBlock) => 'description-' + block.index)
                    }.width('100%')
                  } else {
                    Text(this.skyCultureViewStore.description).fontSize(12).fontColor(this.c.text).width('100%')
                      .lineHeight(21).maxLines(this.skyCultureViewStore.descriptionExpanded ? 999 : 5).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  Button(this.skyCultureViewStore.descriptionExpanded ? I18n.t('culture_hide_full_material') : I18n.t('culture_read_full_material'))
                    .fontSize(10).fontColor(this.c.accent).backgroundColor(Color.Transparent).height(26).padding(0)
                    .onClick(() => { this.skyCultureViewStore.descriptionExpanded = !this.skyCultureViewStore.descriptionExpanded })
                }.width('100%').padding(10).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
              }

              if (this.settings.skyCultureHasTerritoryArchive) {
                Column({ space: 4 }) {
                  Text('历史流传时期档案（纯文字，共 ' + this.settings.skyCultureTerritorySegmentCount + ' 条）')
                    .fontSize(11).fontColor(this.c.sub).width('100%')
                  ForEach(this.settings.skyCultureTerritoryEntriesForSelectedYear(), (entry: SkyCultureTerritoryEntry, index: number) => {
                    Row({ space: 8 }) {
                      Text(entry.name.length > 0 ? entry.name : '历史流传时期').fontSize(11).fontColor(this.c.text).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(this.settings.skyCultureTerritoryRange(entry)).fontSize(10).fontColor(this.c.sub)
                    }.width('100%').padding({ left: 8, right: 8, top: 5, bottom: 5 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                  }, (entry: SkyCultureTerritoryEntry, index: number) => entry.name + '-' + entry.beginTime + '-' + entry.endTime + '-' + index)
                }.width('100%').padding(10).backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
              }

              if (this.settings.skyCultureLicense.length > 0) {
                Text('资料许可：' + this.settings.skyCultureLicense).fontSize(10).fontColor(this.c.sub).width('100%')
              }
              Button('重新载入当前文化数据')
                .fontSize(10).fontColor(this.c.text).backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
                .onClick(() => { this.onReloadList() })
            }
          }
          .width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
        }
      }

      // ================= 分区三：显示与标注 =================
      if (this.subTab === 2) {
        SkyCultureSectionHeader({ title: I18n.t('culture_section_layers'), subtitle: '快速控制星空上的星座线、绘像与星群' })
        Column({ space: 2 }) {
          LayerSwitchRow({ label: I18n.t('s0522'), isOn: this.layerStore.constellationLines, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Lines', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0523'), isOn: this.layerStore.constellationLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Labels', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0525'), isOn: this.layerStore.constellationArt, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Art', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0524'), isOn: this.layerStore.constellationBoundaries, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Boundaries', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0539'), isOn: this.layerStore.constellationHulls, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Constellation_Hulls', '', value) } })
          Row({ space: 6 }) {
            Text(I18n.t('culture_models_preview')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
            InfoTipButton({ title: '3D 星座立体预览', tip: '开启后，现代与 IAU 文化下支持以立体网格形式预览星座绘像，并可在天体详情卡中自由旋转查看。' })
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureConstellationArt3d })
              .width(42).height(24).id('skyculture-art-models-toggle')
              .onChange((value: boolean) => { this.onSetVisualSetting('constellationArt3d', value ? 1 : 0) })
          }.height(40).width('100%').padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
          Row({ space: 6 }) {
            Text(I18n.t('culture_line_center_anim')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
            InfoTipButton({ title: '居中连线绘制动画', tip: '转动星图时，位于视野中央的星座会自动以渐进连线动画浮现，让认星更具层次感。' })
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureConstellationLineCenterAnim })
              .width(42).height(24).id('skyculture-line-center-anim-toggle')
              .onChange((value: boolean) => { this.onSetVisualSetting('constellationLineCenterAnim', value ? 1 : 0) })
          }.height(40).width('100%').padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
          Row({ space: 6 }) {
            Text('时空变更时推荐匹配文化').fontSize(13).fontColor(this.c.text).layoutWeight(1)
            InfoTipButton({ title: '时空智能推荐胶囊', tip: '当你在位置面板手动切换地区或在时间面板大幅跨越历史年代时，底部会短暂弹出轻量推荐胶囊，点按即切、绝不强行打断当前观测。' })
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureSmartRecommend })
              .width(42).height(24)
              .onChange((value: boolean) => { this.settings.skyCultureSmartRecommend = value })
          }.height(40).width('100%').padding({ left: 10, right: 10 }).alignItems(VerticalAlign.Center)
          LayerSwitchRow({ label: I18n.t('s0526'), isOn: this.layerStore.zodiac, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Zodiac', '', value) } })
          LayerSwitchRow({ label: I18n.t('s0527'), isOn: this.layerStore.lunarSystem, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_LunarSystem', '', value) } })
          if (this.settings.skyCultureHasAsterisms) {
            LayerSwitchRow({ label: I18n.t('s0528'), isOn: this.layerStore.asterismLines, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Asterism_Lines', '', value) } })
            LayerSwitchRow({ label: I18n.t('s0529'), isOn: this.layerStore.asterismLabels, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Asterism_Labels', '', value) } })
            LayerSwitchRow({ label: I18n.t('s0540'), isOn: this.layerStore.rayHelpers, onToggle: (value: boolean) => { this.onToggleLayer('actionShow_Ray_Helpers', '', value) } })
          }
        }.width('100%').padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

        SkyCultureSectionHeader({ title: I18n.t('culture_section_labels'), subtitle: '星图标注语言与点选聚焦方式' })
        Column({ space: 6 }) {
          SkyCultureLabelSettingCard({
            target: 'screen',
            title: '星图标注',
            options: this.settings.skyCultureLabelModeOptions('screen'),
            mode: this.settings.skyCultureLabelModeForTarget('screen'),
            isOpen: this.settings.skyCultureLabelPickerOpen === 'screen',
            onToggle: (target: string) => { this.toggleLabelPicker(target) },
            onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
          })
          Row() {
            Text('使用星座短名称').fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureShortLabels }).width(40).height(22)
              .onChange((enabled: boolean) => { this.onSetShortLabels(enabled) })
          }.height(34).width('100%').padding({ left: 6, right: 6 })
          Row() {
            Text('显示国际通用名称').fontSize(11).fontColor(this.settings.skyCultureUsesCommonNames ? this.c.text : this.c.sub).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureOverrideCommonNames }).width(40).height(22)
              .enabled(this.settings.skyCultureUsesCommonNames)
              .opacity(this.settings.skyCultureUsesCommonNames ? 1 : 0.45)
              .onChange((enabled: boolean) => { this.onSetCommonNames(enabled) })
          }.height(34).width('100%').padding({ left: 6, right: 6 })
          Row() {
            Text('选中星座时单独显示').fontSize(11).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureIsolateSelected }).width(40).height(22)
              .onChange((enabled: boolean) => { this.onSetIsolation(enabled) })
          }.height(34).width('100%').padding({ left: 6, right: 6 })
          if (this.settings.skyCultureIsolateSelected) {
            Row() {
              Text('仅保留最后选中的星座').fontSize(11).fontColor(this.c.text).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureSinglePick }).width(40).height(22)
                .onChange((enabled: boolean) => { this.onSetSinglePick(enabled) })
            }.height(34).width('100%').padding({ left: 6, right: 6 })
          }
          Row({ space: 6 }) {
            Button('全选星座').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30)
              .layoutWeight(1).onClick(() => { this.onConstellationSelection('actionShow_Constellation_Select', '已选中全部星座') })
            Button('清除选择').fontSize(10).fontColor(this.c.text).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).height(30)
              .layoutWeight(1).onClick(() => { this.onConstellationSelection('actionShow_Constellation_Deselect', '已清除星座选择') })
          }.width('100%').padding({ top: 2 })
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

        SkyCultureSectionHeader({ title: I18n.t('culture_section_readability'), subtitle: '字号、线宽与绘像明暗' })
        Column({ space: 4 }) {
          Row() {
            Text('星座标签字号').fontSize(11).fontColor(this.c.text).width(84)
            Text(this.settings.skyCultureConstellationFontSize.toFixed(0)).fontSize(11).fontColor(this.c.sub).width(28).textAlign(TextAlign.End)
            Slider({ value: this.settings.skyCultureConstellationFontSize, min: 8, max: 40, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
              .onChange((value: number) => { this.onSetVisualSetting('constellationFontSize', value) })
          }.height(34).width('100%')
          Row() {
            Text('星座连线粗细').fontSize(11).fontColor(this.c.text).width(84)
            Text(this.settings.skyCultureConstellationLineThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
            Slider({ value: this.settings.skyCultureConstellationLineThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
              .onChange((value: number) => { this.onSetVisualSetting('constellationLineThickness', value) })
          }.height(34).width('100%')
          Row() {
            Text('星座边界粗细').fontSize(11).fontColor(this.c.text).width(84)
            Text(this.settings.skyCultureConstellationBoundaryThickness.toFixed(0) + ' px').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
            Slider({ value: this.settings.skyCultureConstellationBoundaryThickness, min: 1, max: 5, step: 1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
              .onChange((value: number) => { this.onSetVisualSetting('constellationBoundaryThickness', value) })
          }.height(34).width('100%')
          Row() {
            Text('星座绘图亮度').fontSize(11).fontColor(this.c.text).width(84)
            Text(Math.round(this.settings.skyCultureConstellationArtIntensity * 100) + '%').fontSize(11).fontColor(this.c.sub).width(32).textAlign(TextAlign.End)
            Slider({ value: this.settings.skyCultureConstellationArtIntensity, min: 0, max: 1, step: 0.05, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
              .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
              .onChange((value: number) => { this.onSetVisualSetting('constellationArtIntensity', value) })
          }.height(34).width('100%')
        }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)

        Column({ space: 6 }) {
          Row() {
            Column({ space: 1 }) {
              Text('高级微调（配色 / 过渡时长 / 组合名称）').fontSize(11).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
              Text('按需展开调整图层颜色、淡入时长及多语名称组合').fontSize(10).fontColor(this.c.sub).width('100%')
            }.layoutWeight(1)
            Button(this.advancedDisplayOpen ? '收起 ▴' : '展开 ▾')
              .fontSize(10).fontColor(this.c.accent).backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL).height(26).padding({ left: 9, right: 9 })
              .onClick(() => {
                this.getUIContext().animateTo({ duration: 180, curve: curves.springMotion(0.46, 0.88) }, () => {
                  this.advancedDisplayOpen = !this.advancedDisplayOpen
                })
              })
          }.width('100%')

          if (this.advancedDisplayOpen) {
            Column({ space: 5 }) {
              Text('淡入淡出时长').fontSize(11).fontColor(this.c.sub).width('100%')
              Row() {
                Text('星座连线').fontSize(11).fontColor(this.c.text).width(80)
                Text(this.settings.skyCultureConstellationLinesFadeDuration.toFixed(1) + ' 秒').fontSize(10).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
                Slider({ value: this.settings.skyCultureConstellationLinesFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                  .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
                  .onChange((value: number) => { this.onSetVisualSetting('constellationLinesFadeDuration', value) })
              }.height(32).width('100%')
              Row() {
                Text('星座标签').fontSize(11).fontColor(this.c.text).width(80)
                Text(this.settings.skyCultureConstellationLabelsFadeDuration.toFixed(1) + ' 秒').fontSize(10).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
                Slider({ value: this.settings.skyCultureConstellationLabelsFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                  .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
                  .onChange((value: number) => { this.onSetVisualSetting('constellationLabelsFadeDuration', value) })
              }.height(32).width('100%')
              Row() {
                Text('星座绘图').fontSize(11).fontColor(this.c.text).width(80)
                Text(this.settings.skyCultureConstellationArtFadeDuration.toFixed(1) + ' 秒').fontSize(10).fontColor(this.c.sub).width(38).textAlign(TextAlign.End)
                Slider({ value: this.settings.skyCultureConstellationArtFadeDuration, min: 0.1, max: 10, step: 0.1, style: SliderStyle.OutSet }).sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
                  .layoutWeight(1).trackColor(this.c.bg).showSteps(false).showTips(false)
                  .onChange((value: number) => { this.onSetVisualSetting('constellationArtFadeDuration', value) })
              }.height(32).width('100%')

              Text('图层颜色').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4 })
              if (this.getColorOptions().length === 0) {
                Text('请先在上方开启星座、星群、黄道或月宿图层。').fontSize(10).fontColor(this.c.sub).width('100%')
              } else {
                ForEach(this.getColorOptions(), (option: ConfigurationOption) => {
                  Row({ space: 8 }) {
                    Stack() {
                      Circle().width(16).height(16).fill(this.settings.skyCultureVisualColor(option.id))
                      Circle().width(16).height(16).fillOpacity(0).stroke(this.c.text).strokeWidth(1)
                    }.width(20).height(20)
                    Text(option.label).fontSize(11).fontColor(this.c.text).layoutWeight(1)
                    Text(this.settings.skyCultureVisualColor(option.id)).fontSize(10).fontColor(this.c.sub)
                  }.height(32).width('100%').padding({ left: 8, right: 8 })
                    .backgroundColor(option.id === this.activeColorTarget() ? this.c.softStrong : this.c.bg)
                    .border({ width: option.id === this.activeColorTarget() ? 1 : 0, color: option.id === this.activeColorTarget() ? this.c.accent : Color.Transparent })
                    .borderRadius(UI_RADIUS_CONTROL)
                    .onClick(() => { this.settings.selectSkyCultureColorTarget(option.id) })
                }, (option: ConfigurationOption) => option.id)
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
                }.width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ left: 4, right: 4, top: 2, bottom: 2 })
              }

              SkyCultureLabelSettingCard({
                target: 'info',
                title: '资料中的名称',
                options: this.settings.skyCultureLabelModeOptions('info'),
                mode: this.settings.skyCultureLabelModeForTarget('info'),
                isOpen: this.settings.skyCultureLabelPickerOpen === 'info',
                onToggle: (target: string) => { this.toggleLabelPicker(target) },
                onSelectMode: (target: string, index: number) => { this.onSelectLabelMode(target, index) }
              })

              Text('组合名称样式（星图）').fontSize(11).fontColor(this.c.sub).width('100%').margin({ top: 4 })
              ForEach(this.settings.skyCultureStyleOptions(), (option: ConfigurationOption, optionIndex: number) => {
                Row() {
                  Text(option.label).fontSize(10).fontColor(this.c.text).layoutWeight(1)
                  Toggle({ type: ToggleType.Switch, isOn: this.settings.skyCultureStyleMaskHas(this.settings.skyCultureScreenStyleMask, optionIndex) }).width(38).height(21)
                    .onChange((enabled: boolean) => { this.onSetStyleOption('screen', optionIndex, enabled) })
                }.height(28).width('100%').padding({ left: 6, right: 6 })
              }, (option: ConfigurationOption) => 'screen-' + option.id)
            }.width('100%').padding({ top: 6 })
          }
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor(this.c.soft).border({ width: 0.5, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
      }
    }.width('100%')
  }
}
