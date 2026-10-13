import { I18n } from '../../pages/I18n'
import { ToolsStore } from '../../state/ToolsStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { AppFilingInfo } from '../../common/ui/AppFilingInfo'

// 帮助面板，对应 `activePanel === 'help'`：静态说明文字 + 手势/快捷操作图例。
//
// “关于”一节的版本信息读 ToolsStore（@ObjectLink）；“数据与工具”按钮经回调打开工具面板。
// 分隔线颜色用 lineColor：成员名须避开 CustomComponent 基类的 borderColor 属性方法。

@Component
export struct HelpPanel {
  @ObjectLink tools: ToolsStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop lineColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  onOpenTools: () => void = () => {}

  build() {
    Scroll() {
      Column({ space: 8 }) {
        Text(I18n.t('i0216')).fontSize(13).fontColor(this.textColor).width('100%').margin({ top: 4 })
        Text(I18n.t('i0261')).fontSize(11).fontColor(this.subColor).width('100%')
        Text(I18n.t('i0262')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0263')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0264')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        // ===== 手势指南 =====
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text(I18n.t('i0310')).fontSize(13).fontColor(this.textColor).width('100%')
        Row({ space: 10 }) {
          Text('DRAG').fontSize(10).fontColor(this.accentColor).fontWeight(FontWeight.Bold).width(36).height(20)
            .textAlign(TextAlign.Center).borderRadius(UI_RADIUS_CONTROL).backgroundColor(this.panelColor)
          Text(I18n.t('i0311')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
        Row({ space: 10 }) {
          Text('PINCH').fontSize(10).fontColor(this.accentColor).fontWeight(FontWeight.Bold).width(36).height(20)
            .textAlign(TextAlign.Center).borderRadius(UI_RADIUS_CONTROL).backgroundColor(this.panelColor)
          Text(I18n.t('i0312')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
        Row({ space: 10 }) {
          Text('TAP').fontSize(10).fontColor(this.accentColor).fontWeight(FontWeight.Bold).width(36).height(20)
            .textAlign(TextAlign.Center).borderRadius(UI_RADIUS_CONTROL).backgroundColor(this.panelColor)
          Text(I18n.t('i0313')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
        Row({ space: 10 }) {
          Text('2FD').fontSize(10).fontColor(this.accentColor).fontWeight(FontWeight.Bold).width(36).height(20)
            .textAlign(TextAlign.Center).borderRadius(UI_RADIUS_CONTROL).backgroundColor(this.panelColor)
          Text(I18n.t('i0314')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
        Row({ space: 10 }) {
          Text('HOLD').fontSize(10).fontColor(this.accentColor).fontWeight(FontWeight.Bold).width(36).height(20)
            .textAlign(TextAlign.Center).borderRadius(UI_RADIUS_CONTROL).backgroundColor(this.panelColor)
          Text(I18n.t('i0315')).fontSize(10).fontColor('#99FFFFFF').layoutWeight(1)
        }.width('100%').padding({ left: 4, right: 4 }).alignItems(VerticalAlign.Center)
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text('键盘、鼠标与触摸板').fontSize(13).fontColor(this.textColor).width('100%')
        Text('鼠标左键点击选中天体，按住左键拖动星图，滚轮缩放视场。').fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text('触摸板双指滚动平移星图，双指捏合缩放视场。').fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text('方向键平移，+ / - 缩放，空格或回车定位已选天体，F 打开搜索，N 切换夜视，Esc 关闭面板。')
          .fontSize(10).fontColor('#99FFFFFF').width('100%')
        // ===== 快捷操作 =====
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text(I18n.t('i0217')).fontSize(13).fontColor(this.textColor).width('100%')
        Text(I18n.t('i0265')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0266')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0267')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0268')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text(I18n.t('i0218')).fontSize(13).fontColor(this.textColor).width('100%')
        Text(I18n.t('i0269')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0270')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0271')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0272')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0273')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        Text(I18n.t('i0274')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        // ===== 关于 =====
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text(I18n.t('c_about')).fontSize(13).fontColor(this.textColor).width('100%')
        AppFilingInfo({ subColor: this.subColor, panelColor: this.panelColor })
        if (this.tools.aboutVersion.length > 0) {
          Text('Stellarium ' + this.tools.aboutVersion + ' · Qt ' + this.tools.aboutQt).fontSize(10).fontColor('#99FFFFFF').width('100%')
          Text(I18n.t('c_user_dir') + ': ' + this.tools.aboutUserDir).fontSize(10).fontColor('#99FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(I18n.t('c_config_file') + ': ' + this.tools.aboutConfigFile).fontSize(10).fontColor('#99FFFFFF').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text(I18n.t('c_loading')).fontSize(10).fontColor('#99FFFFFF').width('100%')
        }
        Row()
          .width('100%').height(0.5)
          .backgroundColor(this.lineColor)
          .margin({ top: 8, bottom: 4 })
        Text(I18n.t('tools_data_hint')).fontSize(10).fontColor(this.subColor).width('100%')
        Button(I18n.t('panel_tools_data'))
          .fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(30).width('100%')
          .onClick(() => { this.onOpenTools() })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
