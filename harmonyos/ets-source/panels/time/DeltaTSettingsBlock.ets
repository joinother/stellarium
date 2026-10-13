import { I18n } from '../../pages/I18n'
import { DeltaTStore } from '../../state/DeltaTStore'
import { UI_RADIUS_CONTROL, UI_OPTION_ANIMATION_MS } from '../../common/ui/UiTokens'

// ΔT 算法块：当前算法 + 算法列表（选择）+ 自定义系数输入 + 说明。
//
// 三个坑要避开：算法列表用 ForEach 内直接读 store（不加参数化 @Builder），
// 自定义系数直接读写 store，`pending` 由宿主以 @Prop 传入（它同时被启动时间设置区使用，
// 因此仍留在宿主，不并入本 store）。
@Component
export struct DeltaTSettingsBlock {
  @ObjectLink store: DeltaTStore
  @Prop pending: boolean
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop inputColor: string
  @Prop accentColor: string
  onSelect: (key: string) => void = () => {}
  onSaveCustom: (text: string) => void = () => {}

  private label(key: string): string {
    switch (key) {
      case 'EspenakMeeusModified': return '修订的 Espenak-Meeus（推荐）'
      case 'EspenakMeeus': return 'Espenak-Meeus'
      case 'JPLHorizons': return 'JPL Horizons'
      case 'WithoutCorrection': return '不进行修正'
      case 'Custom': return '自定义公式'
      default: return key
    }
  }

  build() {
    Column() {
      Text('ΔT 算法').fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 8 }).margin({ bottom: 4 })
      Text(I18n.t('time_delta_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
      Text(this.label(this.store.deltaTAlgorithm)).fontSize(13).fontColor(this.textColor).width('100%').padding(8)
      Scroll() {
        Column({ space: 3 }) {
          ForEach(this.store.timeDeltaTAlgorithms, (key: string) => {
            Row() {
              Text(this.label(key)).fontSize(10).fontColor(this.store.deltaTAlgorithm === key ? this.textColor : this.subColor).layoutWeight(1).maxLines(2)
              if (this.store.deltaTAlgorithm === key) Text('✓').fontSize(12).fontColor(this.accentColor)
            }.width('100%').padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.store.deltaTAlgorithm === key ? this.panelColor : Color.Transparent).borderRadius(UI_RADIUS_CONTROL)
              .animation({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut })
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .enabled(!this.pending).onClick(() => { this.onSelect(key) })
          }, (key: string) => key)
        }.width('100%')
      }.width('100%').height(170).scrollBar(BarState.Auto).scrollBarWidth(4)
      if (this.store.deltaTAlgorithm === 'Custom') {
        Column({ space: 6 }) {
          Text(I18n.t('time_delta_custom_hint')).fontSize(12).fontColor(this.subColor).width('100%').padding(8)
          ForEach(['year', 'ndot', 'a', 'b', 'c'], (key: string, index: number) => {
            Row({ space: 8 }) {
              Text(I18n.t('time_delta_' + key)).fontSize(12).fontColor(this.textColor).layoutWeight(1)
              TextInput({ text: this.store.timeDeltaTCustom.split(',')[index] ?? '' }).fontSize(13).height(40).width('50%')
                .fontColor(this.textColor).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
                .enabled(!this.pending).onChange((value: string) => {
                  const parts = this.store.timeDeltaTCustom.split(',')
                  parts[index] = value
                  this.store.timeDeltaTCustom = parts.join(',')
                })
            }.width('100%').margin({ bottom: 6 })
          }, (key: string) => key)
          Button(I18n.t('time_save')).fontSize(12).height(40).enabled(!this.pending)
            .fontColor(this.textColor).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSaveCustom(this.store.timeDeltaTCustom) })
        }.width('100%').transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 6 })))
      }
      if (this.store.deltaTDescription.length > 0) {
        Text(this.store.deltaTDescription).fontSize(12).fontColor(this.subColor).width('100%').padding(10)
      }
    }.width('100%')
  }
}
