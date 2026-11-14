import { Theme } from '@kit.ArkUI'
import { TimeWheelStore } from '../../state/TimeWheelStore'
import { TimeWheelCanvas } from './TimeWheelCanvas'
import { UI_RADIUS_PILL, UI_RADIUS_SHEET } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间转轴 + 时间轮：顶部日期时间字段行 + 下方可拖动的刻度轮。
//
// 只负责"显示与把触摸事件转交宿主"：所有拖动/惯性/过渡/引擎同步逻辑仍在宿主，
// 由 onTouch / onSelectUnit 回调驱动。字段与刻度数值直接读 store，
// 因此随时间与拖动实时刷新（不经过任何参数化 @Builder——其简单类型参数按值捕获会冻结）。
//
// 主题色走「机制四」：@State c: ThemeSlots via onWillApplyTheme，随夜间开关自动刷新。
@Component
export struct TimeWheelScrubber {
  @ObjectLink store: TimeWheelStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSelectUnit: (unit: string) => void = () => {}
  onWheelTouch: (event: TouchEvent) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 8 }) {
      // 顶部字段即视频中的日期时间条：先点字段，再用下方单一转轴调节。
      Row({ space: 1 }) {
        Button() {
          Row() {
            Text(this.store.timeWheelYear.toString()).maxLines(1).minFontSize(10)
              .fontSize(this.store.timeWheelUnit === 'year' ? 14 : 12)
              .fontWeight(this.store.timeWheelUnit === 'year' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.store.timeWheelUnit === 'year' ? this.c.textStrong : this.c.chipInactiveText)
          }.justifyContent(FlexAlign.Center).width('100%')
        }
          .width(47).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'year' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => { this.onSelectUnit('year') })
        Button() {
          Text(this.store.timeWheelMonth.toString().padStart(2, '0') + '月').maxLines(1).minFontSize(10)
            .fontSize(this.store.timeWheelUnit === 'month' ? 14 : 12)
            .fontWeight(this.store.timeWheelUnit === 'month' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeWheelUnit === 'month' ? this.c.textStrong : this.c.chipInactiveText).textAlign(TextAlign.Center).width('100%')
        }
          .width(34).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'month' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL).onClick(() => { this.onSelectUnit('month') })
        Button() {
          Text(this.store.timeWheelDay.toString().padStart(2, '0') + '日').maxLines(1).minFontSize(10)
            .fontSize(this.store.timeWheelUnit === 'day' ? 14 : 12)
            .fontWeight(this.store.timeWheelUnit === 'day' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeWheelUnit === 'day' ? this.c.textStrong : this.c.chipInactiveText).textAlign(TextAlign.Center).width('100%')
        }
          .width(34).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'day' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL).onClick(() => { this.onSelectUnit('day') })
        Button() {
          Text(this.store.timeWheelHour.toString().padStart(2, '0') + ':').maxLines(1).minFontSize(10)
            .fontSize(this.store.timeWheelUnit === 'hour' ? 14 : 12)
            .fontWeight(this.store.timeWheelUnit === 'hour' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeWheelUnit === 'hour' ? this.c.textStrong : this.c.chipInactiveText).textAlign(TextAlign.Center).width('100%')
        }
          .width(30).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'hour' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL).onClick(() => { this.onSelectUnit('hour') })
        Button() {
          Text(this.store.timeWheelMinute.toString().padStart(2, '0') + ':').maxLines(1).minFontSize(10)
            .fontSize(this.store.timeWheelUnit === 'minute' ? 14 : 12)
            .fontWeight(this.store.timeWheelUnit === 'minute' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeWheelUnit === 'minute' ? this.c.textStrong : this.c.chipInactiveText).textAlign(TextAlign.Center).width('100%')
        }
          .width(30).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'minute' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL).onClick(() => { this.onSelectUnit('minute') })
        Button() {
          Text(this.store.timeWheelSecond.toString().padStart(2, '0')).maxLines(1).minFontSize(10)
            .fontSize(this.store.timeWheelUnit === 'second' ? 14 : 12)
            .fontWeight(this.store.timeWheelUnit === 'second' ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeWheelUnit === 'second' ? this.c.textStrong : this.c.chipInactiveText).textAlign(TextAlign.Center).width('100%')
        }
          .width(26).height(32).padding({ left: 1, right: 1 })
          .backgroundColor(this.store.timeWheelUnit === 'second' ? this.c.chipActiveBg : Color.Transparent)
          .borderRadius(UI_RADIUS_PILL).onClick(() => { this.onSelectUnit('second') })
      }
      .width('100%').height(40).justifyContent(FlexAlign.Center).padding({ left: 4, right: 4 })
      .backgroundColor(this.c.overlayScrim)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_PILL)

      Stack({ alignContent: Alignment.Center }) {
        TimeWheelCanvas({
          store: this.store,
          onWheelTouch: (event: TouchEvent) => { this.onWheelTouch(event) }
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height(56)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.c.overlayScrim)
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_SHEET)
      .clip(true)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 8 })
  }
}
