import { Theme, SymbolGlyphModifier } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LayerStore } from '../../state/LayerStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { LayerSwitchRow } from './LayerSwitchRow'

@Component
export struct AtmosphereGroundSection {
  @ObjectLink layerStore: LayerStore
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private arrowStyle: SymbolGlyphModifier = new SymbolGlyphModifier().fontColor([DEFAULT_SLOTS.sub])
  onSetSkyDisplay: (setting: string, value: boolean | number) => void = () => {}

  onWillApplyTheme(theme: Theme) {
    this.c = slotsFromTheme(theme)
    this.arrowStyle = new SymbolGlyphModifier().fontColor([this.c.sub])
  }

  private text(chinese: string, english: string): string {
    return I18n.getLanguage().toLowerCase().startsWith('zh') ? chinese : english
  }

  private modeLabel(): string {
    if (this.layerStore.environmentMode === 0) return this.text('无', 'None')
    if (this.layerStore.environmentMode === 1) return this.text('仅地面', 'Ground only')
    if (this.layerStore.environmentMode === 2) return this.text('大气层和地面', 'Atmosphere and ground')
    return this.text('仅大气层 · 自定义', 'Atmosphere only · Custom')
  }

  build() {
    Column({ space: 8 }) {
      Text(this.text('大气层和地面', 'Atmosphere and ground'))
        .fontSize(panelFontSize(15, this.readableUi)).fontWeight(FontWeight.Medium)
        .fontColor(this.c.text).width('100%')
      Select([
        { value: this.text('无', 'None') },
        { value: this.text('仅地面', 'Ground only') },
        { value: this.text('大气层和地面', 'Atmosphere and ground') }
      ])
        .selected(this.layerStore.environmentMode < 3 ? this.layerStore.environmentMode : -1)
        .value(this.modeLabel()).width('100%').height(46)
        .font({ size: panelFontSize(14, this.readableUi) })
        .fontColor(this.c.text).backgroundColor(this.c.bg)
        .arrowModifier(this.arrowStyle)
        .optionBgColor(this.c.bg).optionFontColor(this.c.text)
        .optionFont({ size: panelFontSize(14, this.readableUi) })
        .selectedOptionBgColor(this.c.soft).selectedOptionFontColor(this.c.accent)
        .onSelect((index: number) => { this.onSetSkyDisplay('environmentMode', index) })
      Text(this.text('选择地面样式可前往「地景」。', 'Choose a ground style in Landscape.'))
        .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%')
      Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 4, bottom: 4 })
      Column({ space: 2 }) {
        LayerSwitchRow({
          label: this.text('绚丽模式', 'Vivid atmosphere'), isOn: this.layerStore.vividAtmosphere,
          onToggle: (enabled: boolean) => { this.onSetSkyDisplay('vividAtmosphere', enabled) }
        })
        Text(this.text('随日出日落呈现更鲜明的蓝色天空与橙紫暮光，不改变天象计算。',
          'Richer blue skies and orange-violet twilight follow the Sun. Astronomy calculations stay unchanged.'))
          .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%')
        if (!this.layerStore.atmosphere) {
          Text(this.text('开启大气层后可见效果', 'Visible when the atmosphere is enabled'))
            .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.accent).width('100%')
        }
      }.width('100%')
      Column({ space: 2 }) {
        LayerSwitchRow({
          label: this.text('现实星等', 'Realistic star visibility'), isOn: this.layerStore.realisticStarVisibility,
          onToggle: (enabled: boolean) => { this.onSetSkyDisplay('realisticStarVisibility', enabled) }
        })
        Text(this.text('开启时，明亮天空会淹没暗星；关闭后，白天也能辨认恒星，适合学习星空。',
          'On: bright skies hide faint stars. Off: keep stars visible in daylight for exploring the sky.'))
          .fontSize(panelFontSize(12, this.readableUi)).fontColor(this.c.sub).width('100%')
      }.width('100%')
    }.width('100%').padding(12).backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CONTROL)
      .margin({ top: 4, bottom: 12 })
  }
}
