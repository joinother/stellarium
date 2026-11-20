import { common } from '@kit.AbilityKit'
import { formBindingData, formProvider } from '@kit.FormKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import {
  CardInstanceConfig,
  SUPPORTED_EDIT_PLANETS,
  defaultCardConfig,
  planetSymbol,
  planetZhName
} from './AstronomyCardData'
import {
  readFormConfig,
  readFormKind,
  readFormTextColor,
  resolveCardDataForConfig,
  writeFormConfig
} from './FormStoreHelper'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyFormEditPage'
const ACCENT_BLUE: string = '#0A59F7'

interface OptionChoice {
  value: string
  label: string
}

const THEME_CHOICES: OptionChoice[] = [
  { value: 'sky', label: '实时天穹' },
  { value: 'deep', label: '深空极简' }
]

const LABEL_CHOICES: OptionChoice[] = [
  { value: 'name', label: '中文名称' },
  { value: 'symbol', label: '天文符号 ♃' }
]

const OVERFLOW_CHOICES: OptionChoice[] = [
  { value: 'auto', label: '自动与点击' },
  { value: 'tap', label: '仅点击触发' },
  { value: 'off', label: '关闭破框' }
]

@Entry
@Component
struct SkyFormEditPage {
  @State planetMode: string = 'follow'
  @State themeStyle: string = 'sky'
  @State labelStyle: string = 'name'
  @State overflowMode: string = 'auto'
  @State formKind: string = 'sky_window_card'
  @State statusTip: string = ''

  private formId: string = ''
  private previewFormId: string = ''
  private editContext: common.FormEditExtensionContext | undefined = undefined

  aboutToAppear(): void {
    const shared = this.getUIContext().getSharedLocalStorage()
    if (shared !== undefined) {
      this.formId = shared.get<string>('formId') ?? ''
      this.previewFormId = shared.get<string>('previewFormId') ?? ''
      this.editContext = shared.get<common.FormEditExtensionContext>('context')
    }
    if (this.editContext !== undefined && this.formId.length > 0) {
      this.formKind = readFormKind(this.editContext, this.formId)
      const cfg = readFormConfig(this.editContext, this.formId)
      this.planetMode = cfg.planetMode
      this.themeStyle = cfg.themeStyle
      this.labelStyle = cfg.labelStyle
      this.overflowMode = cfg.overflowMode
    }
  }

  private showPlanetSection(): boolean {
    return this.formKind !== 'solar_system_card'
  }

  private showThemeSection(): boolean {
    return this.formKind !== 'floating_orb_card'
  }

  private showPlanetLabelSection(): boolean {
    return this.formKind === 'sky_window_card' || this.formKind === 'celestial_events_card'
  }

  private currentConfig(): CardInstanceConfig {
    const cfg = defaultCardConfig()
    cfg.planetMode = this.planetMode
    cfg.themeStyle = this.themeStyle
    cfg.labelStyle = this.labelStyle
    cfg.overflowMode = this.overflowMode
    return cfg
  }

  private applyConfig(): void {
    if (this.editContext === undefined) return
    const cfg = this.currentConfig()
    if (this.formId.length > 0) {
      writeFormConfig(this.editContext, this.formId, cfg)
    }
    const cardData = resolveCardDataForConfig(this.editContext, cfg, Date.now())
    const savedColor = readFormTextColor(this.editContext, this.formId)
    if (savedColor.length > 0) {
      cardData['textColor'] = savedColor
    }
    const binding = formBindingData.createFormBindingData(cardData)

    const pushUpdate = (targetId: string): void => {
      if (targetId.length === 0) return
      try {
        formProvider.updateForm(targetId, binding).catch((error: BusinessError) => {
          hilog.warn(DOMAIN, TAG, 'updateForm failed id=%{public}s code=%{public}d', targetId, error.code)
        })
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'updateForm sync err: %{public}s', String(error))
      }
    }

