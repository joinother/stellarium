import { curves, Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { SearchStore } from '../../state/SearchStore'
import { getIcon } from '../../common/ui/ShellIcons'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'

// 搜索输入栏：放大镜 + 输入框。
//
// 文本经 SearchStore（@ObjectLink）读写，因此输入框内容与候选列表共享同一份状态；
// 三个交互（输入 / 回车 / 聚焦）经回调交回宿主，宿主负责排程建议、发起搜索与面板高度调整。
@Component
export struct SearchBar {
  @ObjectLink store: SearchStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onInput: (value: string) => void = () => {}
  onSubmit: (text: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Row({ space: 8 }) {
      Image(getIcon('search', false))
        .width(18).height(18).fillColor(this.c.iconTertiary)
      TextInput({ text: this.store.searchText, placeholder: I18n.t('i0063') })
        .fontSize(14)
        .fontColor(this.c.text)
        .placeholderColor(this.c.sub)
        .placeholderFont({ size: 14 })
        .layoutWeight(1)
        .maxLines(1)
        .caretStyle({ color: this.c.accent })
        .borderColor(Color.Transparent)
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.store.searchText = value
          this.onInput(value)
        })
        .onFocus(() => { this.onInputFocus() })
        .onBlur(() => { this.onInputBlur() })
        .onSubmit(() => {
          if (this.store.searchText.length > 0) {
            this.onSubmit(this.store.searchText)
          }
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.c.mediaOverlay)
    .backdropBlur(35)
    .border({ width: 0.5, color: this.c.soft })
    .borderRadius(UI_RADIUS_PANEL)
    .shadow({ radius: 16, color: this.c.shadowSoft, offsetX: 0, offsetY: 6 })
    .animation({ duration: 260, curve: curves.springMotion(0.48, 0.90) })
  }
}
