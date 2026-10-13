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
  @Prop cardBorderColor: string
  onSaveView: () => void = () => {}
  onGoto: (id: string) => void = () => {}
  onDelete: (id: string) => void = () => {}

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.store.draftName, placeholder: I18n.t('c_bookmark_name_hint') })
          .fontSize(13).fontColor('#E5FFFFFF').placeholderColor('#99FFFFFF')
          .backgroundColor('rgba(255,255,255,0.06)').borderRadius(UI_RADIUS_CONTROL)
          .height(36).layoutWeight(1).padding({ left: 10, right: 10 })
          .onChange((v: string) => { this.store.draftName = v })
        Button(I18n.t('btn_save_current_view'))
          .fontSize(12).fontColor('#E5FFFFFF')
          .backgroundColor('rgba(107,163,214,0.35)')
          .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
          .onClick(() => { this.onSaveView() })
      }.width('100%')
      if (this.selectedName.length > 0) {
        Row() {
          Text(I18n.t('bookmark_selected_object_hint') + ': ' + this.selectedName)
            .fontSize(12).fontColor('#99FFFFFF').layoutWeight(1)
          Button(I18n.t('btn_bookmark_object'))
            .fontSize(12).fontColor('#E5FFFFFF')
            .backgroundColor('rgba(91,147,191,0.35)')
            .borderRadius(UI_RADIUS_CONTROL).height(36).padding({ left: 14, right: 14 })
            .onClick(() => { this.onSaveView() })
        }.width('100%').margin({ top: 4 })
      }
      if (this.store.loading) {
        Column() {
          Text(I18n.t('c_loading_bookmarks')).fontSize(13).fontColor('#99FFFFFF')
        }.width('100%').height(80).justifyContent(FlexAlign.Center)
      } else if (this.store.list.length === 0) {
        Column() {
          Text(I18n.t('m_no_bookmarks')).fontSize(14).fontColor('#E5FFFFFF').margin({ top: 8 })
          Text(I18n.t('m_save_view_hint')).fontSize(12).fontColor('#CC8FB6FF').margin({ top: 6 })
        }.width('100%').height(100).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.store.list, (b: BookmarkItem) => {
              Row() {
                Column() {
                  Text(b.name)
                    .fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text((b.object.length > 0 ? (b.object + ' · ') : '') + 'FOV ' + b.fov.toFixed(1) + '°')
                    .fontSize(11).fontColor('#99FFFFFF').margin({ top: 2 })
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  .onClick(() => { this.onGoto(b.id) })
                Button(I18n.t('btn_delete'))
                  .fontSize(12).fontColor('#E5FFFFFF')
                  .backgroundColor('rgba(255,255,255,0.10)')
                  .borderRadius(UI_RADIUS_CONTROL).height(32).padding({ left: 14, right: 14 })
                  .onClick(() => { this.onDelete(b.id) })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
              .backgroundColor('rgba(255,255,255,0.04)')
              .borderRadius(UI_RADIUS_CONTROL)
              .border({ width: 1, color: this.cardBorderColor })
            }, (b: BookmarkItem) => b.id)
          }.width('100%').padding({ left: 2, right: 2 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor('#33FFFFFF')
      }
    }.width('100%').layoutWeight(1)
  }
}
