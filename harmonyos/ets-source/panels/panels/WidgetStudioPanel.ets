import { LengthMetrics, Theme } from '@kit.ArkUI'
import { common, Want } from '@kit.AbilityKit'
import { formBindingData, formInfo, formProvider } from '@kit.FormKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { panelFontSize } from '../../common/ui/UiTypography'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { RegionScopePicker } from '../../common/ui/RegionScopePicker'
import {
  CardInstanceConfig,
  SUPPORTED_EDIT_PLANETS,
  defaultCardConfig,
  planetSymbol,
  planetZhName
} from '../../form/AstronomyCardData'
import {
  readFormConfig,
  readGlobalWidgetConfig,
  readWidgetRegionId,
  resolveCardDataForForm,
  writeFormConfig,
  writeGlobalWidgetConfig,
  writeWidgetRegionId
} from '../../form/FormStoreHelper'
import { FOLLOW_REGION_ID, normalizeObserverRegionId } from '../../state/ObserverRegionScope'

const DOMAIN: number = 0xD003
const TAG: string = 'WidgetStudioPanel'

interface WidgetCatalogMeta {
  formName: string
  titleZh: string
  titleEn: string
  sizes: string
  descZh: string
  descEn: string
  supportsReminder: boolean
  supportsPlanet: boolean
  supportsLabels: boolean
  supportsTheme: boolean
  accentHex: string
}

interface RunningWidgetEntry {
  formId: string
  formName: string
  dimensionLabel: string
  planetMode: string
  themeStyle: string
  labelStyle: string
  overflowMode: string
}

interface StudioOption {
  value: string
  labelZh: string
  labelEn: string
}

const WIDGET_CATALOG: WidgetCatalogMeta[] = [
  {
    formName: 'astronomy_calendar_card',
    titleZh: '天文月历',
    titleEn: 'Astronomy Calendar',
    sizes: '4×4 / 2×4',
    descZh: '完整月相网格、朔望弦标记、流星雨/节气圆点与一键预约重磅天象',
    descEn: 'Monthly moon phases, meteor peaks, solar terms & one-tap reminders',
    supportsReminder: true, supportsPlanet: true, supportsLabels: false, supportsTheme: true,
    accentHex: '#64B5F6'
  },
  {
    formName: 'celestial_events_card',
    titleZh: '天象预告',
    titleEn: 'Celestial Events',
    sizes: '2×4 / 4×4',
    descZh: '近期重点天象倒计时、分页浏览，支持直接在桌面预约或取消提醒',
    descEn: 'Upcoming events countdown with direct desktop reminder booking',
    supportsReminder: true, supportsPlanet: true, supportsLabels: true, supportsTheme: true,
    accentHex: '#FFD166'
  },
  {
    formName: 'satellite_pass_card',
    titleZh: '卫星过境',
    titleEn: 'Satellite Passes',
    sizes: '2×2 / 2×4 / 4×4',
    descZh: '国际空间站与天宫可见过境雷达航迹，支持桌面一键预约过境提醒',
    descEn: 'ISS & Tiangong pass radar with one-tap countdown reminders',
    supportsReminder: true, supportsPlanet: false, supportsLabels: false, supportsTheme: true,
    accentHex: '#4DD0E1'
  },
  {
    formName: 'sky_window_card',
    titleZh: '星穹窗口',
    titleEn: 'Sky Window',
    sizes: '2×2 / 2×4 / 4×4',
    descZh: '实时晨昏天色、今日月相、可见行星与未来 48h 时间预览',
    descEn: 'Live twilight sky, moon phase, visible planets & 48h preview',
    supportsReminder: false, supportsPlanet: true, supportsLabels: true, supportsTheme: true,
    accentHex: '#7FB2FF'
  },
  {
    formName: 'solar_arc_card',
    titleZh: '太阳视运动',
    titleEn: 'Solar Arc',
    sizes: '2×2 / 2×4',
    descZh: '太阳高度弧线、日出日落与天文暮光暗夜窗口',
    descEn: 'Solar altitude arc, sunrise/sunset & astronomical twilight window',
    supportsReminder: false, supportsPlanet: true, supportsLabels: false, supportsTheme: true,
    accentHex: '#FFB74D'
  },
  {
    formName: 'companion_arc_card',
    titleZh: '伴星月相',
    titleEn: 'Moon & Companion',
    sizes: '2×2 / 2×4',
    descZh: '高清月相/外星伴星轨迹、月龄与照明度一览',
    descEn: 'Lunar / off-Earth companion phase disc, age & illumination',
    supportsReminder: false, supportsPlanet: true, supportsLabels: false, supportsTheme: true,
    accentHex: '#C8DEFA'
  },
  {
    formName: 'solar_system_card',
    titleZh: '太阳系仪',
    titleEn: 'Solar System Orrery',
    sizes: '2×2 / 4×4',
    descZh: '实时日心行星轨道俯视图，支持按日步进与内外行星切换',
    descEn: 'Live heliocentric planetary orrery with day stepping',
    supportsReminder: false, supportsPlanet: false, supportsLabels: false, supportsTheme: true,
    accentHex: '#95E1D3'
  },
  {
    formName: 'floating_orb_card',
    titleZh: '天体浮球',
    titleEn: 'Celestial Orb',
    sizes: '2×2',
    descZh: '极简悬浮天体图标，支持切换任意太阳系行星与破框动效',
    descEn: 'Minimal floating planet orb with custom world binding',
    supportsReminder: false, supportsPlanet: true, supportsLabels: false, supportsTheme: false,
    accentHex: '#B39DDB'
  }
]

