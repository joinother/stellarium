import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { SkyCultureMakerStore } from '../../state/SkyCultureMakerStore'
import { SkyCultureMakerField, SkyCultureMakerLongField } from './SkyCultureMakerFields'

// 星文化制作器「概览」页。
//
// 字段的写回由宿主回调完成；自动保存经 onEdited 回调交回宿主排程。
// Column space 10，下拉高 38，双列 Row space 8。
@Component
export struct SkyCultureMakerOverview {
  @ObjectLink store: SkyCultureMakerStore
  @Prop subColor: string
  @Prop textColor: string
  @Prop accentColor: string
  @Prop bgColor: string
  @Prop inputColor: string
  @Prop inputBorderColor: string
  onEdited: () => void = () => {}

  build() {
    Column({ space: 10 }) {
      Text(I18n.t('sky_culture_maker_offline_hint')).fontSize(10).lineHeight(15).fontColor(this.subColor).width('100%')
      SkyCultureMakerField({
        label: I18n.t('sky_culture_maker_id'), value: this.store.id, placeholder: 'custom_culture',
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.id = value.toLowerCase().replace(/[^a-z0-9_]/g, '_') },
        onEdited: () => { this.onEdited() }
      })
      SkyCultureMakerField({
        label: I18n.t('sky_culture_maker_name'), value: this.store.name, placeholder: I18n.t('sky_culture_maker_name_hint'),
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.name = value },
        onEdited: () => { this.onEdited() }
      })
      SkyCultureMakerField({
        label: I18n.t('sky_culture_maker_author'), value: this.store.author, placeholder: I18n.t('sky_culture_maker_author_hint'),
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.author = value },
        onEdited: () => { this.onEdited() }
      })
      Row({ space: 8 }) {
        Column({ space: 5 }) {
          Text(I18n.t('sky_culture_maker_license')).fontSize(10).fontColor(this.subColor).width('100%')
          Select([{ value: 'CC0 1.0' }, { value: 'CC BY 4.0' }, { value: 'CC BY-NC 4.0' }, { value: 'CC BY-ND 4.0' }, { value: 'CC BY-NC-ND 4.0' }])
            .selected(Math.max(0, ['CC0 1.0', 'CC BY 4.0', 'CC BY-NC 4.0', 'CC BY-ND 4.0', 'CC BY-NC-ND 4.0'].indexOf(this.store.license)))
            .value(this.store.license).backgroundColor(this.inputColor)
            .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
            .onSelect((_index: number, value: string) => { this.store.license = value; this.onEdited() })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Column({ space: 5 }) {
          Text(I18n.t('sky_culture_maker_classification')).fontSize(10).fontColor(this.subColor).width('100%')
          Select([{ value: 'traditional' }, { value: 'ethnographic' }, { value: 'historical' }, { value: 'single' }, { value: 'comparative' }, { value: 'personal' }])
            .selected(Math.max(0, ['traditional', 'ethnographic', 'historical', 'single', 'comparative', 'personal'].indexOf(this.store.classification)))
            .value(this.store.classification).backgroundColor(this.inputColor)
            .borderRadius(UI_RADIUS_CONTROL).height(38).width('100%')
            .onSelect((_index: number, value: string) => { this.store.classification = value; this.onEdited() })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      SkyCultureMakerField({
        label: I18n.t('sky_culture_maker_region'), value: this.store.region, placeholder: 'Eastern Asia',
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.region = value },
        onEdited: () => { this.onEdited() }
      })
      SkyCultureMakerField({
        label: I18n.t('sky_culture_maker_native_language'), value: this.store.nativeLang, placeholder: 'zh_CN',
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.nativeLang = value },
        onEdited: () => { this.onEdited() }
      })
      Row({ space: 8 }) {
        Column() {
          SkyCultureMakerField({
            label: I18n.t('sky_culture_maker_begin_year'), value: this.store.beginTime, placeholder: '0',
            labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
            onChange: (value: string) => { this.store.beginTime = value.replace(/[^0-9-]/g, '') },
            onEdited: () => { this.onEdited() }
          })
        }.layoutWeight(1)
        Column() {
          SkyCultureMakerField({
            label: I18n.t('sky_culture_maker_end_year'), value: this.store.endTime, placeholder: '0',
            labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
            onChange: (value: string) => { this.store.endTime = value.replace(/[^0-9-]/g, '') },
            onEdited: () => { this.onEdited() }
          })
        }.layoutWeight(1)
      }.width('100%')
      SkyCultureMakerLongField({
        label: I18n.t('sky_culture_maker_introduction'), value: this.store.introduction, placeholder: I18n.t('sky_culture_maker_introduction_hint'),
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.introduction = value },
        onEdited: () => { this.onEdited() }
      })
      SkyCultureMakerLongField({
        label: I18n.t('sky_culture_maker_description'), value: this.store.description, placeholder: I18n.t('sky_culture_maker_description_hint'),
        labelColor: this.subColor, textColor: this.textColor, inputColor: this.inputColor, inputBorderColor: this.inputBorderColor,
        onChange: (value: string) => { this.store.description = value },
        onEdited: () => { this.onEdited() }
      })
    }.width('100%')
  }
}
