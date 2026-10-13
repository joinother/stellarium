import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 星文化制作器的单行文本字段。
//
// 做成组件而非参数化 @Builder：@Builder 的 value/placeholder 是简单类型形参，按值捕获、首帧后整段冻结，
// 撤销 / 重置 / 导入草稿后字段不会刷新；组件由 @Prop 实时刷新。
// 编辑后经 onEdited 回调让宿主重新排一次自动保存。标签 10 号，输入框高 38 / 字号 12，圆角 UI_RADIUS_CONTROL。
@Component
export struct SkyCultureMakerField {
  @Prop label: ResourceStr
  @Prop value: string
  @Prop placeholder: ResourceStr
  @Prop labelColor: string
  @Prop textColor: string
  @Prop inputColor: string
  @Prop inputBorderColor: string
  onChange: (value: string) => void = () => {}
  onEdited: () => void = () => {}

  build() {
    Column({ space: 5 }) {
      Text(this.label).fontSize(10).fontColor(this.labelColor).width('100%')
      TextInput({ text: this.value, placeholder: this.placeholder })
        .height(38).width('100%').fontSize(12).fontColor(this.textColor).placeholderColor(this.labelColor)
        .backgroundColor(this.inputColor).border({ width: 1, color: this.inputBorderColor }).borderRadius(UI_RADIUS_CONTROL)
        .onChange((text: string) => { this.onChange(text); this.onEdited() })
    }.width('100%')
  }
}

// 星文化制作器的多行文本字段。同上。
@Component
export struct SkyCultureMakerLongField {
  @Prop label: ResourceStr
  @Prop value: string
  @Prop placeholder: ResourceStr
  @Prop labelColor: string
  @Prop textColor: string
  @Prop inputColor: string
  @Prop inputBorderColor: string
  onChange: (value: string) => void = () => {}
  onEdited: () => void = () => {}

  build() {
    Column({ space: 5 }) {
      Text(this.label).fontSize(10).fontColor(this.labelColor).width('100%')
      TextArea({ text: this.value, placeholder: this.placeholder })
        .height(94).width('100%').fontSize(12).fontColor(this.textColor).placeholderColor(this.labelColor)
        .backgroundColor(this.inputColor).border({ width: 1, color: this.inputBorderColor }).borderRadius(UI_RADIUS_CONTROL)
        .onChange((text: string) => { this.onChange(text); this.onEdited() })
    }.width('100%')
  }
}
