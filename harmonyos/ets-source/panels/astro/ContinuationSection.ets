import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 会话延续块。
//
// 提示文本与会话 JSON 由宿主以 @Prop 传入（两者都来自宿主的会话状态），
// 导出 / 应用 / 开始延续三个动作仍由宿主执行，以回调注入。

@Component
export struct ContinuationSection {
  @Prop hint: string
  @Prop json: string
  @Prop textColor: string
  @Prop panelColor: string
  onExport: () => void = () => {}
  onApply: () => void = () => {}
  onHandoff: () => void = () => {}

  build() {
    Column({ space: 8 }) {
      Text(I18n.t('c_continuation')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 10, bottom: 2 })
      Text(I18n.t('m_continuation_desc'))
        .fontSize(11).fontColor('#99FFFFFF').width('100%').margin({ bottom: 2 })
      if (this.hint !== '') {
        Text(this.hint).fontSize(12).fontColor('#CCFFCC').width('100%').margin({ top: 2, bottom: 2 })
      }
      Row({ space: 8 }) {
        Button(I18n.t('btn_export_session'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor('#5B93BF')
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.onExport() })
        Button(I18n.t('btn_apply_local'))
          .fontSize(13).fontColor('#FFFFFF').backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1)
          .onClick(() => { this.onApply() })
      }.width('100%').margin({ top: 4 })
      Button(I18n.t('btn_start_continuation'))
        .fontSize(13).fontColor('#FFFFFF').backgroundColor('#3A6EA5')
        .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').margin({ top: 4 })
        .onClick(() => { this.onHandoff() })
      if (this.json !== '') {
        Scroll() {
          Text(this.json)
            .fontSize(10).fontColor('#BBBBBB').fontFamily('monospace')
            .width('100%').padding(6)
        }.height(160).width('100%').backgroundColor('#1A1A1A').borderRadius(UI_RADIUS_CONTROL).margin({ top: 4 })
      }
    }.width('100%').padding({ left: 10, right: 10 })
  }
}
