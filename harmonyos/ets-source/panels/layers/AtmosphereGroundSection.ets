import { Theme, SymbolGlyphModifier } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LayerStore } from '../../state/LayerStore'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { panelFontSize } from '../../common/ui/UiTypography'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
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

  @Builder
  private auroraStyleChip(styleIndex: number, label: string, dotColor: string) {
    Row({ space: 4 }) {
      Circle({ width: 6, height: 6 })
        .fill(this.c.isNight ? this.c.accent : dotColor)
      Text(label)
        .fontSize(panelFontSize(12, this.readableUi))
        .fontWeight(this.layerStore.auroraStyle === styleIndex ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.layerStore.auroraStyle === styleIndex ? this.c.accent : this.c.sub)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.layerStore.auroraStyle === styleIndex ? this.c.bg : Color.Transparent)
    .border({
      width: 1,
      color: this.layerStore.auroraStyle === styleIndex ? this.c.accent : this.c.border
    })
    .borderRadius(UI_RADIUS_CONTROL)
    .onClick(() => { this.onSetSkyDisplay('auroraStyle', styleIndex) })
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text(this.text('大气层和地面', 'Atmosphere and ground'))
          .fontSize(panelFontSize(15, this.readableUi)).fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
        InfoTipButton({
          title: this.text('大气层和地面', 'Atmosphere and ground'),
          tip: this.text('控制天空大气与地景的组合显示；如需更换地面风格，可前往「地景」标签页。',
            'Controls atmosphere and ground visibility. Choose a ground style in the Landscape tab.')
        })
      }.width('100%').alignItems(VerticalAlign.Center)
      Select([
        { value: this.text('无', 'None') },
        { value: this.text('仅地面', 'Ground only') },
        { value: this.text('大气层和地面', 'Atmosphere and ground') }
      ])
        .selected(this.layerStore.environmentMode < 3 ? this.layerStore.environmentMode : -1)
        .value(this.modeLabel()).width('100%').height(46)
        .font({ size: panelFontSize(14, this.readableUi) })
        .fontColor(this.c.text).backgroundColor(this.c.bg)
        .borderRadius(UI_RADIUS_CONTROL)
        .arrowModifier(this.arrowStyle)
        .optionBgColor(this.c.isNight ? '#150505' : '#101E2C').optionFontColor(this.c.text)
        .menuBackgroundColor(this.c.isNight ? '#150505' : '#101E2C')
        .menuBackgroundBlurStyle(BlurStyle.NONE)
        .optionFont({ size: panelFontSize(14, this.readableUi) })
        .selectedOptionBgColor(this.c.soft).selectedOptionFontColor(this.c.accent)
        .onSelect((index: number) => { this.onSetSkyDisplay('environmentMode', index) })
      Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ top: 2, bottom: 2 })
      LayerSwitchRow({
        label: this.text('绚丽模式', 'Vivid atmosphere'),
        infoTip: this.text('随日出日落呈现更鲜明的蓝色天空与橙紫暮光，不改变天象计算。',
          'Richer blue skies and orange-violet twilight follow the Sun. Astronomy calculations stay unchanged.'),
        hint: !this.layerStore.atmosphere ? this.text('开启大气层后可见效果', 'Visible when the atmosphere is enabled') : '',
        isOn: this.layerStore.vividAtmosphere,
        onToggle: (enabled: boolean) => { this.onSetSkyDisplay('vividAtmosphere', enabled) }
      })
      LayerSwitchRow({
        label: this.text('极光效果', 'Aurora'),
        infoTip: this.text('程序化三维大气极光视觉层，天文暮影后于地球夜空自然显现；支持切换多种自然形态与色系，仅作观星氛围呈现，不代表当地实时地磁预报。',
          'Procedural volumetric aurora curtains visible in Earth night skies after twilight. Choose among natural morphologies and emission palettes; visual atmosphere only, not a local geomagnetic forecast.'),
        isOn: this.layerStore.auroraEnabled,
        onToggle: (enabled: boolean) => { this.onSetSkyDisplay('auroraEnabled', enabled) }
      })
      if (this.layerStore.auroraEnabled) {
        Row({ space: 6 }) {
          this.auroraStyleChip(0, this.text('经典绿幕', 'Arctic'), '#22E588')
          this.auroraStyleChip(1, this.text('红绿磁暴', 'Storm'), '#FF2E7E')
          this.auroraStyleChip(2, this.text('紫韵光柱', 'Pillars'), '#B44CFF')
          this.auroraStyleChip(3, this.text('蓝绿极夜', 'Sapphire'), '#38C8E8')
        }.width('100%').margin({ top: 2, bottom: 2 })
      }
      LayerSwitchRow({
        label: this.text('现实星等', 'Realistic star visibility'),
        infoTip: this.text('开启时，明亮天空会淹没暗星、银河与深空天体；关闭后，白天也能辨认恒星、银河与深空天体，适合学习星空。',
          'On: bright skies hide faint stars, the Milky Way, and deep-sky objects. Off: keep them visible in daylight for exploring the sky.'),
        isOn: this.layerStore.realisticStarVisibility,
        onToggle: (enabled: boolean) => { this.onSetSkyDisplay('realisticStarVisibility', enabled) }
      })
      LayerSwitchRow({
        label: this.text('缩放特写隐去大气与地景', 'Auto-hide atmosphere on zoom'),
        infoTip: this.text('开启后，放大进入望远镜特写视场（10° → 2°）时平滑淡出大气与实景地景，呈现纯净深空与行星视角；关闭时保留物理模拟。',
          'On: smoothly fades atmosphere and ground in telescopic close-ups (10° → 2°). Off: preserves physical simulation.'),
        isOn: this.layerStore.zoomFadeEnvironment,
        onToggle: (enabled: boolean) => { this.onSetSkyDisplay('zoomFadeEnvironment', enabled) }
      })
    }.width('100%').padding(12).backgroundColor(this.c.soft)
      .border({ width: 1, color: this.c.border }).borderRadius(UI_RADIUS_CARD)
      .margin({ top: 4, bottom: 12 })
  }
}
