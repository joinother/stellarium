import { I18n } from '../../pages/I18n'
import { NavStarsStore } from '../../state/NavStarsStore'
import { NavStarsToggleRow } from '../../common/ui/NavStarsToggleRow'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 航海星面板，对应 `activePanel === 'navStars'`。
//
// 加载/开关/星表簇状态来自 NavStarsStore（@ObjectLink）；设置动作回调注入宿主。
// 星表名翻译助手 navStarsSetLabel 为组件内纯函数，不依赖宿主实例。

@Component
export struct NavStarsPanel {
  @ObjectLink navStarsStore: NavStarsStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop accentColor: string
  onSetSetting: (setting: string, value: string) => void = () => {}

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

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 3 }) {
            Text(I18n.t('panel_nav_stars')).fontSize(15).fontColor(this.textColor).width('100%')
            Text(I18n.t('nav_stars_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.navStarsStore.navStarsLoading) { LoadingProgress().width(20).height(20).color(this.accentColor) }
          Toggle({ type: ToggleType.Switch, isOn: this.navStarsStore.navStarsEnabled })
            .enabled(!this.navStarsStore.navStarsLoading)
            .onChange((v: boolean) => { this.onSetSetting('enabled', v ? '1' : '0') })
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL)
        if (this.navStarsStore.navStarsStatus.length > 0) { Text(this.navStarsStore.navStarsStatus).fontSize(11).fontColor('#FFD59A').width('100%') }
        Row() {
          Text(I18n.t('nav_stars_set')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
          Text(this.navStarsStore.navStarsCount.toString() + ' ' + I18n.t('nav_stars_count')).fontSize(11).fontColor(this.subColor)
        }.width('100%')
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.navStarsStore.navStarsSetKeys, (key: string) => {
              Text(this.navStarsSetLabel(key)).fontSize(10)
                .fontColor(this.navStarsStore.navStarsSetKey === key ? '#FFFFFF' : this.subColor)
                .padding({ left: 9, right: 9, top: 7, bottom: 7 })
                .backgroundColor(this.navStarsStore.navStarsSetKey === key ? this.accentColor : this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSetSetting('set', key) })
            }, (key: string) => key)
          }.padding({ left: 2, right: 2 })
        }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        if (this.navStarsStore.navStarsSetDescription.length > 0) {
          Text(this.navStarsStore.navStarsSetDescription.replace(/<[^>]+>/g, '')).fontSize(10).fontColor(this.subColor)
            .width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        NavStarsToggleRow({ label: I18n.t('nav_stars_highlight'), isOn: this.navStarsStore.navStarsHighlight, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('highlightWhenVisible', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_limit_info'), isOn: this.navStarsStore.navStarsLimitInfo, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('limitInfo', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_upper_limb'), isOn: this.navStarsStore.navStarsUpperLimb, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('upperLimb', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_tabulated'), isOn: this.navStarsStore.navStarsTabulated, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('tabulatedDisplay', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_extra_decimals'), isOn: this.navStarsStore.navStarsExtraDecimals, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('extraDecimals', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_utc'), isOn: this.navStarsStore.navStarsUseUtc, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('useUtc', v ? '1' : '0') } })
        NavStarsToggleRow({ label: I18n.t('nav_stars_startup'), isOn: this.navStarsStore.navStarsStartup, canToggle: !this.navStarsStore.navStarsLoading, textColor: this.textColor, panelColor: this.panelColor, onToggle: (v: boolean) => { this.onSetSetting('enableAtStartup', v ? '1' : '0') } })
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
  }
}
