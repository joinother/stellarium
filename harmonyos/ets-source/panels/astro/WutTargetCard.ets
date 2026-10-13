import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { WutTarget } from '../../pages/StellariumTypes'

// 今晚观测目标卡片与它的指标贴片。
//
// 卡片只收目标对象本身；标题 / 副标题 / 类型名 / 数值 / 时刻文本都仍由宿主格式化，以回调注入
// （`fmtNum` / `fmtClock` / `wutTargetTitle` / `wutTargetSubtitle` / `zhType` 留在宿主，多处共用）。
// 类型缺失时走 `zhType('')` 的返回值，不补破折号。

@Component
export struct WutMetric {
  @Prop label: string
  @Prop value: string
  @Prop labelColor: string
  @Prop valueColor: string

  build() {
    Column({ space: 4 }) {
      Text(this.label).fontSize(11).fontColor(this.labelColor).width('100%')
      Text(this.value).fontSize(13).fontColor(this.valueColor).width('100%')
    }.width('48%').alignItems(HorizontalAlign.Start).margin({ bottom: 10 })
  }
}

@Component
export struct WutTargetCard {
  @Prop target: WutTarget
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  titleOf: (target: WutTarget) => string = () => ''
  subtitleOf: (target: WutTarget) => string = () => ''
  typeOf: (type: string) => string = () => ''
  numberText: (value: number | undefined, digits: number, unit: string) => string = () => ''
  clockText: (value: string | undefined) => string = () => ''
  onJump: (target: WutTarget) => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(this.titleOf(this.target)).fontSize(15).fontWeight(FontWeight.Medium)
        .fontColor(this.textColor).width('100%')
      if (this.subtitleOf(this.target).length > 0) {
        Text(this.subtitleOf(this.target)).fontSize(11).fontColor(this.subColor).width('100%')
      }
      Text(this.typeOf(this.target.type ?? '')).fontSize(12).fontColor(this.subColor).width('100%')
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        WutMetric({ label: I18n.t('ui_magnitude'), value: this.numberText(this.target.magnitude, 2, ''), labelColor: this.subColor, valueColor: this.textColor })
        WutMetric({ label: I18n.t('wut_max_altitude'), value: this.numberText(this.target.maxAltitude ?? this.target.altitude, 1, '\u00b0'), labelColor: this.subColor, valueColor: this.textColor })
        WutMetric({ label: I18n.t('tn_rise'), value: this.clockText(this.target.rise), labelColor: this.subColor, valueColor: this.textColor })
        WutMetric({ label: I18n.t('tn_transit'), value: this.clockText(this.target.transit), labelColor: this.subColor, valueColor: this.textColor })
        WutMetric({ label: I18n.t('tn_set'), value: this.clockText(this.target.set), labelColor: this.subColor, valueColor: this.textColor })
        WutMetric({ label: I18n.t('ui_constellation'), value: this.target.constellation ?? '', labelColor: this.subColor, valueColor: this.textColor })
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding(12)
      .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 10 })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onJump(this.target) })
  }
}
