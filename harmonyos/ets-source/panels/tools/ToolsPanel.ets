import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { ToolsStore } from '../../state/ToolsStore'

// 「工具」面板内容。
//
// 导出/导入/截图/会话导出应用/取日志等**副作用**都走原生桥，留在宿主、以回调注入。
//
// 输入框值走 @Prop、编辑走 onChange 回调，避免子组件直接写
// @ObjectLink 的属性。数据（可见性、日志/配置文本、消息）走 @ObjectLink 实时刷新。
//
// 视觉：标题 15 号 top4、提示 10 号；三张卡片 padding(10) + panelColor 底 + UI_RADIUS_CONTROL；
// 按钮高 30 / 11 号 / panelColor 底；配置预览高 120、会话预览高 100、日志高 180、等宽 9 号；
// 外层 Column space 10 / padding 8，Scroll 占满并 layoutWeight(1)。
@Component
export struct ToolsPanel {
  @ObjectLink store: ToolsStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop inputColor: string
  @Prop configImportText: string
  @Prop sessionImportText: string
  onScreenshot: () => void = () => {}
  onExportConfig: () => void = () => {}
  onShareConfig: () => void = () => {}
  onImportConfig: () => void = () => {}
  onConfigImportText: (value: string) => void = () => {}
  onSessionExport: () => void = () => {}
  onSessionShare: () => void = () => {}
  onSessionApply: () => void = () => {}
  onSessionImportText: (value: string) => void = () => {}
  onLoadLog: () => void = () => {}
  onCollapseLog: () => void = () => {}

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text(I18n.t('panel_tools_data')).fontSize(15).fontColor(this.textColor).width('100%').margin({ top: 4 })
        Text(I18n.t('tools_data_hint')).fontSize(10).fontColor(this.subColor).width('100%')

        Row({ space: 8 }) {
          Text(I18n.t('tools_screenshot')).fontSize(13).fontColor(this.textColor).layoutWeight(1)
          Button(this.store.screenshotSaving ? I18n.t('screenshot_preparing') : I18n.t('i0251')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 })
            .enabled(!this.store.screenshotSaving)
            .onClick(() => { this.onScreenshot() })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(I18n.t('tools_config_backup')).fontSize(13).fontColor(this.textColor).layoutWeight(1)
            Button(I18n.t('btn_export_view')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onExportConfig() })
            Button(I18n.t('config_share')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onShareConfig() })
            Button(I18n.t('btn_import_config')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onImportConfig() })
          }.width('100%')
          if (this.store.configExportVisible) {
            Scroll() {
              Text(this.store.configExportText.length > 0 ? this.store.configExportText : '（配置为空）').fontSize(10).fontColor(this.subColor).width('100%').fontFamily('monospace')
            }.width('100%').height(120).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).padding(8)
          }
          TextArea({ placeholder: I18n.t('c_config_import_hint'), text: this.configImportText })
            .fontSize(10).fontColor(this.textColor).placeholderFont({ size: 10 }).placeholderColor(this.subColor)
            .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).width('100%').height(76)
            .onChange((value: string) => { this.onConfigImportText(value) })
          Text(this.store.configImportMsg.length > 0 ? this.store.configImportMsg : ' ').fontSize(10).fontColor('#FFAA00').width('100%').height(16)
        }.width('100%').padding(10).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(I18n.t('tools_session')).fontSize(13).fontColor(this.textColor).layoutWeight(1)
            Button(I18n.t('session_export')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onSessionExport() })
            Button(I18n.t('session_share')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onSessionShare() })
            Button(I18n.t('session_import')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onSessionApply() })
          }.width('100%')
          Text(I18n.t('session_hint')).fontSize(10).fontColor(this.subColor).width('100%')
          if (this.store.sessionExportText.length > 0) {
            Scroll() {
              Text(this.store.sessionExportText).fontSize(10).fontColor(this.subColor).width('100%').fontFamily('monospace')
            }.width('100%').height(100).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).padding(8)
          }
          TextArea({ placeholder: I18n.t('session_import_hint'), text: this.sessionImportText })
            .fontSize(10).fontColor(this.textColor).placeholderColor(this.subColor)
            .backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).width('100%').height(72)
            .onChange((value: string) => { this.onSessionImportText(value) })
          if (this.store.sessionImportMsg.length > 0) {
            Text(this.store.sessionImportMsg).fontSize(10).fontColor('#FFAA00').width('100%')
          }
        }.width('100%').padding(10).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(I18n.t('tools_logs')).fontSize(13).fontColor(this.textColor).layoutWeight(1)
            Button(this.store.logVisible ? I18n.t('btn_refresh') : I18n.t('btn_view_logs')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onLoadLog() })
            if (this.store.logVisible) {
              Button(I18n.t('btn_collapse')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 10, right: 10 }).onClick(() => { this.onCollapseLog() })
            }
          }.width('100%')
          if (this.store.logVisible) {
            Scroll() {
              Text(this.store.logText.length > 0 ? this.store.logText : '（日志为空）').fontSize(10).fontColor(this.subColor).width('100%').fontFamily('monospace')
            }.width('100%').height(180).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL).padding(8)
          }
        }.width('100%').padding(10).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