const THEME_OPTIONS: StudioOption[] = [
  { value: 'sky', labelZh: '实时天穹', labelEn: 'Live Sky' },
  { value: 'deep', labelZh: '深空极简', labelEn: 'Deep Space' }
]

const LABEL_OPTIONS: StudioOption[] = [
  { value: 'name', labelZh: '中文名称', labelEn: 'Names' },
  { value: 'symbol', labelZh: '天文符号 ♃', labelEn: 'Symbols ♃' }
]

const OVERFLOW_OPTIONS: StudioOption[] = [
  { value: 'auto', labelZh: '自动与点击', labelEn: 'Auto + Tap' },
  { value: 'tap', labelZh: '仅点击触发', labelEn: 'Tap Only' },
  { value: 'off', labelZh: '关闭破框', labelEn: 'Off' }
]

function dimensionLabelOf(dim: number): string {
  if (dim === 1) return '1×2'
  if (dim === 2) return '2×2'
  if (dim === 3) return '2×4'
  if (dim === 4) return '4×4'
  return '卡片'
}

function catalogMetaFor(formName: string): WidgetCatalogMeta {
  for (let i = 0; i < WIDGET_CATALOG.length; i++) {
    if (WIDGET_CATALOG[i].formName === formName) return WIDGET_CATALOG[i]
  }
  return WIDGET_CATALOG[3]
}

