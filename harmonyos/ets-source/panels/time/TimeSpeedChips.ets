import { Theme, curves } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import {
  TimeStore,
  TIME_SPEED_IDX_STOP,
  TIME_SPEED_IDX_REALTIME
} from '../../state/TimeStore'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 时间速度控制区：顶部固定高度实时速率状态条（带就地降速胶囊，不跳动布局）+
// 下方 4 枚等宽主控（倒退 / 暂停·继续 / 实时 / 快进）。
// 主题色走「机制四」：@State c: ThemeSlots via onWillApplyTheme，随夜间开关自动刷新。
@Component
export struct TimeSpeedChips {
  @ObjectLink store: TimeStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onChip: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private isRewinding(): boolean {
    return this.store.timeSpeedIndex < TIME_SPEED_IDX_STOP
  }

  private isPaused(): boolean {
    return this.store.timeSpeedIndex === TIME_SPEED_IDX_STOP
  }

  private isRealtime(): boolean {
    return this.store.timeSpeedIndex === TIME_SPEED_IDX_REALTIME
  }

  private isFastForwarding(): boolean {
    return this.store.timeSpeedIndex > TIME_SPEED_IDX_REALTIME
  }

  private statusDotColor(): ResourceColor {
    if (this.isPaused()) return this.c.warning
    if (this.isRealtime()) return this.c.success
    return this.c.accent
  }

  private statusRateSummary(): string {
    if (this.isPaused()) return I18n.t('msg_paused')
    if (this.isRealtime()) return I18n.t('s0764_realtime') + ' · 1x'
    if (this.isRewinding()) return I18n.t('s0763_rewind') + ' · ' + this.store.timeRateText
    return I18n.t('s0765_fast') + ' · ' + this.store.timeRateText
  }

  build() {
    Column({ space: 7 }) {
      // 固定高度实时速率条：一眼看清当前速度档位；快进/倒退态右侧就地出现「降速」，避免增删整行导致界面跳动
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          Circle({ width: 6, height: 6 })
            .fill(this.statusDotColor())
          Text(this.statusRateSummary())
            .fontSize(11.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isPaused() ? this.c.sub : this.c.textStrong)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
          .alignItems(VerticalAlign.Center)
          .layoutWeight(1)

        if (this.isFastForwarding() || this.isRewinding()) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_time_slower'))
              .width(12).height(12)
              .fillColor(this.c.accent)
            Text(I18n.t('s0759_slower'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.accent)
              .maxLines(1)
          }
            .height(24)
            .padding({ left: 9, right: 10 })
            .backgroundColor(this.c.softStrong)
            .border({ width: 0.6, color: this.c.chipActiveBorder })
            .borderRadius(UI_RADIUS_PILL)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onChip('slower') })
        } else {
          Text('1分 · 10分 · 1时 · 1天/秒')
            .fontSize(10)
            .fontColor(this.c.tertiary)
            .maxLines(1)
        }
      }
        .width('100%')
        .height(26)
        .padding({ left: 10, right: 6 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.c.overlayScrim)
        .border({ width: 0.6, color: this.c.dividerSoft })
        .borderRadius(UI_RADIUS_PILL)

      // 4 枚等宽核心速率键：倒退 / 暂停·继续 / 实时 / 快进
      Row({ space: 6 }) {
        // 倒退（快进中点一次即降速，实时/暂停点一次即 -10分/秒 清晰倒流）
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_rewind'))
            .width(15).height(15)
            .fillColor(this.isRewinding() ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0763_rewind'))
            .fontSize(12)
            .fontWeight(this.isRewinding() ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isRewinding() ? this.c.textStrong : this.c.chipInactiveText)
            .maxLines(1)
        }
          .layoutWeight(1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.isRewinding() ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.isRewinding() ? 1.2 : 0.6, color: this.isRewinding() ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('rewind') })

        // 暂停 / 继续
        Row({ space: 4 }) {
          Image($r('app.media.' + (this.isPaused() ? 'ic_time_resume' : 'ic_time_stop')))
            .width(15).height(15)
            .fillColor(this.isPaused() ? this.c.textStrong : this.c.text)
          Text(this.isPaused() ? I18n.t('btn_resume') : I18n.t('s0761_stop'))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isPaused() ? this.c.textStrong : this.c.text)
            .maxLines(1)
        }
          .layoutWeight(1.1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.isPaused() ? this.c.chipActiveBg : this.c.softStrong)
          .border({ width: this.isPaused() ? 1.3 : 0.8, color: this.isPaused() ? this.c.chipActiveBorder : this.c.border })
          .shadow(this.isPaused() ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 6, color: this.c.shadowSoft, offsetX: 0, offsetY: 2 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('stop') })

        // 回到实时 1x
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_realtime')).width(15).height(15)
            .fillColor(this.isRealtime() ? this.c.textStrong : this.c.text)
          Text(I18n.t('s0764_realtime'))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isRealtime() ? this.c.textStrong : this.c.text)
            .maxLines(1)
        }
          .layoutWeight(1.1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.isRealtime() ? this.c.chipActiveBg : this.c.softStrong)
          .border({ width: this.isRealtime() ? 1.3 : 0.8, color: this.isRealtime() ? this.c.chipActiveBorder : this.c.border })
          .shadow(this.isRealtime() ? { radius: 10, color: this.c.accent, offsetX: 0, offsetY: 3 } : { radius: 6, color: this.c.shadowSoft, offsetX: 0, offsetY: 2 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('realtime') })

        // 快进（倒退中点一次即降速，实时/暂停点一次即 10分/秒 清晰推进）
        Row({ space: 4 }) {
          Image($r('app.media.ic_time_fast')).width(15).height(15)
            .fillColor(this.isFastForwarding() ? this.c.textStrong : this.c.iconTertiary)
          Text(I18n.t('s0765_fast'))
            .fontSize(12)
            .fontWeight(this.isFastForwarding() ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.isFastForwarding() ? this.c.textStrong : this.c.chipInactiveText)
            .maxLines(1)
        }
          .layoutWeight(1).height(38).justifyContent(FlexAlign.Center).borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.isFastForwarding() ? this.c.chipActiveBg : this.c.chipInactiveBg)
          .border({ width: this.isFastForwarding() ? 1.2 : 0.6, color: this.isFastForwarding() ? this.c.chipActiveBorder : this.c.chipInactiveBorder })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .animation({ duration: 180, curve: curves.springMotion(0.42, 0.86) })
          .onClick(() => { this.onChip('fast') })
      }
        .width('100%')
    }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .margin({ top: 4, bottom: 2 })
  }
}
