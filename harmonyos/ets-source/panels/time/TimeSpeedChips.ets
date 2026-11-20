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
    Column({ space: 8 }) {
      // 第一层主控（等宽铺满 38vp 大按钮）：最常用的「暂停/继续」与「回到实时」居于视觉焦点，左右配「倒带 / 快进」
      Row({ space: 6 }) {
        // 倒带
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_rewind'))
            .width(15).height(15)
            .fillColor(this.store.timeSpeedIndex < 6 ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0763_rewind'))
            .fontSize(12)
            .fontWeight(this.store.timeSpeedIndex < 6 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex < 6 ? this.c.textStrong : this.c.chipInactiveText)
            .maxLines(1)
        }
        .layoutWeight(1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
        .backgroundColor(this.store.timeSpeedIndex < 6 ? this.c.chipActiveBg : this.c.chipInactiveBg)
        .border({ width: this.store.timeSpeedIndex < 6 ? 1.2 : 0.6, color: this.store.timeSpeedIndex < 6 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
        .onClick(() => { this.onChip('rewind') })

        // 停止/继续（核心主按钮）
        Row({ space: 4 }) {
          Image($r('app.media.' + (this.store.timeSpeedIndex === 6 ? 'ic_time_resume' : 'ic_time_stop')))
            .width(15).height(15)
            .fillColor(this.store.timeSpeedIndex === 6 ? this.c.textStrong : this.c.text)
          Text(this.store.timeSpeedIndex === 6 ? I18n.t('btn_resume') : I18n.t('s0761_stop'))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.timeSpeedIndex === 6 ? this.c.textStrong : this.c.text)
            .maxLines(1)
        }
        .layoutWeight(1.15).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
        .backgroundColor(this.store.timeSpeedIndex === 6 ? this.c.chipActiveBg : this.c.softStrong)
        .border({ width: this.store.timeSpeedIndex === 6 ? 1.3 : 0.8, color: this.store.timeSpeedIndex === 6 ? this.c.chipActiveBorder : this.c.border })
        .shadow(this.store.timeSpeedIndex === 6 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 6, color: this.c.shadowSoft, offsetX: 0, offsetY: 2 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
        .onClick(() => { this.onChip('stop') })

        // 实时（核心主按钮）
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_realtime')).width(15).height(15)
            .fillColor(this.store.timeSpeedIndex === 7 ? this.c.textStrong : this.c.text)
          Text(I18n.t('s0764_realtime'))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.store.timeSpeedIndex === 7 ? this.c.textStrong : this.c.text)
            .maxLines(1)
        }
        .layoutWeight(1.15).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
        .backgroundColor(this.store.timeSpeedIndex === 7 ? this.c.chipActiveBg : this.c.softStrong)
        .border({ width: this.store.timeSpeedIndex === 7 ? 1.3 : 0.8, color: this.store.timeSpeedIndex === 7 ? this.c.chipActiveBorder : this.c.border })
        .shadow(this.store.timeSpeedIndex === 7 ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 6, color: this.c.shadowSoft, offsetX: 0, offsetY: 2 })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
        .onClick(() => { this.onChip('realtime') })

        // 快进
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_fast')).width(15).height(15)
            .fillColor(this.store.timeSpeedIndex > 7 ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0765_fast'))
            .fontSize(12)
            .fontWeight(this.store.timeSpeedIndex > 7 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.store.timeSpeedIndex > 7 ? this.c.textStrong : this.c.chipInactiveText)
            .maxLines(1)
        }
        .layoutWeight(1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
        .backgroundColor(this.store.timeSpeedIndex > 7 ? this.c.chipActiveBg : this.c.chipInactiveBg)
        .border({ width: this.store.timeSpeedIndex > 7 ? 1.2 : 0.6, color: this.store.timeSpeedIndex > 7 ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
        .onClick(() => { this.onChip('fast') })
      }
      .width('100%')

      // 第二层次级微调：仅在快进/倒带状态下出现「逐档降速」，实时/停止态不占用界面空间
      if (this.store.timeSpeedIndex !== 6 && this.store.timeSpeedIndex !== 7) {
        Row({ space: 8 }) {
          Row({ space: 5 }) {
            Image($r('app.media.ic_time_slower')).width(14).height(14).fillColor(this.c.iconSecondary)
            Text(I18n.t('s0759_slower') + '（逐档降速）')
              .fontSize(11.5).fontColor(this.c.sub).maxLines(1)
          }
          .height(34).padding({ left: 12, right: 14 }).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.c.chipInactiveBg)
          .border({ width: 0.6, color: this.c.chipInactiveBorder })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onChip('slower') })
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 8, bottom: 2 })
  }
}
