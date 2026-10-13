// 计算中：转圈 + 进度文案（通用加载行）。
@Component
export struct GraphLoadingRow {
  @Prop label: string
  @Prop accentColor: string
  @Prop subColor: string

  build() {
    Row({ space: 8 }) {
      LoadingProgress().width(22).height(22).color(this.accentColor)
      Text(this.label).fontSize(11).fontColor(this.subColor)
    }.width('100%').padding({ left: 8 }).margin({ top: 8, bottom: 6 })
  }
}
