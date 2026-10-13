// 观测辅助块：大气折射（气压 / 气温 / 消光），嵌在「图层 → 天空 → 观测条件」节内。
//
// 状态由宿主持有、以 @Prop 下发，因为 `applyAtmosphere()` 是宿主的命令桥入口。
@Component
export struct ObservationAidBlock {
  @Prop refractionOn: boolean
  @Prop atmoPressure: number
  @Prop atmoTemperature: number
  @Prop atmoExtinction: number
  @Prop textColor: string
  @Prop subColor: string
  @Prop borderColorValue: string
  onAtmosphere: (pressure: number, temperature: number, extinction: number) => void = () => {}

  build() {
    Column() {
      Row()
        .width('100%').height(0.5)
        .backgroundColor(this.borderColorValue)
        .margin({ top: 8, bottom: 4 })
      Row() {
        Column({ space: 1 }) {
          Text('大气折射').fontSize(12).fontColor(this.textColor).width('100%')
          Text('空气会把贴近地平线的天体"抬高"一点，开启后显示的是肉眼实际看到的位置').fontSize(10).fontColor(this.subColor).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Toggle({ type: ToggleType.Switch, isOn: this.refractionOn })
          .onChange((v: boolean) => { this.onAtmosphere(v ? 1013 : 0, this.atmoTemperature, this.atmoExtinction) })
      }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 4 })
      Row() {
        Text('气压').fontSize(11).fontColor(this.subColor).width(56)
        Slider({ value: this.atmoPressure, min: 0, max: 1100, step: 5 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .onChange((v: number) => { this.onAtmosphere(v, this.atmoTemperature, this.atmoExtinction) })
        Text(this.atmoPressure.toFixed(0) + ' mbar').fontSize(10).fontColor(this.subColor).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text('气温').fontSize(11).fontColor(this.subColor).width(56)
        Slider({ value: this.atmoTemperature, min: -40, max: 50, step: 1 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .onChange((v: number) => { this.onAtmosphere(this.atmoPressure, v, this.atmoExtinction) })
        Text(this.atmoTemperature.toFixed(0) + ' °C').fontSize(10).fontColor(this.subColor).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Row() {
        Text('消光').fontSize(11).fontColor(this.subColor).width(56)
        Slider({ value: this.atmoExtinction, min: 0, max: 1, step: 0.01 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .onChange((v: number) => { this.onAtmosphere(this.atmoPressure, this.atmoTemperature, v) })
        Text(this.atmoExtinction.toFixed(2)).fontSize(10).fontColor(this.subColor).width(72).textAlign(TextAlign.End)
      }.width('100%').padding({ left: 10, right: 10 })
      Text('消光越大，越靠近地平线的星星被大气挡得越暗（城市雾霾天可调高）。')
        .fontSize(10).fontColor(this.subColor).width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 4 })
    }.width('100%')
  }
}
