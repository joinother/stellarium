import { Theme } from '@kit.ArkUI'
import { panelFontSize } from '../../common/ui/UiTypography'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { WutTarget } from '../../pages/StellariumTypes'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 今晚观测目标卡片与它的指标贴片。
//
// 卡片只收目标对象本身；标题 / 副标题 / 类型名 / 数值 / 时刻文本都仍由宿主格式化，以回调注入
// （`fmtNum` / `fmtClock` / `wutTargetTitle` / `wutTargetSubtitle` / `zhType` 留在宿主，多处共用）。
// 类型缺失时走 `zhType('')` 的返回值，不补破折号。

@Component
export struct WutMetric {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop label: string
  @Prop value: string
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 4 }) {
      Text(this.label).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
      Text(this.value).fontSize(panelFontSize(13, this.readableUi)).fontColor(this.c.text).width('100%')
    }.width('48%').alignItems(HorizontalAlign.Start).margin({ bottom: 10 })
  }
}

@Component
export struct WutTargetCard {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @Prop target: WutTarget
  @State c: ThemeSlots = DEFAULT_SLOTS
  titleOf: (target: WutTarget) => string = () => ''
  subtitleOf: (target: WutTarget) => string = () => ''
  typeOf: (type: string) => string = () => ''
  numberText: (value: number | undefined, digits: number, unit: string) => string = () => ''
  clockText: (value: string | undefined) => string = () => ''
  onJump: (target: WutTarget) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 8 }) {
      Text(this.titleOf(this.target)).fontSize(panelFontSize(15, this.readableUi)).fontWeight(FontWeight.Medium)
        .fontColor(this.c.text).width('100%')
      if (this.subtitleOf(this.target).length > 0) {
        Text(this.subtitleOf(this.target)).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.sub).width('100%')
      }
      Text(this.typeOf(this.target.type ?? '')).fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        WutMetric({ label: I18n.t('ui_magnitude'), value: this.numberText(this.target.magnitude, 2, '') })
        WutMetric({ label: I18n.t('wut_max_altitude'), value: this.numberText(this.target.maxAltitude ?? this.target.altitude, 1, '\u00b0') })
        WutMetric({ label: I18n.t('tn_rise'), value: this.clockText(this.target.rise) })
        WutMetric({ label: I18n.t('tn_transit'), value: this.clockText(this.target.transit) })
        WutMetric({ label: I18n.t('tn_set'), value: this.clockText(this.target.set) })
        WutMetric({ label: I18n.t('ui_constellation'), value: this.target.constellation ?? '' })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
      .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 10 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onJump(this.target) })
  }
}
