import { I18n } from '../../pages/I18n'
import { WutTarget } from '../../pages/StellariumTypes'
import { WutStore } from '../../state/WutStore'
import { ObservingListStore } from '../../state/ObservingListStore'
import { UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'

// 观测列表面板，对应 `activePanel === 'observing'`。
//
// WUT 目标来自 wutStore，观测列表与就绪标志来自 observingListStore，均 @ObjectLink。
// 列表增删/分类切换/刷新/搜索居中/清除全部/打开搜索面板等动作回调注入宿主；
// 文案与显示名由宿主纯助手回注。

@Component
export struct ObservingPanel {
  @ObjectLink wutStore: WutStore
  @ObjectLink observingListStore: ObservingListStore
  @Prop textColor: string
  @Prop subColor: string
  @Prop panelColor: string
  @Prop borderTint: string
  @Prop accentColor: string
  onOpenSearch: () => void = () => {}
  onClearAll: () => void = () => {}
  onSelectCategory: (category: string) => void = () => {}
  onRefreshTargets: () => void = () => {}
  onJumpTarget: (target: WutTarget) => void = () => {}
  onAddTarget: (target: WutTarget) => void = () => {}
  onRemoveTarget: (name: string) => void = () => {}
  onSearchName: (name: string) => void = () => {}
  targetTitleOf: (target: WutTarget) => string = () => ''
  targetSubtitleOf: (target: WutTarget) => string = () => ''
  typeOf: (type: string) => string = (type: string) => type
  displayNameOf: (name: string) => string = (name: string) => name

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(I18n.t('panel_observing_list')).fontSize(15).fontColor(this.textColor).layoutWeight(1)
        if (this.observingListStore.observingListReady) {
          Text(I18n.t('observing_list_saved')).fontSize(10).fontColor(this.subColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Button(I18n.t('dock_search')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
          .onClick(() => { this.onOpenSearch() })
        if (this.observingListStore.observingList.length > 0) {
          Button(I18n.t('clear_all')).fontSize(11).fontColor('#FF6B6B').backgroundColor('rgba(255,107,107,0.12)')
            .borderRadius(UI_RADIUS_PILL).height(26).padding({ left: 10, right: 10 })
            .onClick(() => { this.onClearAll() })
        }
      }.width('100%').padding({ left: 4, right: 4 })
      Text(I18n.t('i0130')).fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 4 }).margin({ top: 2 })
      Row({ space: 6 }) {
        ForEach(['planets', 'stars', 'messier'], (category: string) => {
          Text(category === 'planets' ? I18n.t('s0743') : (category === 'stars' ? I18n.t('s0744') : '梅西耶'))
            .fontSize(10).fontColor(this.wutStore.wutCategory === category ? this.textColor : this.subColor)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.wutStore.wutCategory === category ? this.accentColor : this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSelectCategory(category) })
        }, (category: string) => category)
        Text('').layoutWeight(1)
        Button(I18n.t('observing_refresh')).fontSize(10).fontColor(this.subColor).backgroundColor(this.panelColor)
          .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 9, right: 9 })
          .onClick(() => { this.onRefreshTargets() })
      }.width('100%').padding({ left: 4, right: 4 })
      if (this.wutStore.wutLoading) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(this.accentColor)
          Text(this.wutStore.wutProgress.length > 0 ? this.wutStore.wutProgress : I18n.t('observing_loading')).fontSize(11).fontColor(this.subColor)
        }.width('100%').padding({ left: 8, top: 7, bottom: 7 })
      } else if (this.wutStore.wutTargets.length > 0) {
        ForEach(this.wutStore.wutTargets.slice(0, 5), (target: WutTarget) => {
          Row({ space: 9 }) {
            Column({ space: 2 }) {
              Row({ space: 6 }) {
                Text(this.targetTitleOf(target)).fontSize(13).fontColor(this.textColor).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(this.typeOf(target.type ?? '')).fontSize(10).fontColor(this.subColor).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%')
              if (this.targetSubtitleOf(target).length > 0) {
                Text(this.targetSubtitleOf(target)).fontSize(10).fontColor(this.subColor).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              Text('高度 ' + (target.altitude ?? 0).toFixed(0) + '°  方位 ' + (target.azimuth ?? 0).toFixed(0) + '°  ' + (target.magnitude ?? 0).toFixed(1) + ' 等')
                .fontSize(10).fontColor(this.subColor).width('100%').maxLines(1)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button(I18n.t('btn_center')).fontSize(10).fontColor(this.accentColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(29).padding({ left: 8, right: 8 })
              .onClick(() => { this.onJumpTarget(target) })
            if (this.observingListStore.observingList.includes(target.englishName ?? '')) {
              Text(I18n.t('s0739')).fontSize(10).fontColor(this.accentColor).padding({ left: 5, right: 5, top: 7, bottom: 7 })
            } else {
              Button(I18n.t('s0738')).fontSize(10).fontColor(this.textColor).backgroundColor(this.panelColor)
                .borderRadius(UI_RADIUS_CONTROL).height(29).padding({ left: 9, right: 9 })
                .onClick(() => { this.onAddTarget(target) })
            }
          }.width('100%').padding({ left: 10, right: 8, top: 8, bottom: 8 })
            .backgroundColor(this.panelColor).border({ width: 1, color: this.borderTint }).borderRadius(UI_RADIUS_CONTROL)
        }, (target: WutTarget, index: number) => target.englishName ?? index.toString())
      } else if (this.wutStore.wutHint.length > 0) {
        Text(this.wutStore.wutHint).fontSize(11).fontColor(this.subColor).width('100%').padding({ left: 8, top: 8, bottom: 8 })
      }
      Text(I18n.t('panel_observing_list') + ' (' + this.observingListStore.observingList.length.toString() + ')')
        .fontSize(12).fontColor(this.subColor).width('100%').padding({ left: 4 }).margin({ top: 8 })
      if (!this.observingListStore.observingListReady) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(this.accentColor)
          Text(I18n.t('observing_list_loading')).fontSize(11).fontColor(this.subColor)
        }.width('100%').height(100).justifyContent(FlexAlign.Center)
      } else if (this.observingListStore.observingList.length === 0) {
        Column() {
          Text(I18n.t('obs_list_empty')).fontSize(13).fontColor('#99FFFFFF').margin({ top: 12 })
          Button(I18n.t('dock_search')).fontSize(11).fontColor(this.textColor).backgroundColor(this.panelColor)
            .borderRadius(UI_RADIUS_CONTROL).height(30).padding({ left: 12, right: 12 }).margin({ top: 8 })
            .onClick(() => { this.onOpenSearch() })
        }.width('100%').height(140).justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.observingListStore.observingList, (name: string) => {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(this.displayNameOf(name)).fontSize(14).fontColor('#E5FFFFFF').fontWeight(FontWeight.Medium)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Button(I18n.t('btn_center')).fontSize(11).fontColor('#5B93BF').backgroundColor('rgba(91,147,191,0.18)')
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 10, right: 10 })
              .onClick(() => { this.onSearchName(name) })
            Button(I18n.t('observing_remove')).fontSize(10).fontColor(this.subColor).backgroundColor(this.panelColor)
              .borderRadius(UI_RADIUS_CONTROL).height(28).padding({ left: 8, right: 8 })
              .onClick(() => { this.onRemoveTarget(name) })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor('rgba(255,255,255,0.04)')
          .borderRadius(UI_RADIUS_CONTROL)
          .border({ width: 1, color: this.borderTint })
          .onClick(() => { this.onSearchName(name) })
        }, (name: string) => name)
      }
    }.width('100%').padding({ left: 4, right: 4 })
  }
}
