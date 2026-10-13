import { I18n } from '../../pages/I18n'
import { MosaicCameraMetric } from '../../common/ui/MosaicCameraMetric'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { MosaicStore } from '../../state/MosaicStore'

// 马赛克相机面板，对应 `activePanel === 'mosaicCamera'`。
//
// 加载/开关/相机列表/当前相机/RA-DEC-旋转/叠加可见来自 MosaicStore（@ObjectLink）；
// 设置动作回调注入宿主；cameraMetricValue 为组件内纯计算。

@Component
export struct MosaicCameraPanel {
  @ObjectLink mosaicStore: MosaicStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop accentColor: string
  onSetSetting: (setting: string, value: string) => void = () => {}

  private cameraMetricValue(key: string): number {
    return key === 'ra' ? this.mosaicStore.mosaicCameraRA : key === 'dec' ? this.mosaicStore.mosaicCameraDec : this.mosaicStore.mosaicCameraRotation
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text(I18n.t('mosaic_camera_title')).fontSize(14).fontColor(this.textColor).width('100%')
            Text(I18n.t('mosaic_camera_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.mosaicStore.mosaicCameraLoading) { LoadingProgress().width(20).height(20).color(this.accentColor) }
          Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraEnabled })
            .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
            .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        if (this.mosaicStore.mosaicCameraStatus.length > 0) {
          Text(this.mosaicStore.mosaicCameraStatus).fontSize(10).fontColor('#FFD59A').width('100%').padding({ left: 10, right: 10 })
        }
        Text(I18n.t('mosaic_camera_device')).fontSize(11).fontColor(this.subColor).width('100%')
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.mosaicStore.mosaicCameraNames, (name: string) => {
              Text(name).fontSize(11).fontColor(this.mosaicStore.mosaicCameraCurrent === name ? '#FFFFFF' : this.subColor)
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .backgroundColor(this.mosaicStore.mosaicCameraCurrent === name ? this.accentColor : this.panelColor).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSetting('camera', name) })
            }, (name: string) => name)
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Row({ space: 10 }) {
          MosaicCameraMetric({ labelKey: 'mosaic_camera_ra', value: this.cameraMetricValue('ra'), subColor: this.subColor, textColor: this.textColor })
          MosaicCameraMetric({ labelKey: 'mosaic_camera_dec', value: this.cameraMetricValue('dec'), subColor: this.subColor, textColor: this.textColor })
          MosaicCameraMetric({ labelKey: 'mosaic_camera_rotation', value: this.cameraMetricValue('rotation'), subColor: this.subColor, textColor: this.textColor })
        }.width('100%')
        Row() {
          Text(I18n.t('mosaic_camera_overlay')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraVisible })
            .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
            .onChange((v: boolean) => { this.onSetSetting('visible', v ? '1' : '0') })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        Row({ space: 8 }) {
          Button(I18n.t('mosaic_camera_use_view')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1).onClick(() => { this.onSetSetting('setToView', '') })
          Button(I18n.t('mosaic_camera_use_selected')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1).onClick(() => { this.onSetSetting('setToSelected', '') })
        }.width('100%')
        Button(I18n.t('mosaic_camera_view')).fontSize(11).fontColor('#FFFFFF').backgroundColor(this.accentColor)
          .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').onClick(() => { this.onSetSetting('viewToCamera', '') })
        Text(I18n.t('mosaic_camera_rotation')).fontSize(12).fontColor(this.subColor).width('100%')
        Slider({ value: this.mosaicStore.mosaicCameraRotation, min: -360, max: 360, step: 1 })
          .width('100%').enabled(!this.mosaicStore.mosaicCameraPending && !this.mosaicStore.mosaicCameraLoading)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onSetSetting('rotation', value.toString())
          })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
  }
}
