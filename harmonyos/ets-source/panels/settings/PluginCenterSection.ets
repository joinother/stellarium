import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { PluginItem } from '../../pages/StellariumTypes'
import { PluginStore } from '../../state/PluginStore'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'
import {
  pluginCategoryFor,
  pluginConciseSummary,
  pluginDesc,
  pluginFeatureRoute,
  pluginZh,
  resourceText
} from '../../common/derive/labels'

interface PluginTabDef {
  id: string
  labelZh: string
  labelEn: string
}

const PLUGIN_CATEGORY_TABS: PluginTabDef[] = [
  { id: 'all', labelZh: '全部可用', labelEn: 'All' },
  { id: 'observe', labelZh: '观测工具', labelEn: 'Observe' },
  { id: 'data', labelZh: '深空数据', labelEn: 'Data' },
  { id: 'advanced', labelZh: '高级创作', labelEn: 'Studio' }
]

// 鸿蒙风格「插件中心」：无嵌套小窗死滚动、按功能分层筛选、卡片精简（开发元信息折叠至详情）、
// 离线禁用与桌面专用模块默认收纳于底部折叠区，全部控件接入全局字体与按钮尺寸缩放。
@Component
export struct PluginCenterSection {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink pluginStore: PluginStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private selectedCategory: string = 'all'
  @State private expandedPluginId: string = ''
  @State private showInactiveModules: boolean = false

