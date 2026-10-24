import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { Scenery3dItem } from '../../pages/StellariumTypes'
import { I18n } from '../../pages/I18n'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { SceneryStore } from '../../state/SceneryStore'
import { resourceText } from '../../common/derive/labels'

// 三维地景面板，对应 `activePanel === 'scenery3d'`。
//
// 列表/加载态来自 SceneryStore（@ObjectLink）；启用开关与选中场景回调注入宿主；
// resourceText 直连 common/derive/labels。

@Component
export struct Scenery3dPanel {
  @ObjectLink sceneryStore: SceneryStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onToggleEnabled: (enabled: boolean) => void = () => {}
  onSelectScene: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text(I18n.pluginName('Scenery3d')).fontSize(14).fontColor(this.c.text).fontWeight(FontWeight.Medium)
            Text('保留原版三维场景的介绍、作者、版权和模型来源信息').fontSize(10).fontColor(this.c.sub).maxLines(2)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.sceneryStore.scenery3dEnabled })
            .width(42).height(24)
            .onChange((enabled: boolean) => { this.onToggleEnabled(enabled) })
        }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CONTROL)
        if (this.sceneryStore.scenery3dLoading && this.sceneryStore.scenery3dItems.length === 0) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(this.c.accent)
            Text(I18n.t('msg_loading')).fontSize(11).fontColor(this.c.sub)
          }.width('100%').height(44).justifyContent(FlexAlign.Center)
        }
        if (this.sceneryStore.scenery3dItems.length === 0 && !this.sceneryStore.scenery3dLoading) {
          Text('原版没有可用的三维地景资源').fontSize(11).fontColor(this.c.sub).width('100%').textAlign(TextAlign.Center).padding(16)
        }
        ForEach(this.sceneryStore.scenery3dItems, (scene: Scenery3dItem) => {
          Column({ space: 4 }) {
            Row() {
              Text(scene.name.length > 0 ? scene.name : scene.id).fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (scene.current === true) Text('当前').fontSize(10).fontColor(this.c.accent)
              if (this.sceneryStore.scenery3dLoadingId === scene.id) LoadingProgress().width(16).height(16).color(this.c.accent)
            }.width('100%')
            Text(resourceText(scene.description, I18n.t('resource_not_provided'))).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(I18n.t('resource_author') + ': ' + resourceText(scene.author, I18n.t('resource_not_provided')) + ' · ' + I18n.t('resource_license') + ': ' + resourceText(scene.copyright, I18n.t('resource_not_provided'))).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (scene.planet || scene.landscape || scene.modelScenery) {
              Text((scene.planet ? '星球: ' + scene.planet : '') + (scene.landscape ? ' · 地景: ' + scene.landscape : '') + (scene.modelScenery ? ' · 模型: ' + scene.modelScenery : '')).fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (scene.source) Text(I18n.t('resource_source') + ': ' + scene.source).fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (scene.descriptionSource) Text('介绍文件: ' + scene.descriptionSource).fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 }).backgroundColor(scene.current === true ? this.c.accentSoft : this.c.bg).borderRadius(UI_RADIUS_CONTROL)
            .onClick(() => { this.onSelectScene(scene.id) })
        }, (scene: Scenery3dItem) => scene.id)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 12 })
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).scrollBarWidth(4).scrollBarColor(this.c.scrollbar)
  }
}
