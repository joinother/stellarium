import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
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
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private cameraMetricValue(key: string): number {
    return key === 'ra' ? this.mosaicStore.mosaicCameraRA : key === 'dec' ? this.mosaicStore.mosaicCameraDec : this.mosaicStore.mosaicCameraRotation
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text(I18n.t('mosaic_camera_title')).fontSize(14).fontColor(this.c.text).width('100%')
            Text(I18n.t('mosaic_camera_hint')).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.mosaicStore.mosaicCameraLoading) { LoadingProgress().width(20).height(20).color(this.c.accent) }
          Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraEnabled })
            .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
            .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 8 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        if (this.mosaicStore.mosaicCameraStatus.length > 0) {
          Text(this.mosaicStore.mosaicCameraStatus).fontSize(10).fontColor(this.c.warning).width('100%').padding({ left: 10, right: 10 })
        }
        Text(I18n.t('mosaic_camera_device')).fontSize(11).fontColor(this.c.sub).width('100%')
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.mosaicStore.mosaicCameraNames, (name: string) => {
              Text(name).fontSize(11).fontColor(this.mosaicStore.mosaicCameraCurrent === name ? this.c.onAccent : this.c.sub)
                .padding({ left: 10, right: 10, top: 7, bottom: 7 })
                .backgroundColor(this.mosaicStore.mosaicCameraCurrent === name ? this.c.accent : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSetting('camera', name) })
            }, (name: string) => name)
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Row({ space: 10 }) {
          MosaicCameraMetric({ labelKey: 'mosaic_camera_ra', value: this.cameraMetricValue('ra') })
          MosaicCameraMetric({ labelKey: 'mosaic_camera_dec', value: this.cameraMetricValue('dec') })
          MosaicCameraMetric({ labelKey: 'mosaic_camera_rotation', value: this.cameraMetricValue('rotation') })
        }.width('100%')
        Row() {
          Text(I18n.t('mosaic_camera_overlay')).fontSize(12).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraVisible })
            .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
            .onChange((v: boolean) => { this.onSetSetting('visible', v ? '1' : '0') })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row({ space: 8 }) {
          Button(I18n.t('mosaic_camera_use_view')).fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1).onClick(() => { this.onSetSetting('setToView', '') })
          Button(I18n.t('mosaic_camera_use_selected')).fontSize(11).fontColor(this.c.text).backgroundColor(this.c.bg)
            .borderRadius(UI_RADIUS_CONTROL).height(34).layoutWeight(1).onClick(() => { this.onSetSetting('setToSelected', '') })
        }.width('100%')
        Button(I18n.t('mosaic_camera_view')).fontSize(11).fontColor(this.c.textStrong).backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_CONTROL).height(34).width('100%').onClick(() => { this.onSetSetting('viewToCamera', '') })
        Text(I18n.t('mosaic_camera_rotation')).fontSize(12).fontColor(this.c.sub).width('100%')
        Slider({ value: this.mosaicStore.mosaicCameraRotation, min: -360, max: 360, step: 1 })
          .width('100%').enabled(!this.mosaicStore.mosaicCameraPending && !this.mosaicStore.mosaicCameraLoading)
          .onChange((value: number, mode: SliderChangeMode) => {
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onSetSetting('rotation', value.toString())
          })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
  }
}
