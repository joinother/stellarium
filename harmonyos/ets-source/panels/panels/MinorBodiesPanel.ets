// 太阳系小天体与彗星离线管理面板（SolarSystemEditor 插件原生鸿蒙界面）。
// 支持按亮度排序浏览已加载彗星/小行星/矮行星/外海王星天体、一键导入内置千颗彗星库（ssystem_1000comets.ini）、
// 离线解析 MPC 单行轨道根数并一键在星图中定位。
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { MinorBodiesStore, MPC_MIRROR_PACKS, MpcMirrorPackSpec } from '../../state/MinorBodiesStore'
import { MinorBodyItem } from '../../common/types/StellariumTypes'
import { OFFLINE_APPGALLERY_BUILD } from '../../common/types/MainWindowModels'
import { UI_OPTION_ANIMATION_MS, UI_RADIUS_CARD, UI_RADIUS_CONTROL, UI_RADIUS_PILL, UI_RADIUS_TAG } from '../../common/ui/UiTokens'
import { uiFadeUpTransition } from '../../common/ui/UiMotion'
import { InfoTipButton } from '../../common/ui/InfoTipButton'
import { uiControlHeight, uiFontSize } from '../../common/ui/UiTypography'

interface MinorCatTab {
  id: string
  label: string
}

interface Real3dBodyShowcase {
  key: string
  label: string
  searchName: string
}

const REAL_3D_BODY_SHOWCASE: Real3dBodyShowcase[] = [
  { key: 'vesta', label: '灶神星 Vesta', searchName: 'Vesta' },
  { key: 'phobos', label: '火卫一 Phobos', searchName: 'Phobos' },
  { key: 'deimos', label: '火卫二 Deimos', searchName: 'Deimos' },
  { key: 'halley', label: '哈雷彗星', searchName: '1P/Halley (1986)' },
  { key: '67p', label: '67P 彗星', searchName: '67P/Churyumov-Gerasimenko' },
  { key: 'ida', label: '爱达 243 Ida', searchName: 'Ida' },
  { key: 'gaspra', label: '加斯普拉 951', searchName: 'Gaspra' },
  { key: 'hyperion', label: '土卫七 Hyperion', searchName: 'Hyperion' }
]

const MINOR_CATS: MinorCatTab[] = [
  { id: 'all', label: '全部' },
  { id: 'comet', label: '彗星' },
  { id: 'asteroid', label: '小行星' },
  { id: 'dwarf', label: '矮行星' },
  { id: 'tno', label: '外海王星' }
]

@Component
export struct MinorBodiesPanel {
  @StorageProp('stellariumReadableUi') readableUi: boolean = false
  @StorageProp('stellariumUiFontScale') uiFontScale: number = 1.0
  @StorageProp('stellariumControlScale') controlScale: number = 1.0
  @ObjectLink store: MinorBodiesStore
  @Prop onlineMirrorAllowed: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private importExpanded: boolean = false
  @State private mpcKind: string = 'comet'
  @State private mpcLineText: string = ''

  onLocateObject: (englishName: string) => void = () => {}
  onInspect3dModel: (englishName: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private fs(base: number): number {
    return uiFontSize(base, this.readableUi, this.uiFontScale)
  }

  private ch(base: number): number {
    return uiControlHeight(base, this.readableUi, this.controlScale)
  }

  private catCount(id: string): number {
    if (id === 'comet') return this.store.countComet
    if (id === 'asteroid') return this.store.countAsteroid
    if (id === 'dwarf') return this.store.countDwarf
    if (id === 'tno') return this.store.countTno
    return this.store.totalCount
  }

  private formatPeriod(days: number): string {
    if (!Number.isFinite(days) || days <= 0) return '非周期/双曲线'
    if (days >= 365.25) return (days / 365.25).toFixed(1) + ' 年'
    return days.toFixed(0) + ' 天'
  }

  private confirmReset(): void {
    this.getUIContext().showAlertDialog({
      title: '恢复默认小天体目录',
      message: '将移除您导入的额外彗星与 MPC 轨道根数，恢复为应用默认小天体配置。',
      autoCancel: true,
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '恢复默认',
        fontColor: '#D9534F',
        action: () => { this.store.resetDefault() }
      }
    })
  }

