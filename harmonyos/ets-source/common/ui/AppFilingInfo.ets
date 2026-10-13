import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from './UiTokens'
import { APP_ICP_FILING_NUMBER, APP_ICP_FILING_URL } from '../QtAppConstants'

// APP 备案信息（ICP 备案号 + 工信部核验链接）。
// 设置面板「设备与隐私」与帮助面板「关于」两处共用同一组件与常量。
@Component
export struct AppFilingInfo {
  @Prop subColor: string
  @Prop panelColor: string

  build() {
    Column({ space: 4 }) {
      Text(I18n.t('app_icp_filing')).fontSize(12).fontColor(this.subColor).width('100%')
      Hyperlink(APP_ICP_FILING_URL, APP_ICP_FILING_NUMBER)
        .color('#8CC9F2').width('100%').constraintSize({ minHeight: 44 })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        .accessibilityText(I18n.t('app_icp_filing') + ' ' + APP_ICP_FILING_NUMBER)
    }.width('100%').margin({ top: 8, bottom: 8 })
  }
}
