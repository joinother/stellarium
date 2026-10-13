import { UI_RADIUS_CONTROL } from './UiTokens'

// 星文化描述块：按 kind 渲染标题 / 项目 / 表格行 / 正文。
//
// 天体详情卡的"星座文化"段与星文化制作器共用，因此做成共享组件；
// `level` 的可选判断由调用方解析成 `headingLarge` 布尔量传入，组件内不做可选值判断；
// 文字颜色（夜视）以 `@Prop textColor` 注入。

@Component
export struct SkyCultureDescriptionBlockView {
  @Prop kind: string
  @Prop headingLarge: boolean
  @Prop text: string
  @Prop textColor: string

  build() {
    if (this.kind === 'heading') {
      Text(this.text).fontSize(this.headingLarge ? 15 : 13)
        .fontColor(this.textColor).fontWeight(FontWeight.Medium).width('100%')
        .margin({ top: 8, bottom: 3 })
    } else if (this.kind === 'bullet') {
      Text('• ' + this.text).fontSize(11).lineHeight(19).fontColor(this.textColor).width('100%')
        .padding({ left: 8, right: 4 })
    } else if (this.kind === 'tableRow') {
      Text(this.text).fontSize(10).lineHeight(17).fontColor(this.textColor).width('100%')
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .backgroundColor('rgba(255,255,255,0.045)').borderRadius(UI_RADIUS_CONTROL)
    } else {
      Text(this.text).fontSize(11).lineHeight(19).fontColor(this.textColor).width('100%')
    }
  }
}
