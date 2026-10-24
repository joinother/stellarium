import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { SearchStore } from '../../state/SearchStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// RA/Dec 坐标跳转：两行输入（赤经 / 赤纬）+ 跳转按钮。
//
// 输入文本经 SearchStore（@ObjectLink）读写；跳转经 onGo 交回宿主（解析并下发命令）。
@Component
export struct SearchCoordinateInput {
  @ObjectLink store: SearchStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onGo: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column() {
      Row() {
        Text(I18n.t('s_coord_input')).fontSize(12).fontColor(this.c.sub).layoutWeight(1)
        Text(I18n.t('s_coord_format_hint')).fontSize(10).fontColor(this.c.sub).maxLines(2).textAlign(TextAlign.End)
      }
      .height(32).width('100%').padding({ left: 10, right: 10 }).margin({ top: 10 })
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(I18n.t('view_coord_ra')).fontSize(11).fontColor(this.c.sub).width(64)
          TextInput({ text: this.store.coordInputRA, placeholder: '5.5 / 5h30m' })
            .height(36).layoutWeight(1).fontSize(13).fontColor(this.c.text)
            .placeholderColor(this.c.sub)
            .backgroundColor(this.c.input)
            .border({ width: 1, color: this.c.inputBorder })
            .borderRadius(UI_RADIUS_CONTROL)
            .onChange((v: string) => { this.store.coordInputRA = v })
        }.width('100%')
        Row({ space: 8 }) {
          Text(I18n.t('view_coord_dec')).fontSize(11).fontColor(this.c.sub).width(64)
          TextInput({ text: this.store.coordInputDec, placeholder: '+45.5 / -30d15m' })
            .height(36).layoutWeight(1).fontSize(13).fontColor(this.c.text)
            .placeholderColor(this.c.sub)
            .backgroundColor(this.c.input)
            .border({ width: 1, color: this.c.inputBorder })
            .borderRadius(UI_RADIUS_CONTROL)
            .onChange((v: string) => { this.store.coordInputDec = v })
          Button(I18n.t('s_coord_go'))
            .height(36).fontSize(12).fontColor(this.c.textStrong).backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_CONTROL)
            .padding({ left: 12, right: 12 })
            .onClick(() => { this.onGo() })
        }.width('100%')
      }
      .width('100%').padding({ left: 10, right: 10 }).margin({ bottom: 12 })
    }.width('100%')
  }
}
