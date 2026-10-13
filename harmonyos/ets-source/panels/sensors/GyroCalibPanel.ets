import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { GyroStore } from '../../state/GyroStore'


// 陀螺仪校准面板。
//
// 校准、开关与提示由宿主执行，以回调注入；面板内对偏移/灵敏度/开关的写入直接落 store。
@Component
export struct GyroCalibPanel {
  @ObjectLink store: GyroStore
  onFlashHint: (text: string) => void = () => {}
  onCalibrate: () => void = () => {}
  onToggle: (enabled: boolean) => void = () => {}

  build() {
    Column({ space: 12 }) {
      // 标题行
      Row() {
        Stack() {
          Circle().width(10).height(10)
            .fill(this.store.gyroscopeEnabled ? '#5BDF7F' : '#666')
            .opacity(0.9)
        }.width(16).height(16)
        Text(I18n.t('i0060'))
          .fontSize(14).fontWeight(FontWeight.Bold).fontColor('#E5FFFFFF').layoutWeight(1).margin({ left: 6 })
        Text('×')
          .fontSize(18).fontColor('#99FFFFFF')
          .onClick(() => { this.store.gyroCalibPanelOpen = false })
      }
      .width('100%')

      Text(I18n.t('i0043'))
        .fontSize(11).fontColor('#8099BBCC').width('100%')

      // 灵敏度选择
      Row({ space: 8 }) {
        Text(I18n.t('i0061')).fontSize(12).fontColor('#CCCCCC').width(44)
        Row({ space: 6 }) {
          ForEach(['Low', 'Standard', 'High'], (s: string, idx: number) => {
            Text(s)
              .fontSize(11)
              .fontColor(this.store.gyroscopeSensitivityText === s ? '#FFFFFF' : '#8099BBCC')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(UI_RADIUS_CONTROL)
              .backgroundColor(this.store.gyroscopeSensitivityText === s ? 'rgba(91,147,191,0.35)' : 'rgba(255,255,255,0.06)')
              .onClick(() => {
                this.store.gyroscopeSensitivityText = s
                this.onFlashHint(s)
              })
          })
        }.layoutWeight(1).justifyContent(FlexAlign.End)
      }.width('100%')

      // 方位角校准
      Row({ space: 10 }) {
        Text(I18n.t('i0084') + '→' + I18n.t('i0086')).fontSize(11).fontColor('#CCCCCC').width(50)
        Slider({ value: this.store.gyroOffsetAz, min: -30, max: 30, step: 0.5 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .selectedColor('#5B93BF')
          .trackColor('rgba(255,255,255,0.12)')
          .onChange((v: number) => { this.store.gyroOffsetAz = v })
        Text(this.store.gyroOffsetAz.toFixed(1) + '°')
          .fontSize(11).fontColor('#7FB3DC').width(48).textAlign(TextAlign.End)
      }.width('100%')

      // 高度角校准
      Row({ space: 10 }) {
        Text(I18n.t('i0016')).fontSize(11).fontColor('#CCCCCC').width(50)
        Slider({ value: this.store.gyroOffsetAlt, min: -30, max: 30, step: 0.5 })
          .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
          .layoutWeight(1)
          .selectedColor('#5B93BF')
          .trackColor('rgba(255,255,255,0.12)')
          .onChange((v: number) => { this.store.gyroOffsetAlt = v })
        Text(this.store.gyroOffsetAlt.toFixed(1) + '°')
          .fontSize(11).fontColor('#7FB3DC').width(48).textAlign(TextAlign.End)
      }.width('100%')

      // 重置按钮
      Row({ space: 8 }) {
        Button(I18n.t('i0053'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(91,147,191,0.25)').borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
          .onClick(() => {
            this.store.gyroOffsetAz = 0
            this.store.gyroOffsetAlt = 0
            this.store.gyroCompassAzAlignment = 0
            this.onCalibrate()
            this.onFlashHint('已重新校准')
          })
        Button(I18n.t('i0051'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(200,80,60,0.25)').borderRadius(UI_RADIUS_CONTROL).height(32).layoutWeight(1)
          .onClick(() => {
            this.onToggle(false)
            this.store.gyroCalibPanelOpen = false
          })
      }.width('100%').margin({ top: 4 })

      // 状态信息
      Row() {
        Text((this.store.gyroscopeStatus as string))
          .fontSize(10).fontColor('#8099BBCC')
      }.width('100%')
    }
    .width(280)
    .padding(16)
    .backgroundColor('rgba(12, 16, 28, 0.92)')
    .border({ width: 0.5, color: 'rgba(91, 147, 191, 0.18)' })
    .borderRadius(UI_RADIUS_PILL)
    .shadow({ radius: 20, color: 'rgba(0,0,0,0.30)', offsetX: 0, offsetY: 8 })
  }
}
