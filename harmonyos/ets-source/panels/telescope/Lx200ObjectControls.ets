import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { TelescopeStore } from '../../state/TelescopeStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 天体详情卡里的 LX200 快捷控制条。
//
// 三个命令（GoTo / 同步 / 中止）经原生桥，留在宿主，以回调注入。
@Component
export struct Lx200ObjectControls {
  @ObjectLink store: TelescopeStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onGoto: () => void = () => {}
  onSync: () => void = () => {}
  onAbort: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column() {
      Row() {
        Text(I18n.t('i0041'))
          .fontSize(12)
          .fontColor(this.c.tertiary)
          .layoutWeight(1)
      }
        .width('100%')
      Row() {
        Button(I18n.t('i0049'))
          .height(32)
          .fontSize(12)
          .fontColor(this.c.textStrong)
          .backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8 })
          .onClick(() => {
            this.onGoto()
          })
        Button(I18n.t('i0050'))
          .height(32)
          .fontSize(12)
          .fontColor(this.c.tertiary)
          .backgroundColor(this.c.softStrong)
          .border({ width: 1, color: this.c.softStrong })
          .borderRadius(UI_RADIUS_PILL)
          .margin({ right: 8 })
          .onClick(() => {
            this.onSync()
          })
        Button(I18n.t('i0051'))
          .height(32)
          .fontSize(12)
          .fontColor(this.c.errorText)
          .backgroundColor(this.c.errorBg)
          .border({ width: 1, color: this.c.errorBg })
          .borderRadius(UI_RADIUS_PILL)
          .onClick(() => {
            this.onAbort()
          })
      }
        .width('100%')
        .margin({ top: 8 })
      Text(this.store.lx200Status)
        .fontSize(11)
        .fontColor(this.c.sub)
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })
    }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.softStrong })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 8, bottom: 8 })
  }
}
