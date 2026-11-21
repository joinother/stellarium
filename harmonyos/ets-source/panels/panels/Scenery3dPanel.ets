import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { Scenery3dItem } from '../../pages/StellariumTypes'
import { I18n } from '../../pages/I18n'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import { SceneryStore } from '../../state/SceneryStore'
import { resourceText } from '../../common/derive/labels'

// 三维地景面板，对应 `activePanel === 'scenery3d'`。
// 列表/加载态来自 SceneryStore（@ObjectLink）；启用开关与选中场景回调注入宿主；
// 详细作者/版权/文件路径信息默认折叠至每张卡片的「详情 ▾」，保持卡片清爽可读。

@Component
export struct Scenery3dPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink sceneryStore: SceneryStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private expandedId: string = ''
  onToggleEnabled: (enabled: boolean) => void = () => {}
  onSelectScene: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private fs(base: number): number { return uiFontSize(base, this.readableUi, this.uiFontScale) }
  private ch(base: number): number { return uiControlHeight(base, this.readableUi, this.controlScale) }

  build() {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            Text(I18n.pluginName('Scenery3d'))
              .fontSize(this.fs(15)).fontColor(this.c.textStrong).fontWeight(FontWeight.Medium)
            InfoTipButton({
              title: I18n.pluginName('Scenery3d'),
              tip: '在星图中加载三维历史遗迹与建筑模型，真实还原地面遮挡、日照光影与方位对准。开启后点下方场景即可切换。'
            })
          }.layoutWeight(1).alignItems(VerticalAlign.Center)
          Toggle({ type: ToggleType.Switch, isOn: this.sceneryStore.scenery3dEnabled })
            .selectedColor(this.c.accent)
            .onChange((enabled: boolean) => { this.onToggleEnabled(enabled) })
        }
          .width('100%')
          .constraintSize({ minHeight: this.ch(46) })
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)

        if (this.sceneryStore.scenery3dLoading && this.sceneryStore.scenery3dItems.length === 0) {
          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color(this.c.accent)
            Text(I18n.t('msg_loading')).fontSize(this.fs(12)).fontColor(this.c.sub)
          }.width('100%').height(48).justifyContent(FlexAlign.Center)
        }
        if (this.sceneryStore.scenery3dItems.length === 0 && !this.sceneryStore.scenery3dLoading) {
          Text('当前没有可用的三维地景资源')
            .fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').textAlign(TextAlign.Center).padding(18)
            .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
        }
        ForEach(this.sceneryStore.scenery3dItems, (scene: Scenery3dItem) => {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text(scene.name.length > 0 ? scene.name : scene.id)
                .fontSize(this.fs(14)).fontColor(this.c.textStrong).fontWeight(FontWeight.Medium)
                .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (scene.current === true) {
                Text('当前使用').fontSize(this.fs(10.5)).fontColor(this.c.onAccent)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .backgroundColor(this.c.accent).borderRadius(UI_RADIUS_PILL)
              }
              if (this.sceneryStore.scenery3dLoadingId === scene.id) {
                LoadingProgress().width(16).height(16).color(this.c.accent)
              }
            }.width('100%').alignItems(VerticalAlign.Center)

            Text(resourceText(scene.description, I18n.t('resource_not_provided')))
              .fontSize(this.fs(11.5)).fontColor(this.c.sub).width('100%')
              .maxLines(this.expandedId === scene.id ? 6 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })

            Row({ space: 8 }) {
              Button(scene.current === true ? '重新加载场景' : '切换到此场景')
                .fontSize(this.fs(11.5))
                .fontColor(scene.current === true ? this.c.text : this.c.onAccent)
                .backgroundColor(scene.current === true ? this.c.soft : this.c.accent)
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(34) })
                .padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onSelectScene(scene.id) })
              Blank()
              Text(this.expandedId === scene.id ? '收起详情 ▴' : '作者与来源 ▾')
                .fontSize(this.fs(11)).fontColor(this.c.accent)
                .padding({ left: 6, right: 4, top: 6, bottom: 6 })
                .onClick(() => {
                  this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                    this.expandedId = this.expandedId === scene.id ? '' : scene.id
                  })
                })
            }.width('100%').alignItems(VerticalAlign.Center)

            if (this.expandedId === scene.id) {
              Column({ space: 3 }) {
                Row().width('100%').height(0.5).backgroundColor(this.c.border).margin({ bottom: 2 })
                Text(I18n.t('resource_author') + '：' + resourceText(scene.author, I18n.t('resource_not_provided'))
                  + ' · ' + I18n.t('resource_license') + '：' + resourceText(scene.copyright, I18n.t('resource_not_provided')))
                  .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%')
                if (scene.planet || scene.landscape || scene.modelScenery) {
                  Text((scene.planet ? '星体：' + scene.planet : '') + (scene.landscape ? ' · 地景：' + scene.landscape : '') + (scene.modelScenery ? ' · 模型：' + scene.modelScenery : ''))
                    .fontSize(this.fs(10.5)).fontColor(this.c.tertiary).width('100%')
                }
                if (scene.source) {
                  Text(I18n.t('resource_source') + '：' + scene.source).fontSize(this.fs(10.5)).fontColor(this.c.tertiary).width('100%')
                }
              }.width('100%').transition(uiFadeUpTransition())
            }
          }
            .width('100%')
            .padding(12)
            .backgroundColor(scene.current === true ? this.c.accentSoft : this.c.bg)
            .border({ width: 0.6, color: scene.current === true ? this.c.accent : this.c.border })
            .borderRadius(UI_RADIUS_CARD)
        }, (scene: Scenery3dItem) => scene.id)
      }.width('100%').padding({ left: 8, right: 8, top: 8, bottom: 16 })
  }
}