  pluginMetaLine: (plugin: PluginItem) => string = () => ''
  pluginFeatureDestination: (id: string) => string = () => ''
  pluginFeatureIsActionable: (id: string) => boolean = () => false
  pluginFeatureActionLabel: (id: string) => string = () => ''
  onRefresh: () => void = () => {}
  onOpenFeature: (id: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private isZh(): boolean {
    return I18n.getLanguage().startsWith('zh')
  }

  private actionablePlugins(): PluginItem[] {
    return this.pluginStore.pluginList.filter((pl: PluginItem) => this.pluginFeatureIsActionable(pl.id))
  }

  private filteredPlugins(): PluginItem[] {
    const active = this.actionablePlugins()
    if (this.selectedCategory === 'all') return active
    return active.filter((pl: PluginItem) => pluginCategoryFor(pl.id) === this.selectedCategory)
  }

  private inactivePlugins(): PluginItem[] {
    return this.pluginStore.pluginList.filter((pl: PluginItem) => !this.pluginFeatureIsActionable(pl.id))
  }

  private categoryBadgeText(id: string): string {
    const cat = pluginCategoryFor(id)
    if (cat === 'observe') return this.isZh() ? '观测' : 'Observe'
    if (cat === 'data') return this.isZh() ? '数据' : 'Data'
    return this.isZh() ? '高级' : 'Tool'
  }

  private inactiveReasonText(id: string): string {
    const kind = pluginFeatureRoute(id).kind
    if (kind === 'network') return this.isZh() ? '需联网 · 离线停用' : I18n.t('plugin_network_disabled')
    if (kind === 'offline') return this.isZh() ? '离线模式未启用' : I18n.t('plugin_offline_disabled')
    return this.isZh() ? '桌面专用 / 规划中' : I18n.t('plugin_background_only')
  }

  private toggleDetails(id: string): void {
    this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
      this.expandedPluginId = this.expandedPluginId === id ? '' : id
    })
  }

  build() {
    Column({ space: 10 }) {
      // 顶部标题与刷新操作（简洁清晰，不堆砌长说明）
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text(this.isZh() ? '插件中心' : I18n.t('i0124'))
            .fontSize(this.fs(15))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
          Text(this.isZh()
            ? ('已就绪 ' + String(this.actionablePlugins().length) + ' 项功能插件 · 点击即可直达使用')
            : (String(this.actionablePlugins().length) + ' ready plugins'))
            .fontSize(this.fs(11))
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button(I18n.t('act_refresh'))
          .fontSize(this.fs(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.c.text)
          .backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(34) })
          .padding({ left: 13, right: 13 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.onRefresh() })
      }
      .width('100%')
      .padding({ left: 2, right: 2, top: 2 })

      // 分类筛选分段条（等宽大按钮，防误触）
      Row({ space: 5 }) {
        ForEach(PLUGIN_CATEGORY_TABS, (tab: PluginTabDef) => {
          Text(this.isZh() ? tab.labelZh : tab.labelEn)
            .fontSize(this.fs(11.5))
            .fontWeight(this.selectedCategory === tab.id ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.selectedCategory === tab.id ? this.c.onAccent : this.c.sub)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .constraintSize({ minHeight: this.ch(34) })
            .padding({ left: 4, right: 4, top: 6, bottom: 6 })
            .backgroundColor(this.selectedCategory === tab.id ? this.c.accent : Color.Transparent)
            .borderRadius(UI_RADIUS_CONTROL)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.selectedCategory = tab.id
            })
        }, (tab: PluginTabDef) => tab.id)
      }
      .width('100%')
      .padding(3)
      .backgroundColor(this.c.soft)
      .borderRadius(UI_RADIUS_CONTROL)

      // 加载中提示
      if (this.pluginStore.pluginListLoading && this.pluginStore.pluginList.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(18).height(18).color(this.c.accent)
          Text(I18n.t('msg_loading')).fontSize(this.fs(12)).fontColor(this.c.sub)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 16, bottom: 16 })
      }

      // 主插件列表（直接参与外部面板流畅单滚动，不再套 height(260) 小窗！）
      Column({ space: 8 }) {
        ForEach(this.filteredPlugins(), (pl: PluginItem) => {
          Column({ space: 8 }) {
            // 第一行：中文名称 + 分类/就绪状态胶囊
            Row({ space: 6 }) {
              Text(pluginZh(pl.name))
                .fontSize(this.fs(14))
                .fontWeight(FontWeight.Medium)
                .fontColor(this.c.textStrong)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.categoryBadgeText(pl.id))
                .fontSize(this.fs(10))
                .fontColor(this.c.sub)
                .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                .backgroundColor(this.c.soft)
                .borderRadius(UI_RADIUS_PILL)

              Text(pl.loaded
                ? (this.isZh() ? '已就绪' : I18n.t('plugin_runtime_loaded'))
                : (this.isZh() ? '按需加载' : I18n.t('plugin_runtime_unloaded')))
                .fontSize(this.fs(10))
                .fontColor(pl.loaded ? this.c.success : this.c.sub)
                .padding({ left: 7, right: 7, top: 3, bottom: 3 })
                .backgroundColor(pl.loaded ? this.c.accentSoft : this.c.soft)
                .borderRadius(UI_RADIUS_PILL)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 第二行：一句话白话用途
            if (pluginConciseSummary(pl.id, resourceText(pl.description, pluginDesc(pl.name))).length > 0) {
              Text(pluginConciseSummary(pl.id, resourceText(pl.description, pluginDesc(pl.name))))
                .fontSize(this.fs(11.5))
                .fontColor(this.c.sub)
                .width('100%')
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }

            // 第三行：主次清晰的操作条（主操作大蓝按钮 + 次级「详情 ▾」折叠按钮）
            Row({ space: 8 }) {
              Button() {
                Text(this.pluginFeatureActionLabel(pl.id))
                  .fontSize(this.fs(12))
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.c.onAccent)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .id('plugin-feature-' + pl.id)
              .backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL)
              .constraintSize({ minHeight: this.ch(36) })
              .layoutWeight(1)
              .padding({ left: 12, right: 12 })
              .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => { this.onOpenFeature(pl.id) })

              Button(this.expandedPluginId === pl.id
                ? (this.isZh() ? '收起 ▴' : 'Less')
                : (this.isZh() ? '详情 ▾' : 'Info'))
                .fontSize(this.fs(11.5))
                .fontColor(this.c.sub)
                .backgroundColor(this.c.soft)
                .border({ width: 0.6, color: this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .constraintSize({ minHeight: this.ch(36) })
                .padding({ left: 12, right: 12 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.toggleDetails(pl.id) })
            }
            .width('100%')

            // 按需展开的「关于插件」开发元信息区（平时隐藏，彻底消除噪音）
            if (this.expandedPluginId === pl.id) {
              Column({ space: 4 }) {
                Text(this.pluginFeatureDestination(pl.id))
                  .fontSize(this.fs(10.5))
                  .fontColor(this.c.text)
                  .width('100%')
                Text(I18n.t('resource_author') + ': ' + resourceText(pl.authors, I18n.t('resource_not_provided')) +
                  ' · ' + I18n.t('resource_license') + ': ' + resourceText(pl.license, I18n.t('resource_not_provided')))
                  .fontSize(this.fs(10.5))
                  .fontColor(this.c.sub)
                  .width('100%')
                if (this.pluginMetaLine(pl).length > 0) {
                  Text(this.pluginMetaLine(pl))
                    .fontSize(this.fs(10))
                    .fontColor(this.c.tertiary)
                    .width('100%')
                }
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL)
              .transition(uiFadeUpTransition())
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 11, bottom: 11 })
          .backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
        }, (pl: PluginItem) => pl.id + '_' + this.selectedCategory)
      }
      .width('100%')

      // 底部折叠区：离线停用 / 桌面专用模块（默认收起，不再污染主列表）
      if (this.inactivePlugins().length > 0) {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text(this.isZh()
              ? ('未启用与桌面专用模块（' + String(this.inactivePlugins().length) + '）')
              : ('Inactive / Desktop Modules (' + String(this.inactivePlugins().length) + ')'))
              .fontSize(this.fs(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.sub)
              .layoutWeight(1)
            Text(this.showInactiveModules ? (this.isZh() ? '收起 ▴' : 'Hide') : (this.isZh() ? '展开 ▾' : 'Show'))
              .fontSize(this.fs(11))
              .fontColor(this.c.accent)
          }
          .width('100%')
          .constraintSize({ minHeight: this.ch(38) })
          .padding({ left: 12, right: 12 })
          .backgroundColor(this.c.soft)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CARD)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => {
            this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
              this.showInactiveModules = !this.showInactiveModules
            })
          })

          if (this.showInactiveModules) {
            Column({ space: 6 }) {
              ForEach(this.inactivePlugins(), (pl: PluginItem) => {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(pluginZh(pl.name))
                      .fontSize(this.fs(12.5))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.text)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.inactiveReasonText(pl.id))
                      .fontSize(this.fs(10))
                      .fontColor(this.c.tertiary)
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .backgroundColor(this.c.soft)
                      .borderRadius(UI_RADIUS_PILL)
                  }
                  .width('100%')
                  Text(pluginConciseSummary(pl.id, resourceText(pl.description, pluginDesc(pl.name))))
                    .fontSize(this.fs(11))
                    .fontColor(this.c.sub)
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 9, bottom: 9 })
                .backgroundColor(this.c.bg)
                .border({ width: 0.5, color: this.c.border })
                .borderRadius(UI_RADIUS_CARD)
              }, (pl: PluginItem) => 'inactive_' + pl.id)
            }
            .width('100%')
            .transition(uiFadeUpTransition())
          }
        }
        .width('100%')
        .margin({ top: 4, bottom: 8 })
      }
    }
    .width('100%')
  }
}
