import { Theme } from '@kit.ArkUI'
import { panelFontSize, uiControlHeight } from '../../common/ui/UiTypography'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { NavStarsStore } from '../../state/NavStarsStore'
import { NavStarsToggleRow } from '../../common/ui/NavStarsToggleRow'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { UI_RADIUS_CARD, UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 航海星面板，对应 `activePanel === 'navStars'`。
// 加载/开关/星表簇状态来自 NavStarsStore（@ObjectLink）；长说明收纳于 InfoTipButton ⓘ。

@Component
export struct NavStarsPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink navStarsStore: NavStarsStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSetSetting: (setting: string, value: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  private navStarsSetLabel(key: string): ResourceStr {
    switch (key) {
      case 'AngloAmerican': return '英美航海星'
      case 'French': return '法国航海星'
      case 'British': return '英国航海星'
      case 'Wrinkles': return '19世纪英国航海星'
      case 'Russian': return '俄罗斯航海星'
      case 'USSRAvia': return '苏联航空星'
      case 'USSRSpace': return '苏联航天星'
      case 'German': return '德国航海星'
      case 'GeminiAPS': return 'Gemini 对准星'
      case 'MeadeLX200': return 'Meade LX200 对准星'
      case 'MeadeETX': return 'Meade ETX 对准星'
      case 'MeadeAS494': return 'Meade 494 对准星'
      case 'MeadeAS497': return 'Meade 497 对准星'
      case 'CelestronNS': return 'Celestron 对准星'
      case 'Apollo': return 'Apollo 导航星'
      case 'SkywatcherSS': return 'Sky-Watcher 对准星'
      case 'VixenSB': return 'Vixen 对准星'
      case 'ArgoNavis': return 'Argo Navis 对准星'
      case 'OrionIS': return 'Orion 对准星'
      case 'SkyCommander': return 'Sky Commander 对准星'
      default: return key
    }
  }

  private navTipText(): string {
    const key: string = 'nav_stars_hint'
    const base: string = I18n.t(key)
    const extra = this.navStarsStore.navStarsSetDescription.replace(/<[^>]+>/g, '').trim()
    return extra.length > 0 ? (base + '\n' + extra) : base
  }

  build() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            Text(I18n.t('panel_nav_stars')).fontSize(panelFontSize(15, this.readableUi))
              .fontWeight(FontWeight.Medium).fontColor(this.c.textStrong)
            InfoTipButton({
              title: I18n.t('panel_nav_stars'),
              tip: this.navTipText()
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          if (this.navStarsStore.navStarsLoading) { LoadingProgress().width(20).height(20).color(this.c.accent) }
          Toggle({ type: ToggleType.Switch, isOn: this.navStarsStore.navStarsEnabled })
            .selectedColor(this.c.accent)
            .enabled(!this.navStarsStore.navStarsLoading)
            .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
        }
          .width('100%')
          .constraintSize({ minHeight: this.ch(46) })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.navStarsStore.navStarsStatus.length > 0) {
          Text(this.navStarsStore.navStarsStatus).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.warning).width('100%').padding({ left: 6, right: 6 })
        }

        Column({ space: 8 }) {
          Row() {
            Text(I18n.t('nav_stars_set')).fontSize(panelFontSize(12, this.readableUi)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
            Text(this.navStarsStore.navStarsCount.toString() + ' ' + I18n.t('nav_stars_count')).fontSize(panelFontSize(11, this.readableUi)).fontColor(this.c.accent)
          }.width('100%')
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.navStarsStore.navStarsSetKeys, (key: string) => {
                Text(this.navStarsSetLabel(key)).fontSize(panelFontSize(11, this.readableUi))
                  .fontWeight(this.navStarsStore.navStarsSetKey === key ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor(this.navStarsStore.navStarsSetKey === key ? this.c.onAccent : this.c.sub)
                  .padding({ left: 11, right: 11, top: 8, bottom: 8 })
                  .backgroundColor(this.navStarsStore.navStarsSetKey === key ? this.c.accent : this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
                  .onClick(() => { this.onSetSetting('set', key) })
              }, (key: string) => key)
            }.padding({ left: 1, right: 2 })
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }
          .width('100%')
          .padding(12)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        NavStarsToggleRow({ label: I18n.t('nav_stars_highlight'), isOn: this.navStarsStore.navStarsHighlight, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('highlightWhenVisible', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_limit_info'), isOn: this.navStarsStore.navStarsLimitInfo, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('limitInfo', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_upper_limb'), isOn: this.navStarsStore.navStarsUpperLimb, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('upperLimb', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_tabulated'), isOn: this.navStarsStore.navStarsTabulated, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('tabulatedDisplay', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_extra_decimals'), isOn: this.navStarsStore.navStarsExtraDecimals, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('extraDecimals', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_utc'), isOn: this.navStarsStore.navStarsUseUtc, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('useUtc', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_startup'), isOn: this.navStarsStore.navStarsStartup, canToggle: !this.navStarsStore.navStarsLoading, onToggle: (v: boolean) => { this.onSetSetting('enableAtStartup', v ? '1' : '0') } })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
