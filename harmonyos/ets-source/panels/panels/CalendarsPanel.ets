// 世界多历法对照面板（Calendars 插件原生鸿蒙界面）。
// 支持公历、儒略历、中国农历干支、藏历、伊斯兰历、希伯来历、波斯历、印度历、玛雅历等 18 种历法实时互转与历史日期跳转。
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { CalendarsStore } from '../../state/CalendarsStore'
import { CalendarRowItem } from '../../common/types/StellariumTypes'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

interface CalendarCategoryTab {
  id: string
  label: string
}

interface HistoricEpochPreset {
  id: string
  label: string
  mode: string
  year: number
  month: number
  day: number
}

const CALENDAR_CATEGORIES: CalendarCategoryTab[] = [
  { id: 'all', label: '全部' },
  { id: 'common', label: '常用' },
  { id: 'east_asia', label: '东亚' },
  { id: 'abrahamic', label: '西亚/南亚' },
  { id: 'ancient', label: '古文明' }
]

const HISTORIC_EPOCHS: HistoricEpochPreset[] = [
  { id: 'greg_reform', label: '格里历首日 1582-10-15', mode: 'gregorian', year: 1582, month: 10, day: 15 },
  { id: 'julian_last', label: '儒略历终日 1582-10-04', mode: 'julian', year: 1582, month: 10, day: 4 },
  { id: 'j2000', label: 'J2000 历元 2000-01-01', mode: 'gregorian', year: 2000, month: 1, day: 1 },
  { id: 'song_sn1054', label: '宋至和客星 1054-07-04', mode: 'julian', year: 1054, month: 7, day: 4 }
]

