import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from './UiTokens'
import { APP_ICP_FILING_NUMBER, APP_ICP_FILING_URL } from '../QtAppConstants'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// APP 备案信息（ICP 备案号 + 工信部核验链接）。
// 设置面板「关于」标签页使用本组件与常量，避免备案号在多个面板重复维护。
@Component
export struct AppFilingInfo {
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 4 }) {
      Text(I18n.t('app_icp_filing')).fontSize(12).fontColor(this.c.sub).width('100%')
      Hyperlink(APP_ICP_FILING_URL, APP_ICP_FILING_NUMBER)
        .color(this.c.accent).width('100%').constraintSize({ minHeight: 44 })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        .accessibilityText(I18n.t('app_icp_filing') + ' ' + APP_ICP_FILING_NUMBER)
    }.width('100%').margin({ top: 8, bottom: 8 })
  }
}