@Component
export struct WidgetStudioPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop language: string = 'zh'
  @Prop followLocationName: string = ''
  @Prop remindedCount: number = 0
  onSyncAllWidgets: () => void = () => {}
  onOpenNotifications: () => void = () => {}
  onFlashHint: (msg: string) => void = () => {}

  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private loading: boolean = false
  @State private widgetRegionId: string = FOLLOW_REGION_ID
  @State private runningWidgets: RunningWidgetEntry[] = []
  @State private expandedFormId: string = ''
  @State private showGlobalDefaults: boolean = false
  @State private globalPlanetMode: string = 'follow'
  @State private globalThemeStyle: string = 'sky'
  @State private globalLabelStyle: string = 'name'
  @State private globalOverflowMode: string = 'auto'
  @State private statusNote: string = ''

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  aboutToAppear(): void {
    this.reloadStudioState()
  }

  private isZh(): boolean {
    return this.language.toLowerCase().startsWith('zh')
  }

  private t(zh: string, en: string): string {
    return this.isZh() ? zh : en
  }

  private hostContext(): common.UIAbilityContext | undefined {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext
    } catch (_) {
      return undefined
    }
  }

  private reloadStudioState(): void {
    const ctx = this.hostContext()
    if (ctx === undefined) return
    this.widgetRegionId = normalizeObserverRegionId(readWidgetRegionId(ctx))
    const gCfg = readGlobalWidgetConfig(ctx)
    this.globalPlanetMode = gCfg.planetMode
    this.globalThemeStyle = gCfg.themeStyle
    this.globalLabelStyle = gCfg.labelStyle
    this.globalOverflowMode = gCfg.overflowMode
    this.loading = true
    formProvider.getPublishedRunningFormInfos().then((infos: Array<formInfo.RunningFormInfo>) => {
      const list: RunningWidgetEntry[] = []
      for (let i = 0; i < infos.length; i++) {
        const info = infos[i]
        if (info.bundleName !== 'com.joinother.skyinstrument') continue
        const cfg = readFormConfig(ctx, info.formId)
        list.push({
          formId: info.formId,
          formName: info.formName,
          dimensionLabel: dimensionLabelOf(Number(info.dimension)),
          planetMode: cfg.planetMode,
          themeStyle: cfg.themeStyle,
          labelStyle: cfg.labelStyle,
          overflowMode: cfg.overflowMode
        })
      }
      this.runningWidgets = list
      if (list.length > 0 && this.expandedFormId.length === 0) {
        this.expandedFormId = list[0].formId
      }
      this.loading = false
    }).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'getPublishedRunningFormInfos failed: %{public}s', String(err?.message ?? err))
      this.loading = false
    })
  }

  private pushFormUpdate(ctx: common.UIAbilityContext, formId: string): void {
    const data = resolveCardDataForForm(ctx, formId, Date.now())
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data)).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'updateForm failed id=%{public}s code=%{public}d', formId, err?.code ?? -1)
    })
  }

  private pushAllRunningForms(ctx: common.UIAbilityContext): void {
    for (let i = 0; i < this.runningWidgets.length; i++) {
      this.pushFormUpdate(ctx, this.runningWidgets[i].formId)
    }
  }

  private updateWidgetRegion(regionId: string): void {
    const ctx = this.hostContext()
    if (ctx === undefined) return
    const safe = normalizeObserverRegionId(regionId)
    this.widgetRegionId = safe
    writeWidgetRegionId(ctx, safe)
    this.pushAllRunningForms(ctx)
    this.onSyncAllWidgets()
    this.statusNote = this.t('已更新桌面小组件地理区域并同步卡片。', 'Widget region updated and synced.')
    this.onFlashHint(this.statusNote)
  }

  private updateSingleWidgetConfig(
    formId: string,
    planetMode: string,
    themeStyle: string,
    labelStyle: string,
    overflowMode: string
  ): void {
    const ctx = this.hostContext()
    if (ctx === undefined) return
    const cfg: CardInstanceConfig = defaultCardConfig()
    cfg.planetMode = planetMode
    cfg.themeStyle = themeStyle
    cfg.labelStyle = labelStyle
    cfg.overflowMode = overflowMode
    writeFormConfig(ctx, formId, cfg)
    this.pushFormUpdate(ctx, formId)
    const nextList: RunningWidgetEntry[] = []
    for (let i = 0; i < this.runningWidgets.length; i++) {
      const item = this.runningWidgets[i]
      if (item.formId === formId) {
        nextList.push({
          formId: item.formId,
          formName: item.formName,
          dimensionLabel: item.dimensionLabel,
          planetMode: planetMode,
          themeStyle: themeStyle,
          labelStyle: labelStyle,
          overflowMode: overflowMode
        })
      } else {
        nextList.push(item)
      }
    }
    this.runningWidgets = nextList
    this.statusNote = this.t('已实时应用到桌面小组件。', 'Applied to desktop widget.')
  }

  private saveGlobalDefaults(applyToExisting: boolean): void {
    const ctx = this.hostContext()
    if (ctx === undefined) return
    const cfg: CardInstanceConfig = defaultCardConfig()
    cfg.planetMode = this.globalPlanetMode
    cfg.themeStyle = this.globalThemeStyle
    cfg.labelStyle = this.globalLabelStyle
    cfg.overflowMode = this.globalOverflowMode
    writeGlobalWidgetConfig(ctx, cfg)
    if (applyToExisting) {
      const nextList: RunningWidgetEntry[] = []
      for (let i = 0; i < this.runningWidgets.length; i++) {
        const item = this.runningWidgets[i]
        writeFormConfig(ctx, item.formId, cfg)
        this.pushFormUpdate(ctx, item.formId)
        nextList.push({
          formId: item.formId,
          formName: item.formName,
          dimensionLabel: item.dimensionLabel,
          planetMode: cfg.planetMode,
          themeStyle: cfg.themeStyle,
          labelStyle: cfg.labelStyle,
          overflowMode: cfg.overflowMode
        })
      }
      this.runningWidgets = nextList
      this.statusNote = this.t('已将默认配置应用到全部桌面卡片。', 'Applied defaults to all widgets.')
    } else {
      this.statusNote = this.t('已保存新卡片默认配置。', 'Saved default widget settings.')
    }
    this.onFlashHint(this.statusNote)
  }

  private openAddWidgetPicker(formName?: string): void {
    const want: Want = {
      bundleName: 'com.joinother.skyinstrument',
      abilityName: 'SkyInstrumentFormAbility',
      parameters: formName !== undefined && formName.length > 0
        ? { 'ohos.extra.param.key.form_name': formName }
        : {}
    }
    try {
      formProvider.openFormManager(want)
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'openFormManager failed: %{public}s', String(err))
      this.onFlashHint(this.t('请在系统桌面双指捏合 → 服务卡片 → 搜索「星象仪」添加。',
        'Pinch home screen → Service Widgets → Search Sky Instrument.'))
    }
  }

  private planetLabel(id: string): string {
    if (id === 'follow') return this.t('跟随星图', 'Follow')
    return this.isZh() ? planetZhName(id) : id
  }

  @Builder
  private optionRow(
    label: string,
    options: StudioOption[],
    selected: string,
    onPick: (val: string) => void
  ) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(panelFontSize(11, this.readableUi))
        .fontColor(this.c.sub)
        .width('100%')
      Row({ space: 6 }) {
        ForEach(options, (opt: StudioOption) => {
          Text(this.isZh() ? opt.labelZh : opt.labelEn)
            .fontSize(panelFontSize(12, this.readableUi))
            .fontWeight(selected === opt.value ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(selected === opt.value ? this.c.onAccent : this.c.text)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(34)
            .backgroundColor(selected === opt.value ? this.c.accent : this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => onPick(opt.value))
        }, (opt: StudioOption) => opt.value + ':' + (selected === opt.value ? '1' : '0'))
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private planetGrid(selected: string, onPick: (planetId: string) => void) {
    Column({ space: 6 }) {
      Text(this.t('观测天体绑定', 'Bound Celestial World'))
        .fontSize(panelFontSize(11, this.readableUi))
        .fontColor(this.c.sub)
        .width('100%')
      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(6) } }) {
        ForEach(SUPPORTED_EDIT_PLANETS, (pid: string) => {
          Row({ space: 4 }) {
            Text(pid === 'follow' ? '✦' : (pid === 'Sun' ? '☉' : planetSymbol(pid)))
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(selected === pid ? this.c.onAccent : this.c.sub)
            Text(this.planetLabel(pid))
              .fontSize(panelFontSize(12, this.readableUi))
              .fontWeight(selected === pid ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(selected === pid ? this.c.onAccent : this.c.text)
          }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(selected === pid ? this.c.accent : this.c.bg)
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => onPick(pid))
        }, (pid: string) => pid + ':' + (selected === pid ? '1' : '0'))
      }.width('100%')
    }.width('100%')
  }

  build() {
    Column({ space: 12 }) {
      // 1. 顶部概览与快捷操作
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Row({ space: 4 }) {
              Text(this.t('桌面小组件工作台', 'Desktop Widget Studio'))
                .fontSize(panelFontSize(15, this.readableUi))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.text)
              InfoTipButton({
                title: this.t('桌面小组件说明', 'About Widgets'),
                tip: this.t('在此可精细调整每张已添加桌面卡片的观测天体、视觉风格、标注与破框动效，并独立设置小组件使用的地理区域。小组件预约的提醒与日历、通知双向同步。',
                  'Fine-tune each pinned desktop widget here: bound world, theme, labels, overflow effect, and independent geographic region. Reminders stay synced with calendar & notifications.')
              })
            }
            Text(this.t(
              `桌面已运行 ${this.runningWidgets.length} 张卡片 · 已同步 ${this.remindedCount} 条提醒`,
              `${this.runningWidgets.length} active widget(s) · ${this.remindedCount} synced reminder(s)`))
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(this.c.sub)
          }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
        }.width('100%')

        Row({ space: 8 }) {
          Button(this.t('＋ 添加到桌面', '+ Add Widget'), { type: ButtonType.Normal })
            .height(38).layoutWeight(1)
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.c.onAccent).backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.openAddWidgetPicker())
          Button(this.t('同步全部卡片', 'Sync All'), { type: ButtonType.Normal })
            .height(38).layoutWeight(1)
            .fontSize(panelFontSize(12, this.readableUi))
            .fontColor(this.c.text).backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              const ctx = this.hostContext()
              if (ctx !== undefined) this.pushAllRunningForms(ctx)
              this.onSyncAllWidgets()
              this.reloadStudioState()
              this.statusNote = this.t('已向全部桌面小组件推送最新天象与提醒状态。', 'Synced latest sky & reminder data to widgets.')
              this.onFlashHint(this.statusNote)
            })
        }.width('100%')

        Row({ space: 8 }) {
          Button(this.t('通知与提醒设置 ↗', 'Notifications ↗'), { type: ButtonType.Normal })
            .height(34).layoutWeight(1)
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.sub).backgroundColor(this.c.bg)
            .border({ width: 1, color: this.c.dividerSoft })
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => this.onOpenNotifications())
          Button(this.showGlobalDefaults ? this.t('收起全局默认 ▴', 'Hide Defaults ▴') : this.t('全局默认样式 ▾', 'Global Defaults ▾'),
            { type: ButtonType.Normal })
            .height(34).layoutWeight(1)
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.showGlobalDefaults ? this.c.onAccent : this.c.text)
            .backgroundColor(this.showGlobalDefaults ? this.c.accent : this.c.bg)
            .border({ width: 1, color: this.c.dividerSoft })
            .borderRadius(UI_RADIUS_CONTROL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.showGlobalDefaults = !this.showGlobalDefaults
              })
            })
        }.width('100%')
      }
        .width('100%')
        .padding(12)
        .backgroundColor(this.c.soft)
        .border({ width: 1, color: this.c.border })
        .borderRadius(UI_RADIUS_CARD)

      // 2. 小组件地理区域独立选择器（跟随星图位置 / 独立指定区域）
      RegionScopePicker({
        title: this.t('小组件地理区域', 'Widget Geographic Region'),
        regionId: this.widgetRegionId,
        followLocationName: this.followLocationName,
        language: this.language,
        onSelectRegion: (rid: string) => this.updateWidgetRegion(rid)
      })

      // 3. 全局默认配置抽屉
      if (this.showGlobalDefaults) {
        Column({ space: 10 }) {
          Text(this.t('全局默认样式（新卡片默认采用，也可一键覆盖现有卡片）', 'Global defaults for new or existing widgets'))
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.sub)
            .width('100%')
          this.planetGrid(this.globalPlanetMode, (pid: string) => { this.globalPlanetMode = pid })
          this.optionRow(this.t('视觉风格', 'Theme'), THEME_OPTIONS, this.globalThemeStyle, (v: string) => { this.globalThemeStyle = v })
          this.optionRow(this.t('行星标注', 'Planet Labels'), LABEL_OPTIONS, this.globalLabelStyle, (v: string) => { this.globalLabelStyle = v })
          this.optionRow(this.t('破框动效', 'Overflow Animation'), OVERFLOW_OPTIONS, this.globalOverflowMode, (v: string) => { this.globalOverflowMode = v })
          Row({ space: 8 }) {
            Button(this.t('保存为默认', 'Save Default'), { type: ButtonType.Normal })
              .height(36).layoutWeight(1)
              .fontSize(panelFontSize(12, this.readableUi))
              .fontColor(this.c.text).backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => this.saveGlobalDefaults(false))
            Button(this.t('应用到全部卡片', 'Apply to All'), { type: ButtonType.Normal })
              .height(36).layoutWeight(1)
              .fontSize(panelFontSize(12, this.readableUi))
              .fontColor(this.c.onAccent).backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => this.saveGlobalDefaults(true))
          }.width('100%')
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.soft)
          .border({ width: 1, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .transition(uiFadeUpTransition())
      }

      // 4. 已添加的桌面卡片逐张精细管理
      Column({ space: 8 }) {
        Row() {
          Text(this.t('已添加的桌面卡片（实时调节）', 'Active Desktop Widgets (Live Tuning)'))
            .fontSize(panelFontSize(13, this.readableUi))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.text)
            .layoutWeight(1)
          Text(this.t('刷新列表', 'Refresh'))
            .fontSize(panelFontSize(11, this.readableUi))
            .fontColor(this.c.accent)
            .padding({ left: 8, right: 4, top: 4, bottom: 4 })
            .onClick(() => this.reloadStudioState())
        }.width('100%')

        if (this.loading) {
          LoadingProgress().width(24).height(24).color(this.c.sub)
        } else if (this.runningWidgets.length === 0) {
          Column({ space: 8 }) {
            Text(this.t('桌面暂未检测到已添加的星象仪卡片。点击上方「添加到桌面」，或在桌面双指捏合添加服务卡片。',
              'No pinned Sky Instrument widgets detected yet. Tap Add Widget above or add from your home screen.'))
              .fontSize(panelFontSize(12, this.readableUi))
              .fontColor(this.c.sub)
              .lineHeight(panelFontSize(18, this.readableUi))
              .width('100%')
          }
            .width('100%')
            .padding(12)
            .backgroundColor(this.c.bg)
            .border({ width: 1, color: this.c.dividerSoft })
            .borderRadius(UI_RADIUS_CARD)
        } else {
          ForEach(this.runningWidgets, (item: RunningWidgetEntry) => {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Column()
                  .width(8).height(8).borderRadius(4)
                  .backgroundColor(this.c.isNight ? this.c.accent : catalogMetaFor(item.formName).accentHex)
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(this.isZh() ? catalogMetaFor(item.formName).titleZh : catalogMetaFor(item.formName).titleEn)
                      .fontSize(panelFontSize(13, this.readableUi))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.text)
                    Text(item.dimensionLabel)
                      .fontSize(panelFontSize(10, this.readableUi))
                      .fontColor(this.c.sub)
                      .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                      .backgroundColor(this.c.softStrong)
                      .borderRadius(UI_RADIUS_PILL)
                  }
                  Text(`${this.planetLabel(item.planetMode)} · ${item.themeStyle === 'deep' ? this.t('深空极简', 'Deep') : this.t('实时天穹', 'Sky')}`)
                    .fontSize(panelFontSize(11, this.readableUi))
                    .fontColor(this.c.sub)
                }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                Text(this.expandedFormId === item.formId ? this.t('收起 ▴', 'Hide') : this.t('调整 ▾', 'Tune'))
                  .fontSize(panelFontSize(11, this.readableUi))
                  .fontColor(this.expandedFormId === item.formId ? this.c.onAccent : this.c.text)
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .backgroundColor(this.expandedFormId === item.formId ? this.c.accent : this.c.softStrong)
                  .borderRadius(UI_RADIUS_PILL)
                  .onClick(() => {
                    this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                      this.expandedFormId = this.expandedFormId === item.formId ? '' : item.formId
                    })
                  })
              }.width('100%').alignItems(VerticalAlign.Center)

              if (this.expandedFormId === item.formId) {
                Column({ space: 10 }) {
                  if (catalogMetaFor(item.formName).supportsPlanet) {
                    this.planetGrid(item.planetMode, (pid: string) => {
                      this.updateSingleWidgetConfig(item.formId, pid, item.themeStyle, item.labelStyle, item.overflowMode)
                    })
                  }
                  if (catalogMetaFor(item.formName).supportsTheme) {
                    this.optionRow(this.t('视觉风格', 'Theme'), THEME_OPTIONS, item.themeStyle, (val: string) => {
                      this.updateSingleWidgetConfig(item.formId, item.planetMode, val, item.labelStyle, item.overflowMode)
                    })
                  }
                  if (catalogMetaFor(item.formName).supportsLabels) {
                    this.optionRow(this.t('行星标注', 'Planet Labels'), LABEL_OPTIONS, item.labelStyle, (val: string) => {
                      this.updateSingleWidgetConfig(item.formId, item.planetMode, item.themeStyle, val, item.overflowMode)
                    })
                  }
                  this.optionRow(this.t('破框动效', 'Overflow'), OVERFLOW_OPTIONS, item.overflowMode, (val: string) => {
                    this.updateSingleWidgetConfig(item.formId, item.planetMode, item.themeStyle, item.labelStyle, val)
                  })
                }
                  .width('100%')
                  .padding({ top: 4 })
                  .transition(uiFadeUpTransition())
              }
            }
              .width('100%')
              .padding(11)
              .backgroundColor(this.expandedFormId === item.formId ? this.c.soft : this.c.bg)
              .border({ width: 1, color: this.expandedFormId === item.formId ? this.c.border : this.c.dividerSoft })
              .borderRadius(UI_RADIUS_CARD)
          }, (item: RunningWidgetEntry) => `${item.formId}:${item.planetMode}:${item.themeStyle}:${item.labelStyle}:${item.overflowMode}:${this.expandedFormId === item.formId ? 1 : 0}`)
        }
      }.width('100%')

      // 5. 全部 8 款内置桌面小组件图鉴
      Column({ space: 8 }) {
        Text(this.t('全部内置桌面小组件（8 款）', 'Built-in Desktop Widgets (8)'))
          .fontSize(panelFontSize(13, this.readableUi))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
          .width('100%')

        ForEach(WIDGET_CATALOG, (meta: WidgetCatalogMeta) => {
          Row({ space: 10 }) {
            Column()
              .width(4).height(38).borderRadius(2)
              .backgroundColor(this.c.isNight ? this.c.accent : meta.accentHex)
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(this.isZh() ? meta.titleZh : meta.titleEn)
                  .fontSize(panelFontSize(13, this.readableUi))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.text)
                Text(meta.sizes)
                  .fontSize(panelFontSize(10, this.readableUi))
                  .fontColor(this.c.sub)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .backgroundColor(this.c.softStrong)
                  .borderRadius(UI_RADIUS_PILL)
                if (meta.supportsReminder) {
                  Text(this.t('可预约提醒', 'Reminders'))
                    .fontSize(panelFontSize(9.5, this.readableUi))
                    .fontColor(this.c.accent)
                    .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                    .backgroundColor(this.c.soft)
                    .borderRadius(UI_RADIUS_PILL)
                }
              }
              Text(this.isZh() ? meta.descZh : meta.descEn)
                .fontSize(panelFontSize(11, this.readableUi))
                .fontColor(this.c.sub)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

            Button(this.t('添加', 'Add'), { type: ButtonType.Normal })
              .height(30).padding({ left: 10, right: 10 })
              .fontSize(panelFontSize(11, this.readableUi))
              .fontColor(this.c.text).backgroundColor(this.c.softStrong)
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => this.openAddWidgetPicker(meta.formName))
          }
            .width('100%')
            .padding({ left: 10, right: 10, top: 9, bottom: 9 })
            .backgroundColor(this.c.bg)
            .border({ width: 1, color: this.c.dividerSoft })
            .borderRadius(UI_RADIUS_CARD)
            .alignItems(VerticalAlign.Center)
        }, (meta: WidgetCatalogMeta) => meta.formName + ':' + this.language)
      }.width('100%')

      if (this.statusNote.length > 0) {
        Text(this.statusNote)
          .fontSize(panelFontSize(11, this.readableUi))
          .fontColor(this.c.sub)
          .width('100%')
      }
    }
      .width('100%')
      .padding({ top: 4, bottom: 16 })
  }
}
