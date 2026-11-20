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
  readFormTextColor,
  resolveCardDataForConfig,
  writeFormConfig
} from './FormStoreHelper'

const DOMAIN: number = 0xD003
const TAG: string = 'SkyFormEditPage'

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
      const cfg = readFormConfig(this.editContext, this.formId)
      this.planetMode = cfg.planetMode
      this.themeStyle = cfg.themeStyle
      this.labelStyle = cfg.labelStyle
      this.overflowMode = cfg.overflowMode
    }
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
    this.statusTip = '已应用：' + planetZhName(this.planetMode)
  }

  private planetChipText(id: string): string {
    if (id === 'follow') return '跟随星图'
    return planetSymbol(id) + ' ' + planetZhName(id)
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        // Section 1: Multi-instance Planet Binding
        Column({ space: 8 }) {
          Row() {
            Text('观测天体')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.font_primary'))
            Blank()
            Text(this.statusTip.length > 0 ? this.statusTip : '支持多张卡片独立绑定')
              .fontSize(11)
              .fontColor($r('sys.color.font_secondary'))
          }
          .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(SUPPORTED_EDIT_PLANETS, (planetId: string) => {
              Text(this.planetChipText(planetId))
                .fontSize(13)
                .fontWeight(this.planetMode === planetId ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.planetMode === planetId ? '#FFFFFF' : $r('sys.color.font_primary'))
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(this.planetMode === planetId ? '#2864D8' : $r('sys.color.comp_background_tertiary'))
                .borderRadius(18)
                .onClick(() => {
                  this.planetMode = planetId
                  this.applyConfig()
                })
            }, (planetId: string) => planetId)
          }
          .width('100%')
        }
        .width('100%')

        // Section 2: Sky Theme Style
        Column({ space: 8 }) {
          Text('视觉风格')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')

          Row({ space: 8 }) {
            ForEach(THEME_CHOICES, (choice: OptionChoice) => {
              Text(choice.label)
                .fontSize(13)
                .fontWeight(this.themeStyle === choice.value ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.themeStyle === choice.value ? '#FFFFFF' : $r('sys.color.font_primary'))
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 8, bottom: 8 })
                .backgroundColor(this.themeStyle === choice.value ? '#2864D8' : $r('sys.color.comp_background_tertiary'))
                .borderRadius(16)
                .onClick(() => {
                  this.themeStyle = choice.value
                  this.applyConfig()
                })
            }, (choice: OptionChoice) => choice.value)
          }
          .width('100%')
        }
        .width('100%')

        // Section 3: Planet Label Style (Names vs Astronomical Symbols)
        Column({ space: 8 }) {
          Text('行星标识样式')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')

          Row({ space: 8 }) {
            ForEach(LABEL_CHOICES, (choice: OptionChoice) => {
              Text(choice.label)
                .fontSize(13)
                .fontWeight(this.labelStyle === choice.value ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.labelStyle === choice.value ? '#FFFFFF' : $r('sys.color.font_primary'))
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 8, bottom: 8 })
                .backgroundColor(this.labelStyle === choice.value ? '#2864D8' : $r('sys.color.comp_background_tertiary'))
                .borderRadius(16)
                .onClick(() => {
                  this.labelStyle = choice.value
                  this.applyConfig()
                })
            }, (choice: OptionChoice) => choice.value)
          }
          .width('100%')
        }
        .width('100%')

        // Section 4: API 20 Overflow Animation Policy
        Column({ space: 8 }) {
          Text('天体破框动效')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .width('100%')

          Row({ space: 8 }) {
            ForEach(OVERFLOW_CHOICES, (choice: OptionChoice) => {
              Text(choice.label)
                .fontSize(12)
                .fontWeight(this.overflowMode === choice.value ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.overflowMode === choice.value ? '#FFFFFF' : $r('sys.color.font_primary'))
                .textAlign(TextAlign.Center)
                .layoutWeight(1)
                .padding({ top: 8, bottom: 8 })
                .backgroundColor(this.overflowMode === choice.value ? '#2864D8' : $r('sys.color.comp_background_tertiary'))
                .borderRadius(16)
                .onClick(() => {
                  this.overflowMode = choice.value
                  this.applyConfig()
                })
            }, (choice: OptionChoice) => choice.value)
          }
          .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 12, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
  }
}
