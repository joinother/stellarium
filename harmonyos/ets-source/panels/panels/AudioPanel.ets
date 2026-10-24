import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { AudioStore } from '../../state/AudioStore'

// 音频控制面板，对应 `activePanel === 'audio'`。
//
// 播放/静音/音量状态来自 AudioStore（@ObjectLink）。AudioEngine 是原生桥，经回调注入：
// 组件内不 import StellariumAudio，播放/静音/音量与提示都由宿主侧的
// onToggleMusic / onVolumeChange 处理。

@Component
export struct AudioPanel {
  @ObjectLink audioStore: AudioStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleMusic: (enabled: boolean) => void = () => {}
  onVolumeChange: (value: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Text(I18n.t('panel_audio_ctrl')).fontSize(15).fontColor(this.c.text).width('100%').margin({ top: 4 })
        Row() {
          Text(I18n.t('audio_toggle')).fontSize(13).fontColor(this.c.text).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.audioStore.musicEnabled })
            .onChange((isOn: boolean) => { this.onToggleMusic(isOn) })
        }.width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        Row() {
          Text(I18n.t('audio_volume')).fontSize(13).fontColor(this.c.text).width(72)
          Text(Math.round(this.audioStore.audioVolume * 100) + '%').fontSize(13).fontColor(this.c.text).margin({ right: 8 })
          Slider({ value: this.audioStore.audioVolume, min: 0, max: 1, step: 0.05, style: SliderStyle.OutSet })
            .sliderInteractionMode(SliderInteraction.SLIDE_ONLY).minResponsiveDistance(8)
            .width('40%')
            .trackColor(this.c.bg)
            .showSteps(false)
            .onChange((val: number) => { this.onVolumeChange(val) })
        }.height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
