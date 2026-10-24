import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { BookmarkItem } from '../../pages/MainWindowModels'
import { BookmarkStore } from '../../state/BookmarkStore'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 书签面板：保存当前视图 + 已存书签列表（点击跳转 / 删除）。
//
// 状态经 `BookmarkStore` 以 `@ObjectLink` 订阅，宿主只传入回调与当前选中目标名。
// 列表用 ForEach 内联渲染——参数化 `@Builder` 的参数按值捕获、子树首帧后会冻结。
@Component
export struct BookmarkPanel {
  @ObjectLink store: BookmarkStore
  @Prop selectedName: string
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSaveView: () => void = () => {}
  onGoto: (id: string) => void = () => {}
  onDelete: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.store.draftName, placeholder: I18n.t('c_bookmark_name_hint') })
          .fontSize(13).fontColor(this.c.text).placeholderColor(this.c.sub)
          .backgroundColor(this.c.input).borderRadius(UI_RADIUS_CONTROL)
          .height(36).layoutWeight(1).padding({ left: 10, right: 10 })
          .onChange((v: string) => { this.store.draftName = v })
        Button(I18n.t('btn_save_current_view'))
          .fontSize(12).fontColor(this.c.text)
          .backgroundColor(this.c.softStrong)
          .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
          .onClick(() => { this.onSaveView() })
      }.width('100%')
      if (this.selectedName.length > 0) {
        Row() {
          Text(I18n.t('bookmark_selected_object_hint') + ': ' + this.selectedName)
            .fontSize(12).fontColor(this.c.sub).layoutWeight(1)
          Button(I18n.t('btn_bookmark_object'))
            .fontSize(12).fontColor(this.c.text)
            .backgroundColor(this.c.softStrong)
            .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
            .onClick(() => { this.onSaveView() })
        }.width('100%').margin({ top: 4 })
      }
      if (this.store.loading) {
        Column() {
          Text(I18n.t('c_loading_bookmarks')).fontSize(13).fontColor(this.c.sub)
        }.width('100%').height(80).justifyContent(FlexAlign.Center)
      } else if (this.store.list.length === 0) {
        Column() {
          Text(I18n.t('m_no_bookmarks')).fontSize(14).fontColor(this.c.text).margin({ top: 8 })
          Text(I18n.t('m_save_view_hint')).fontSize(12).fontColor(this.c.tertiary).margin({ top: 6 })
        }.width('100%').height(100).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.store.list, (b: BookmarkItem) => {
              Row() {
                Column() {
                  Text(b.name)
                    .fontSize(14).fontColor(this.c.text).fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text((b.object.length > 0 ? (b.object + ' · ') : '') + 'FOV ' + b.fov.toFixed(1) + '°')
                    .fontSize(11).fontColor(this.c.sub).margin({ top: 2 })
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  .onClick(() => { this.onGoto(b.id) })
                Button(I18n.t('btn_delete'))
                  .fontSize(12).fontColor(this.c.text)
                  .backgroundColor(this.c.softStrong)
                  .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 14, right: 14 })
                  .onClick(() => { this.onDelete(b.id) })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor(this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
              .border({ width: 1, color: this.c.border })
            }, (b: BookmarkItem) => b.id)
          }.width('100%').padding({ left: 2, right: 2 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
      }
    }.width('100%').layoutWeight(1)
  }
}