    pushUpdate(this.formId)
    pushUpdate(this.previewFormId)
    this.statusTip = this.formKind === 'solar_system_card'
      ? '已应用 · 太阳系仪'
      : ('已应用 · ' + planetZhName(this.planetMode))
  }

  private planetDisplayName(id: string): string {
    return id === 'follow' ? '跟随星图' : planetZhName(id)
  }

  private planetGlyph(id: string): string {
    if (id === 'follow') return '✦'
    if (id === 'Sun') return '☉'
    return planetSymbol(id)
  }

  @Builder
  sectionSegmentedRow(title: string, choices: OptionChoice[], selectedValue: string, onPick: (val: string) => void) {
    Column({ space: 8 }) {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(choices, (choice: OptionChoice) => {
          Row() {
            Text(choice.label)
              .fontSize(13)
              .lineHeight(18)
              .fontWeight(selectedValue === choice.value ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(selectedValue === choice.value ? '#FFFFFF' : $r('sys.color.font_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .height(38)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(selectedValue === choice.value ? ACCENT_BLUE : $r('sys.color.comp_background_tertiary'))
          .borderRadius(12)
          .onClick(() => {
            onPick(choice.value)
            this.applyConfig()
          })
        }, (choice: OptionChoice) => choice.value)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor($r('sys.color.comp_background_secondary'))
    .borderRadius(16)
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        // Section 1: Uniform 3x3 Celestial World Grid (exact equal width & 38vp height!)
        if (this.showPlanetSection()) {
        Column({ space: 8 }) {
          Row() {
            Text('观测天体')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_secondary'))
            Blank()
            Text(this.statusTip.length > 0 ? this.statusTip : '每张卡片可独立绑定')
              .fontSize(11)
              .fontColor(this.statusTip.length > 0 ? ACCENT_BLUE : $r('sys.color.font_tertiary'))
          }
          .width('100%')

          Grid() {
            ForEach(SUPPORTED_EDIT_PLANETS, (planetId: string) => {
              GridItem() {
                Row({ space: 4 }) {
                  Text(this.planetGlyph(planetId))
                    .fontSize(13)
                    .lineHeight(16)
                    .fontColor(this.planetMode === planetId ? '#FFFFFF' : $r('sys.color.font_secondary'))
                  Text(this.planetDisplayName(planetId))
                    .fontSize(13)
                    .lineHeight(16)
                    .fontWeight(this.planetMode === planetId ? FontWeight.Medium : FontWeight.Regular)
                    .fontColor(this.planetMode === planetId ? '#FFFFFF' : $r('sys.color.font_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .height(38)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .padding({ left: 6, right: 6 })
                .backgroundColor(this.planetMode === planetId ? ACCENT_BLUE : $r('sys.color.comp_background_tertiary'))
                .borderRadius(12)
                .onClick(() => {
                  this.planetMode = planetId
                  this.applyConfig()
                })
              }
            }, (planetId: string) => planetId)
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(8)
          .rowsGap(8)
          .width('100%')
          .height(130)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 12 })
        .backgroundColor($r('sys.color.comp_background_secondary'))
        .borderRadius(16)
        }

        // Section 2: Sky Theme Style (framed cards only)
        if (this.showThemeSection()) {
          this.sectionSegmentedRow('视觉风格', THEME_CHOICES, this.themeStyle, (val: string) => {
            this.themeStyle = val
          })
        }

        // Section 3: Planet Label Style (cards with planet lists only)
        if (this.showPlanetLabelSection()) {
          this.sectionSegmentedRow('行星标识样式', LABEL_CHOICES, this.labelStyle, (val: string) => {
            this.labelStyle = val
          })
        }

        // Section 4: API 20 Overflow Animation Policy
        this.sectionSegmentedRow('天体破框动效', OVERFLOW_CHOICES, this.overflowMode, (val: string) => {
          this.overflowMode = val
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
