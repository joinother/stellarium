import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { LocSearchItem } from '../../pages/StellariumTypes'
import { LocationStore } from '../../state/LocationStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { tintMatrixFor } from '../../common/ui/IconTint'

// 本组件职责：位置面板的离线地点搜索框 + 结果列表。
//
//   - 搜索簇字段（locSearchQuery / locSearchResults / locSearching / locSearchDebounce）
//     与 formatDegrees 随 @ObjectLink store 实时刷新；
//   - 分块扫描（searchLocations）、选中落地（selectSearchLocation）走原生桥，由宿主完成；
//   - 结果行的「省·国」上下文串依赖宿主的翻译缓存，以 contextOf 回调注入；
//   - 输入框会把草稿名同步给位置选择器，以 onNameDraft 回注。
@Component
export struct LocationSearchPanel {
  @ObjectLink store: LocationStore
  @State c: ThemeSlots = DEFAULT_SLOTS
  onSearch: (query: string) => void = () => {}
  onNameDraft: (name: string) => void = () => {}
  onInputFocus: () => void = () => {}
  onInputBlur: () => void = () => {}
  contextOf: (item: LocSearchItem) => string = () => ''
  onPickItem: (item: LocSearchItem) => void = () => {}

  // 面板打开即预热归一化索引（分块构建）：用户打完字时通常已经建好，
  // 首次搜索不必再等一遍全表归一化。
  aboutToAppear(): void {
    this.store.warmLocationSearchIndex()
  }

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.store.locSearchQuery, placeholder: I18n.t('loc_search_placeholder') })
          .height(36)
          .fontSize(13)
          .fontColor(this.c.text)
          .placeholderColor(this.c.sub)
          .backgroundColor(this.c.input)
          .border({ width: 1, color: this.c.inputBorder })
          .borderRadius(UI_RADIUS_CONTROL)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.store.locSearchQuery = value
            this.onNameDraft(value.length > 0 ? value : I18n.t('custom_location'))
            clearTimeout(this.store.locSearchDebounce)
            this.store.locSearchDebounce = setTimeout(() => { this.onSearch(value) }, 260)
          })
          .onFocus(() => { this.onInputFocus() })
          .onBlur(() => { this.onInputBlur() })
          .onSubmit(() => {
            clearTimeout(this.store.locSearchDebounce)
            this.onSearch(this.store.locSearchQuery)          })
        if (this.store.locSearching) {
          LoadingProgress().width(18).height(18).color(this.c.accent)
        } else {
          Button() {
             Image($r('app.media.ic_search')).width(16).height(16).supportSvg2(true).colorFilter(tintMatrixFor(this.c.onAccent))
           }
             .width(40)
             .height(36)
             .backgroundColor(this.c.accent)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => {
              clearTimeout(this.store.locSearchDebounce)
              this.onSearch(this.store.locSearchQuery)
            })
        }
      }
        .width('100%')
      if (this.store.locSearchResults.length > 0) {
        Text(I18n.t('loc_search_results')).fontSize(11).fontColor(this.c.sub).width('100%').padding({ left: 2, top: 2 })
        Column({ space: 4 }) {
          ForEach(this.store.locSearchResults, (item: LocSearchItem) => {
            Row() {
              Column() {
                Text(item.displayName ?? item.name).fontSize(12).fontColor(this.c.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                if (this.contextOf(item).length > 0) {
                  Text(this.contextOf(item)).fontSize(10).fontColor(this.c.tertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(this.store.formatDegrees(item.lat, 'N', 'S') + ' / ' + this.store.formatDegrees(item.lon, 'E', 'W'))
                  .fontSize(10).fontColor(this.c.tertiary)
              }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              Image($r('app.media.ic_location')).width(14).height(14).fillColor(this.c.tertiary)
            }
              .width('100%')
              .height(58)
              .padding({ left: 10, right: 10 })
              .backgroundColor(this.c.soft)
              .border({ width: 1, color: this.c.soft })
              .borderRadius(UI_RADIUS_CONTROL)
              .onClick(() => { this.onPickItem(item) })
          }, (item: LocSearchItem) => item.name + item.lat.toString())
        }
          .width('100%')
      } else if (this.store.locSearching) {
        Text(I18n.t('search_catalog_loading')).fontSize(11).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      } else if (this.store.locSearchQuery.trim().length > 0 && !this.store.locSearching) {
        Text(I18n.t('loc_no_results')).fontSize(11).fontColor(this.c.tertiary).width('100%').padding({ left: 2, top: 2 })
      }
    }
      .width('100%')
      .margin({ top: 10 })
  }
}
