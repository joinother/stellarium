import { Theme, curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { TimeStore } from '../../state/TimeStore'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间速度控制按钮：倒带 / 停止·继续 / 实时 / 减速 / 快进。
// 当前档位高亮，点击后速度显示立即更新。
//
// chip 内容全部内联、直接读 store，不走带参数的 @Builder ——
// 参数化 @Builder 的简单类型参数按值捕获、首帧后即冻结，会导致标签 / 高亮要重开面板才更新。
//
// 主题色走「机制四」：@State c: ThemeSlots via onWillApplyTheme，随夜间开关自动刷新。
@Component
export struct TimeSpeedChips {
  @ObjectLink store: TimeStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onChip: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Scroll() {
      Row({ space: 5 }) {
        // 倒带 — 单按钮循环升档：-1x → -2x → -10x → -1分/秒 → -1时/秒 → -10天/秒 → 回到-1x
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_rewind'))
            .width(14).height(14)
            .fillColor(this.store.timeSpeedIndex < 6 ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0763_rewind'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex < 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex < 6 ? this.c.textStrong : this.c.chipInactiveText)
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex < 6 ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.store.timeSpeedIndex < 6 ? 1.2 : 0.6, color: this.store.timeSpeedIndex < 6 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .shadow(this.store.timeSpeedIndex < 6 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 8, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('rewind') })

        // 停止/继续 — 停止后同一按钮变成继续，避免"停止"和播放状态混淆
        Row({ space: 4 }) {
          Image($r('app.media.' + (this.store.timeSpeedIndex === 6 ? 'ic_time_resume' : 'ic_time_stop')))
            .width(14).height(14)
            .fillColor(this.store.timeSpeedIndex === 6 ? this.c.textStrong : this.c.iconTertiary)
          Text(this.store.timeSpeedIndex === 6 ? I18n.t('btn_resume') : I18n.t('s0761_stop'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex === 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex === 6 ? this.c.textStrong : this.c.chipInactiveText)
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex === 6 ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.store.timeSpeedIndex === 6 ? 1.2 : 0.6, color: this.store.timeSpeedIndex === 6 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .shadow(this.store.timeSpeedIndex === 6 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 8, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('stop') })

        // 实时 — 回到当前时刻 + 1x
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_realtime')).width(14).height(14)
            .fillColor(this.store.timeSpeedIndex === 7 ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0764_realtime')).fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex === 7 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex === 7 ? this.c.textStrong : this.c.chipInactiveText)
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex === 7 ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.store.timeSpeedIndex === 7 ? 1.2 : 0.6, color: this.store.timeSpeedIndex === 7 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .shadow(this.store.timeSpeedIndex === 7 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 8, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('realtime') })

        // 减速 — 每点降一档；降到1x再点=停止
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_slower')).width(14).height(14).fillColor(this.c.iconTertiary)
          Text(I18n.t('s0759_slower'))
            .fontSize(11.5).fontColor(this.c.chipInactiveText)
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.c.chipInactiveBg)
          .border({ width: 0.6, color: this.c.chipInactiveBorder })
          .shadow({ radius: 8, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('slower') })

        // 快进 — 单按钮循环升档：1x → 2x → 10x → 1分/秒 → 1时/秒 → 1天/秒 → 10天/秒 → 回到1x
        // 激活时标签直接显示当前档位速度
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_fast')).width(14).height(14)
            .fillColor(this.store.timeSpeedIndex > 7 ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0765_fast'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex > 7 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex > 7 ? this.c.textStrong : this.c.chipInactiveText)
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex > 7 ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.store.timeSpeedIndex > 7 ? 1.2 : 0.6, color: this.store.timeSpeedIndex > 7 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .shadow(this.store.timeSpeedIndex > 7 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 8, color: this.c.shadowSoft, offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('fast') })
      }
      .padding({ left: 2, right: 10 })
    }
      .width('100%')
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .margin({ top: 8 })
  }
}
