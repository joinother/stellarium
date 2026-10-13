import { curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { TimeStore } from '../../state/TimeStore'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 时间速度控制按钮：倒带 / 停止·继续 / 实时 / 减速 / 快进。
// 当前档位高亮，点击后速度显示立即更新。
//
// chip 内容全部内联、直接读 store，不走带参数的 @Builder ——
// 参数化 @Builder 的简单类型参数按值捕获、首帧后即冻结，会导致标签 / 高亮要重开面板才更新。
@Component
export struct TimeSpeedChips {
  @ObjectLink store: TimeStore
  onChip: (id: string) => void = () => {}

  build() {
    Scroll() {
      Row({ space: 5 }) {
        // 倒带 — 单按钮循环升档：-1x → -2x → -10x → -1分/秒 → -1时/秒 → -10天/秒 → 回到-1x
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_rewind'))
            .width(14).height(14)
            .fillColor(this.store.timeSpeedIndex < 6 ? '#FFFFFF' : '#7FB3DC')
          Text(I18n.t('s0763_rewind'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex < 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex < 6 ? '#FFFFFF' : '#B8D4EF')
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex < 6 ? 'rgba(79, 148, 211, 0.55)' : 'rgba(107, 163, 214, 0.15)')
          .border({ width: this.store.timeSpeedIndex < 6 ? 1.2 : 0.6, color: this.store.timeSpeedIndex < 6 ? 'rgba(127, 179, 220, 0.7)' : 'rgba(127, 179, 220, 0.22)' })
          .shadow(this.store.timeSpeedIndex < 6 ? { radius: 10, color: 'rgba(49, 120, 200, 0.25)', offsetX: 0, offsetY: 3 } : { radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('rewind') })

        // 停止/继续 — 停止后同一按钮变成继续，避免“停止”和播放状态混淆
        Row({ space: 4 }) {
          Image($r('app.media.' + (this.store.timeSpeedIndex === 6 ? 'ic_time_resume' : 'ic_time_stop')))
            .width(14).height(14)
            .fillColor(this.store.timeSpeedIndex === 6 ? '#FFFFFF' : '#7FB3DC')
          Text(this.store.timeSpeedIndex === 6 ? I18n.t('btn_resume') : I18n.t('s0761_stop'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex === 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex === 6 ? '#FFFFFF' : '#B8D4EF')
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex === 6 ? 'rgba(79, 148, 211, 0.55)' : 'rgba(107, 163, 214, 0.15)')
          .border({ width: this.store.timeSpeedIndex === 6 ? 1.2 : 0.6, color: this.store.timeSpeedIndex === 6 ? 'rgba(127, 179, 220, 0.7)' : 'rgba(127, 179, 220, 0.22)' })
          .shadow(this.store.timeSpeedIndex === 6 ? { radius: 10, color: 'rgba(49, 120, 200, 0.25)', offsetX: 0, offsetY: 3 } : { radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('stop') })

        // 实时 — 回到当前时刻 + 1x
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_realtime')).width(14).height(14)
            .fillColor(this.store.timeSpeedIndex === 7 ? '#FFFFFF' : '#7FB3DC')
          Text(I18n.t('s0764_realtime')).fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex === 7 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex === 7 ? '#FFFFFF' : '#B8D4EF')
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex === 7 ? 'rgba(79, 148, 211, 0.55)' : 'rgba(107, 163, 214, 0.15)')
          .border({ width: this.store.timeSpeedIndex === 7 ? 1.2 : 0.6, color: this.store.timeSpeedIndex === 7 ? 'rgba(127, 179, 220, 0.7)' : 'rgba(127, 179, 220, 0.22)' })
          .shadow(this.store.timeSpeedIndex === 7 ? { radius: 10, color: 'rgba(49, 120, 200, 0.25)', offsetX: 0, offsetY: 3 } : { radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('realtime') })

        // 减速 — 每点降一档；降到1x再点=停止
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_slower')).width(14).height(14).fillColor('#7FB3DC')
          Text(I18n.t('s0759_slower'))
            .fontSize(11.5).fontColor('#B8D4EF')
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor('rgba(107, 163, 214, 0.15)')
          .border({ width: 0.6, color: 'rgba(127, 179, 220, 0.22)' })
          .shadow({ radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('slower') })

        // 快进 — 单按钮循环升档：1x → 2x → 10x → 1分/秒 → 1时/秒 → 1天/秒 → 10天/秒 → 回到1x
        // 激活时标签直接显示当前档位速度
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_fast')).width(14).height(14)
            .fillColor(this.store.timeSpeedIndex > 7 ? '#FFFFFF' : '#7FB3DC')
          Text(I18n.t('s0765_fast'))
            .fontSize(11.5)
            .fontWeight(this.store.timeSpeedIndex > 7 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex > 7 ? '#FFFFFF' : '#B8D4EF')
        }.height(32).padding({ left: 7, right: 7 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.store.timeSpeedIndex > 7 ? 'rgba(79, 148, 211, 0.55)' : 'rgba(107, 163, 214, 0.15)')
          .border({ width: this.store.timeSpeedIndex > 7 ? 1.2 : 0.6, color: this.store.timeSpeedIndex > 7 ? 'rgba(127, 179, 220, 0.7)' : 'rgba(127, 179, 220, 0.22)' })
          .shadow(this.store.timeSpeedIndex > 7 ? { radius: 10, color: 'rgba(49, 120, 200, 0.25)', offsetX: 0, offsetY: 3 } : { radius: 8, color: 'rgba(0, 0, 0, 0.12)', offsetX: 0, offsetY: 4 })
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
