import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { MosaicCameraMetric } from '../../common/ui/MosaicCameraMetric'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { MosaicStore } from '../../state/MosaicStore'

// 马赛克相机面板，对应 `activePanel === 'mosaicCamera'`。
// 加载/开关/相机列表/当前相机/RA-DEC-旋转/叠加可见来自 MosaicStore（@ObjectLink）。

@Component
export struct MosaicCameraPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink mosaicStore: MosaicStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  private cameraMetricValue(key: string): number {
    return key === 'ra' ? this.mosaicStore.mosaicCameraRA : key === 'dec' ? this.mosaicStore.mosaicCameraDec : this.mosaicStore.mosaicCameraRotation
  }

  build() {
      Column({ space: 10 }) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Row({ space: 6 }) {
              Text(I18n.t('mosaic_camera_title'))
                .fontSize(this.fs(15)).fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
              InfoTipButton({
                title: I18n.t('mosaic_camera_title'),
                tip: I18n.t('mosaic_camera_hint')
              })
            }.layoutWeight(1).alignItems(VerticalAlign.Center)
            if (this.mosaicStore.mosaicCameraLoading) { LoadingProgress().width(20).height(20).color(this.c.accent) }
            Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraEnabled })
              .selectedColor(this.c.accent)
              .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
              .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
          }.width('100%').constraintSize({ minHeight: this.ch(40) }).alignItems(VerticalAlign.Center)

          Row().width('100%').height(0.5).backgroundColor(this.c.border)

          Row() {
            Text(I18n.t('mosaic_camera_overlay')).fontSize(this.fs(13)).fontColor(this.c.text).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.mosaicStore.mosaicCameraVisible })
              .selectedColor(this.c.accent)
              .enabled(!this.mosaicStore.mosaicCameraLoading && !this.mosaicStore.mosaicCameraPending)
              .onChange((v: boolean) => { this.onSetSetting('visible', v ? '1' : '0') })
          }.width('100%').constraintSize({ minHeight: this.ch(38) }).alignItems(VerticalAlign.Center)
        }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.mosaicStore.mosaicCameraStatus.length > 0) {
          Text(this.mosaicStore.mosaicCameraStatus).fontSize(this.fs(11)).fontColor(this.c.warning).width('100%').padding({ left: 8, right: 8 })
        }

        Column({ space: 8 }) {
          Text(I18n.t('mosaic_camera_device')).fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%')
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.mosaicStore.mosaicCameraNames, (name: string) => {
                Text(name).fontSize(this.fs(11.5))
                  .fontWeight(this.mosaicStore.mosaicCameraCurrent === name ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.mosaicStore.mosaicCameraCurrent === name ? this.c.onAccent : this.c.sub)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(this.mosaicStore.mosaicCameraCurrent === name ? this.c.accent : this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                  .onClick(() => { this.onSetSetting('camera', name) })
              }, (name: string) => name)
            }.padding({ left: 1, right: 2 })
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

          Row({ space: 8 }) {
            MosaicCameraMetric({ labelKey: 'mosaic_camera_ra', value: this.cameraMetricValue('ra') })
            MosaicCameraMetric({ labelKey: 'mosaic_camera_dec', value: this.cameraMetricValue('dec') })
            MosaicCameraMetric({ labelKey: 'mosaic_camera_rotation', value: this.cameraMetricValue('rotation') })
          }.width('100%')

          Row({ space: 8 }) {
            Button(I18n.t('mosaic_camera_use_view')).fontSize(this.fs(12)).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(38) }).layoutWeight(1)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onSetSetting('setToView', '') })
            Button(I18n.t('mosaic_camera_use_selected')).fontSize(this.fs(12)).fontColor(this.c.text).backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(38) }).layoutWeight(1)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.onSetSetting('setToSelected', '') })
          }.width('100%')

          Button(I18n.t('mosaic_camera_view')).fontSize(this.fs(12.5)).fontWeight(FontWeight.Medium).fontColor(this.c.onAccent).backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_CONTROL).constraintSize({ minHeight: this.ch(38) }).width('100%')
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.onSetSetting('viewToCamera', '') })

          Row() {
            Text(I18n.t('mosaic_camera_rotation')).fontSize(this.fs(12)).fontColor(this.c.sub).layoutWeight(1)
            Text(this.mosaicStore.mosaicCameraRotation.toFixed(0) + '°').fontSize(this.fs(12)).fontColor(this.c.accent)
          }.width('100%').padding({ top: 4 })
          Slider({ value: this.mosaicStore.mosaicCameraRotation, min: -360, max: 360, step: 1 })
            .width('100%').trackColor(this.c.soft).selectedColor(this.c.accent)
            .enabled(!this.mosaicStore.mosaicCameraPending && !this.mosaicStore.mosaicCameraLoading)
            .onChange((value: number, mode: SliderChangeMode) => {
              if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) this.onSetSetting('rotation', value.toString())
            })
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
