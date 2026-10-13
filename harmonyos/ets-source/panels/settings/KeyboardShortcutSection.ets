import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { KeyboardShortcutStore } from '../../state/KeyboardShortcutStore'
import { KeyboardShortcutItem } from '../../common/types/StellariumTypes'

// 设置面板「视图导航」页内的快捷键编辑器：搜索、动作列表、主/备快捷键编辑、保存/恢复。
// 宿主持有 KeyboardShortcutStore 与四个动作回调。
@Component
export struct KeyboardShortcutSection {
  @ObjectLink store: KeyboardShortcutStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop accentColor: string
  @Prop panelColor: string
  @Prop inputColor: string
  @Prop activeSoft: string
  onQuery: (value: string) => void = () => {}
  onSelect: (item: KeyboardShortcutItem) => void = () => {}
  onPrimary: (value: string) => void = () => {}
  onAlternate: (value: string) => void = () => {}
  onSave: () => void = () => {}
  onResetSelected: () => void = () => {}
  onResetAll: () => void = () => {}

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(I18n.t('settings_shortcuts_title')).fontSize(12).fontColor(this.textColor).layoutWeight(1)
        Button(I18n.t('settings_shortcuts_restore_all')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
          .onClick(() => { this.onResetAll() })
      }.width('100%')
      Text(I18n.t('settings_shortcuts_hint')).fontSize(10).fontColor(this.subColor).width('100%').maxLines(3)
      TextInput({ text: this.store.keyboardShortcutQuery, placeholder: I18n.t('settings_shortcuts_search') })
        .fontSize(11).fontColor(this.textColor).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
        .onChange((value: string) => { this.onQuery(value) })
      if (this.store.keyboardShortcutsLoading) {
        LoadingProgress().width(20).height(20).color(this.accentColor)
      } else {
        Scroll() {
          Column({ space: 4 }) {
            ForEach(this.store.keyboardShortcuts, (item: KeyboardShortcutItem) => {
              Row({ space: 6 }) {
                Column({ space: 1 }) {
                  Text(item.text.length > 0 ? item.text : item.id).fontSize(10).fontColor(this.textColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.id + ' · ' + item.group).fontSize(10).fontColor(this.subColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Text(item.shortcut.length > 0 ? item.shortcut : '—').fontSize(10)
                  .fontColor(this.store.keyboardShortcutSelectedId === item.id ? this.accentColor : this.subColor)
              }.width('100%').padding({ left: 8, right: 8, top: 6, bottom: 6 })
                .backgroundColor(this.store.keyboardShortcutSelectedId === item.id ? this.activeSoft : this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL)
                .onClick(() => { this.onSelect(item) })
            }, (item: KeyboardShortcutItem) => item.id)
          }.width('100%')
        }.width('100%').height(180).scrollBar(BarState.Auto)
      }
      if (this.store.keyboardShortcutSelectedId.length > 0) {
        Text(this.store.keyboardShortcutSelectedId).fontSize(10).fontColor(this.subColor).width('100%').maxLines(1)
        TextInput({ text: this.store.keyboardShortcutPrimary, placeholder: I18n.t('settings_shortcuts_primary') })
          .fontSize(11).fontColor(this.textColor).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
          .onChange((value: string) => { this.onPrimary(value) })
        TextInput({ text: this.store.keyboardShortcutAlternate, placeholder: I18n.t('settings_shortcuts_alternate') })
          .fontSize(11).fontColor(this.textColor).backgroundColor(this.inputColor).borderRadius(UI_RADIUS_CONTROL)
          .onChange((value: string) => { this.onAlternate(value) })
        Row({ space: 6 }) {
          Button(I18n.t('settings_shortcuts_save')).fontSize(10).fontColor('#FFFFFF').backgroundColor(this.accentColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1).onClick(() => { this.onSave() })
          Button(I18n.t('settings_shortcuts_restore')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).layoutWeight(1).onClick(() => { this.onResetSelected() })
        }.width('100%')
      }
    }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
      .backgroundColor(this.panelColor).borderRadius(UI_RADIUS_CONTROL).margin({ bottom: 8 })
  }
}