@Component
export struct CalendarsPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: CalendarsStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private jumpExpanded: boolean = false
  @State private jumpMode: string = 'gregorian'
  @State private jumpYearText: string = String(new Date().getFullYear())
  @State private jumpMonthText: string = String(new Date().getMonth() + 1)
  @State private jumpDayText: string = String(new Date().getDate())

  onChooseGregorianDate: (onAccept: (y: number, m: number, d: number) => void) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private filteredItems(): CalendarRowItem[] {
    if (this.store.selectedCategory === 'all') return this.store.items
    return this.store.items.filter((item: CalendarRowItem) => item.category === this.store.selectedCategory)
  }

  private formatLocalClock(iso: string): string {
    if (!iso || iso.length < 16) return iso || '--'
    return iso.replace('T', ' ').slice(0, 19)
  }

  private submitCustomJump(): void {
    const y = parseInt(this.jumpYearText.trim(), 10)
    const m = parseInt(this.jumpMonthText.trim(), 10)
    const d = parseInt(this.jumpDayText.trim(), 10)
    if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return
    this.store.jumpToCalendarDate(this.jumpMode, y, Math.max(1, Math.min(12, m)), Math.max(1, Math.min(31, d)))
  }

  build() {
    Column({ space: 10 }) {
      // 顶部标题与刷新
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text('世界多历法对照')
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong)
            InfoTipButton({
              title: '世界多历法引擎',
              tip: '由 Stellarium 原生 Calendars 插件离线驱动，按当前星图儒略日实时换算公历、儒略历、中国农历干支、藏历、伊斯兰历、希伯来历、波斯历、印度历与玛雅历等 18 种历法，并支持历史日期精准跳转。'
            })
          }.alignItems(VerticalAlign.Center)
          Text(this.store.localTime.length > 0
            ? ('星图时刻 ' + this.formatLocalClock(this.store.localTime))
            : '与当前星图时间实时同步')
            .fontSize(this.fs(11))
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('刷新')
          .id('calendars-refresh-btn')
          .fontSize(this.fs(12))
          .fontColor(this.c.text)
          .backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(34) })
          .padding({ left: 12, right: 12 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.store.load() })
      }.width('100%').alignItems(VerticalAlign.Center)

      // 天文历元摘要卡 + 屏幕叠加开关
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('儒略日 JD').fontSize(this.fs(10)).fontColor(this.c.sub)
            Text(this.store.jd > 0 ? this.store.jd.toFixed(2) : '--')
              .fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Column({ space: 2 }) {
            Text('简约儒略日 MJD').fontSize(this.fs(10)).fontColor(this.c.sub)
            Text(this.store.jd > 0 ? this.store.mjd.toFixed(2) : '--')
              .fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.text)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Column({ space: 2 }) {
            Text('Rata Die').fontSize(this.fs(10)).fontColor(this.c.sub)
            Text(this.store.jd > 0 ? String(Math.round(this.store.rataDie)) : '--')
              .fontSize(this.fs(12)).fontWeight(FontWeight.Medium).fontColor(this.c.text)
              .maxLines(1)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }.width('100%')

        Row().width('100%').height(0.5).backgroundColor(this.c.border)

        Row({ space: 8 }) {
          Text('星图画面右下角叠加历法')
            .fontSize(this.fs(12.5))
            .fontColor(this.c.text)
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.store.overlayEnabled })
            .id('calendars-overlay-toggle')
            .selectedColor(this.c.accent)
            .onChange((isOn: boolean) => {
              if (isOn !== this.store.overlayEnabled) {
                this.store.setOverlayEnabled(isOn)
              }
            })
        }.width('100%').constraintSize({ minHeight: this.ch(36) }).alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.c.bg)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)

      // 历史/指定日期历法跳转区（可折叠）
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text('日期换算与跳转')
            .fontSize(this.fs(12.5))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
            .maxLines(1)
            .layoutWeight(1)
          Button('回到现在')
            .fontSize(this.fs(11))
            .fontColor(this.c.accent)
            .backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_PILL)
            .constraintSize({ minHeight: this.ch(30) })
            .padding({ left: 10, right: 10 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.store.jumpToNow() })
          Text(this.jumpExpanded ? '收起 ▴' : '展开 ▾')
            .fontSize(this.fs(11))
            .fontColor(this.c.accent)
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.jumpExpanded = !this.jumpExpanded
              })
            })
        }.width('100%').alignItems(VerticalAlign.Center)

        if (this.jumpExpanded) {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              ForEach(['gregorian', 'julian'], (mode: string) => {
                Text(mode === 'gregorian' ? '公历 (Gregorian)' : '儒略历 (Julian)')
                  .fontSize(this.fs(11.5))
                  .fontWeight(this.jumpMode === mode ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.jumpMode === mode ? this.c.onAccent : this.c.sub)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .constraintSize({ minHeight: this.ch(34) })
                  .padding({ top: 6, bottom: 6 })
                  .backgroundColor(this.jumpMode === mode ? this.c.accent : this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.jumpMode = mode })
              }, (mode: string) => mode)
            }.width('100%')

            Row({ space: 6 }) {
              TextInput({ text: this.jumpYearText, placeholder: '年' })
                .type(InputType.Normal)
                .fontSize(this.fs(12))
                .fontColor(this.c.text)
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(36) })
                .layoutWeight(2)
                .onChange((val: string) => { this.jumpYearText = val })
              TextInput({ text: this.jumpMonthText, placeholder: '月' })
                .type(InputType.Number)
                .fontSize(this.fs(12))
                .fontColor(this.c.text)
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(36) })
                .layoutWeight(1)
                .onChange((val: string) => { this.jumpMonthText = val })
              TextInput({ text: this.jumpDayText, placeholder: '日' })
                .type(InputType.Number)
                .fontSize(this.fs(12))
                .fontColor(this.c.text)
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(36) })
                .layoutWeight(1)
                .onChange((val: string) => { this.jumpDayText = val })
              Button('跳转')
                .fontSize(this.fs(12))
                .fontColor(this.c.onAccent)
                .backgroundColor(this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(36) })
                .padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.submitCustomJump() })
            }.width('100%')

            if (this.jumpMode === 'gregorian') {
              Button('使用系统日期选择器')
                .fontSize(this.fs(11.5))
                .fontColor(this.c.text)
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(34) })
                .width('100%')
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => {
                  this.onChooseGregorianDate((y: number, m: number, d: number) => {
                    this.jumpYearText = String(y)
                    this.jumpMonthText = String(m)
                    this.jumpDayText = String(d)
                    this.store.jumpToCalendarDate('gregorian', y, m, d)
                  })
                })
            }

            Text('经典天文历史节点').fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(HISTORIC_EPOCHS, (preset: HistoricEpochPreset) => {
                Text(preset.label)
                  .fontSize(this.fs(10.5))
                  .fontColor(this.c.text)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .margin({ right: 6, bottom: 6 })
                  .backgroundColor(this.c.soft)
                  .border({ width: 0.5, color: this.c.border })
                  .borderRadius(UI_RADIUS_PILL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => {
                    this.jumpMode = preset.mode
                    this.jumpYearText = String(preset.year)
                    this.jumpMonthText = String(preset.month)
                    this.jumpDayText = String(preset.day)
                    this.store.jumpToCalendarDate(preset.mode, preset.year, preset.month, preset.day)
                  })
              }, (preset: HistoricEpochPreset) => preset.id)
            }.width('100%')
          }
          .width('100%')
          .transition(uiFadeUpTransition())
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.c.bg)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)

      // 历法分类筛选条
      Scroll() {
        Row({ space: 6 }) {
          ForEach(CALENDAR_CATEGORIES, (tab: CalendarCategoryTab) => {
            Text(tab.label)
              .id('calendars-cat-' + tab.id)
              .fontSize(this.fs(11.5))
              .fontWeight(this.store.selectedCategory === tab.id ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.store.selectedCategory === tab.id ? this.c.onAccent : this.c.sub)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .backgroundColor(this.store.selectedCategory === tab.id ? this.c.accent : this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.store.selectedCategory = tab.id })
          }, (tab: CalendarCategoryTab) => tab.id)
        }.padding({ left: 1, right: 2 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

      if (this.store.loading && this.store.items.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(this.c.accent)
          Text('正在换算世界多历法…').fontSize(this.fs(12)).fontColor(this.c.sub)
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 18, bottom: 18 })
      } else if (this.store.error.length > 0) {
        Text(this.store.error).fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').padding(12)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
      } else {
        Column({ space: 8 }) {
          ForEach(this.filteredItems(), (item: CalendarRowItem) => {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text(item.nameZh)
                  .fontSize(this.fs(13))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.textStrong)
                  .layoutWeight(1)
                Text(item.nameEn)
                  .fontSize(this.fs(10.5))
                  .fontColor(this.c.sub)
              }.width('100%')
              Text(item.formatted.length > 0 ? item.formatted : '--')
                .fontSize(this.fs(12.5))
                .fontColor(this.c.accent)
                .width('100%')
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c.bg)
            .border({ width: 0.5, color: this.c.border })
            .borderRadius(UI_RADIUS_CARD)
          }, (item: CalendarRowItem) => item.id)
        }.width('100%')
      }
    }
    .width('100%')
    .padding({ bottom: 12 })
  }
}