  build() {
    Column({ space: 10 }) {
      // 标题栏 + 刷新
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Row({ space: 6 }) {
            Text('太阳系小天体目录')
              .fontSize(this.fs(15))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.textStrong)
            InfoTipButton({
              title: '离线小天体与彗星管理',
              tip: '全程离线运行，由 SolarSystemEditor 插件驱动。支持按当前视星等排序检索已加载的彗星、小行星与矮行星，一键导入随包内置的千颗彗星库（ssystem_1000comets.ini），或粘贴 MPC 单行轨道根数离线添加新发现彗星。'
            })
          }.alignItems(VerticalAlign.Center)
          Text('已加载 ' + String(this.store.totalCount) + ' 颗（彗星 ' + String(this.store.countComet) + ' · 小行星 ' + String(this.store.countAsteroid) + '）')
            .fontSize(this.fs(11))
            .fontColor(this.c.sub)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Button('刷新')
          .id('minor-bodies-refresh-btn')
          .fontSize(this.fs(12))
          .fontColor(this.c.text)
          .backgroundColor(this.c.bg)
          .border({ width: 0.6, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(34) })
          .padding({ left: 12, right: 12 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.store.load() })
      }.width('100%').alignItems(VerticalAlign.Center)

      // 真实 3D 探测器形态小天体速览（点击即定位并展开可旋转 3D 实测模型）
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text('真实 3D 探测器形态模型 · 旋转查看')
            .fontSize(this.fs(12))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.c.textStrong)
            .layoutWeight(1)
          Text('15 颗内置')
            .fontSize(this.fs(10.5))
            .fontColor(this.c.accent)
            .backgroundColor(this.c.accentSoft)
            .borderRadius(UI_RADIUS_TAG)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }.width('100%').alignItems(VerticalAlign.Center)

        Scroll() {
          Row({ space: 6 }) {
            ForEach(REAL_3D_BODY_SHOWCASE, (item: Real3dBodyShowcase) => {
              Button(item.label)
                .id('minor-bodies-3d-' + item.key)
                .fontSize(this.fs(11))
                .fontColor(this.c.accent)
                .backgroundColor(this.c.accentSoft)
                .border({ width: 0.6, color: this.c.accent })
                .borderRadius(UI_RADIUS_PILL)
                .constraintSize({ minHeight: this.ch(30) })
                .padding({ left: 10, right: 10 })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .onClick(() => { this.onInspect3dModel(item.searchName) })
            }, (item: Real3dBodyShowcase) => item.key)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .padding(10)
      .backgroundColor(this.c.rowBg)
      .border({ width: 0.6, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)

      // 离线导入与管理工具卡
      Column({ space: 8 }) {
        if (this.store.precisionAsteroidsAvailable) {
          Row({ space: 6 }) {
            Text('✓ 离线精密历表已激活')
              .fontSize(this.fs(10)).fontColor(this.c.accent).fontWeight(FontWeight.Medium)
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.c.accentSoft).borderRadius(UI_RADIUS_TAG)
            Text('谷神星 / 智神星 / 婚神星 / 灶神星 300 年精密轨道')
              .fontSize(this.fs(10.5)).fontColor(this.c.sub).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }.width('100%').alignItems(VerticalAlign.Center)
        }
        Row({ space: 8 }) {
          if (this.store.bundledCometsAvailable) {
            Button(this.store.busy && this.store.mirrorSyncingPack.length === 0 ? '导入中…' : '导入千颗彗星')
              .id('minor-bodies-import-comets-btn')
              .fontSize(this.fs(12))
              .fontWeight(FontWeight.Medium)
              .fontColor(this.c.onAccent)
              .backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL)
              .constraintSize({ minHeight: this.ch(36) })
              .layoutWeight(1)
              .enabled(!this.store.busy)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => { this.store.importBundledComets() })
          }
          Button(this.importExpanded ? '收起 MPC' : 'MPC 手动导入')
            .id('minor-bodies-mpc-toggle-btn')
            .fontSize(this.fs(12))
            .fontColor(this.c.text)
            .backgroundColor(this.c.soft)
            .border({ width: 0.5, color: this.c.border })
            .borderRadius(UI_RADIUS_CONTROL)
            .constraintSize({ minHeight: this.ch(36) })
            .padding({ left: 12, right: 12 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => {
              this.getUIContext().animateTo({ duration: UI_OPTION_ANIMATION_MS, curve: Curve.EaseOut }, () => {
                this.importExpanded = !this.importExpanded
              })
            })
          Button('重置')
            .fontSize(this.fs(11.5))
            .fontColor(this.c.sub)
            .backgroundColor(this.c.soft)
            .borderRadius(UI_RADIUS_CONTROL)
            .constraintSize({ minHeight: this.ch(36) })
            .padding({ left: 10, right: 10 })
            .enabled(!this.store.busy)
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.confirmReset() })
        }.width('100%')

        // 阿里云国内镜像实时同步（skyinstrument.cn，只读静态 GET + SHA-256 校验，不上传任何个人信息）
        if (!OFFLINE_APPGALLERY_BUILD) {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('阿里云国内镜像 · MPC 实时目录')
                .fontSize(this.fs(11.5)).fontWeight(FontWeight.Medium).fontColor(this.c.text).layoutWeight(1)
              InfoTipButton({
                title: '国内镜像安全同步说明',
                tip: '通过自有境内镜像 skyinstrument.cn 静态获取国际小行星中心（MPC）每日更新的彗星与小行星轨道。「最新可观测彗星」每 24 小时或云端日历推送新彗星预警时也会在后台静默校验更新（哈希未变自动跳过）；其余小行星目录按需点选同步。写入前均核验 manifest.json 与 SHA-256 哈希，不上传经纬度、搜索词或设备标识。'
              })
            }.width('100%').alignItems(VerticalAlign.Center)

            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(MPC_MIRROR_PACKS, (pack: MpcMirrorPackSpec) => {
                Button(this.store.mirrorSyncingPack === pack.key ? '同步中…' : pack.label)
                  .id('minor-bodies-mirror-' + pack.key)
                  .fontSize(this.fs(11))
                  .fontColor(this.store.mirrorSyncingPack === pack.key ? this.c.onAccent : this.c.accent)
                  .backgroundColor(this.store.mirrorSyncingPack === pack.key ? this.c.accent : this.c.accentSoft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .constraintSize({ minHeight: this.ch(32) })
                  .width('48.5%')
                  .margin({ bottom: 6 })
                  .padding({ left: 8, right: 8 })
                  .enabled(!this.store.busy)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { void this.store.syncMirrorPack(pack.key, this.onlineMirrorAllowed) })
              }, (pack: MpcMirrorPackSpec) => pack.key)
            }.width('100%')

            if (this.store.mirrorStatusText.length > 0) {
              Text(this.store.mirrorStatusText)
                .fontSize(this.fs(10.5)).fontColor(this.c.sub).width('100%').lineHeight(16)
            }
          }
          .width('100%').padding({ left: 10, right: 10, top: 8, bottom: 6 })
          .backgroundColor(this.c.soft).borderRadius(UI_RADIUS_CONTROL)
        }

        if (this.importExpanded) {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              ForEach(['comet', 'asteroid'], (kind: string) => {
                Text(kind === 'comet' ? 'MPC 彗星单行格式' : 'MPC 小行星单行格式')
                  .fontSize(this.fs(11))
                  .fontColor(this.mpcKind === kind ? this.c.onAccent : this.c.sub)
                  .textAlign(TextAlign.Center)
                  .layoutWeight(1)
                  .constraintSize({ minHeight: this.ch(32) })
                  .padding({ top: 5, bottom: 5 })
                  .backgroundColor(this.mpcKind === kind ? this.c.accent : this.c.soft)
                  .borderRadius(UI_RADIUS_CONTROL)
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.mpcKind = kind })
              }, (kind: string) => kind)
            }.width('100%')

            TextInput({ text: this.mpcLineText, placeholder: '粘贴 MPC 一行轨道根数（如 Soft00Cmt / MPCORB 行）…' })
              .fontSize(this.fs(11.5))
              .fontColor(this.c.text)
              .backgroundColor(this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL)
              .constraintSize({ minHeight: this.ch(38) })
              .width('100%')
              .onChange((val: string) => { this.mpcLineText = val })

            Button(this.store.busy ? '写入中…' : '离线解析并添加到星图')
              .fontSize(this.fs(12))
              .fontColor(this.c.onAccent)
              .backgroundColor(this.c.accent)
              .borderRadius(UI_RADIUS_CONTROL)
              .constraintSize({ minHeight: this.ch(36) })
              .width('100%')
              .enabled(!this.store.busy)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                this.store.importMpcLine(this.mpcKind, this.mpcLineText, () => {
                  this.mpcLineText = ''
                })
              })
          }
          .width('100%')
          .transition(uiFadeUpTransition())
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.c.bg)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CARD)

      // 搜索框 + 分类筛选
      Row({ space: 6 }) {
        TextInput({ text: this.store.query, placeholder: '搜索彗星 / 小行星名称（如 Halley、Ceres、Vesta）' })
          .id('minor-bodies-search-input')
          .fontSize(this.fs(12))
          .fontColor(this.c.text)
          .backgroundColor(this.c.bg)
          .border({ width: 0.5, color: this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(36) })
          .layoutWeight(1)
          .onChange((val: string) => { this.store.query = val })
          .onSubmit(() => { this.store.load() })
        Button('筛选')
          .fontSize(this.fs(12))
          .fontColor(this.c.onAccent)
          .backgroundColor(this.c.accent)
          .borderRadius(UI_RADIUS_CONTROL)
          .constraintSize({ minHeight: this.ch(36) })
          .padding({ left: 12, right: 12 })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .onClick(() => { this.store.load() })
      }.width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(MINOR_CATS, (tab: MinorCatTab) => {
            Text(tab.label + ' ' + String(this.catCount(tab.id)))
              .id('minor-bodies-cat-' + tab.id)
              .fontSize(this.fs(11.5))
              .fontWeight(this.store.category === tab.id ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.store.category === tab.id ? this.c.onAccent : this.c.sub)
              .padding({ left: 11, right: 11, top: 7, bottom: 7 })
              .backgroundColor(this.store.category === tab.id ? this.c.accent : this.c.soft)
              .borderRadius(UI_RADIUS_CONTROL)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .onClick(() => {
                if (this.store.category !== tab.id) {
                  this.store.category = tab.id
                  this.store.load()
                }
              })
          }, (tab: MinorCatTab) => tab.id)
        }.padding({ left: 1, right: 2 })
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

      if (this.store.loading && this.store.items.length === 0) {
        Row({ space: 8 }) {
          LoadingProgress().width(20).height(20).color(this.c.accent)
          Text('正在读取小天体目录…').fontSize(this.fs(12)).fontColor(this.c.sub)
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 18, bottom: 18 })
      } else if (this.store.error.length > 0) {
        Text(this.store.error).fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').padding(12)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
      } else if (this.store.items.length === 0) {
        Text('当前筛选条件下未找到匹配的小天体。').fontSize(this.fs(12)).fontColor(this.c.sub).width('100%').padding(12)
          .backgroundColor(this.c.bg).borderRadius(UI_RADIUS_CARD)
      } else {
        Column({ space: 8 }) {
          ForEach(this.store.items, (item: MinorBodyItem) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(item.name)
                      .fontSize(this.fs(13.5))
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.c.textStrong)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(item.typeZh)
                      .fontSize(this.fs(10))
                      .fontColor(this.c.accent)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .backgroundColor(this.c.softStrong)
                      .borderRadius(UI_RADIUS_PILL)
                  }.alignItems(VerticalAlign.Center)
                  Text((item.magnitude < 90 ? item.magnitude.toFixed(1) + 'm' : '--')
                    + ' · ' + item.distanceAU.toFixed(2) + ' AU · ' + this.formatPeriod(item.periodDays))
                    .fontSize(this.fs(11))
                    .fontColor(this.c.sub)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                Button('定位')
                  .fontSize(this.fs(11.5))
                  .fontColor(this.c.onAccent)
                  .backgroundColor(this.c.accent)
                  .borderRadius(UI_RADIUS_PILL)
                  .constraintSize({ minHeight: this.ch(32) })
                  .padding({ left: 12, right: 12 })
                  .clickEffect({ level: ClickEffectLevel.LIGHT })
                  .onClick(() => { this.onLocateObject(item.englishName) })
              }.width('100%').alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.c.bg)
            .border({ width: 0.5, color: this.c.border })
            .borderRadius(UI_RADIUS_CARD)
          }, (item: MinorBodyItem) => item.englishName)
        }.width('100%')
      }
    }
    .width('100%')
    .padding({ bottom: 12 })
  }
}
