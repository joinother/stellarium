import { I18n } from '../../pages/I18n'
import { UI_RADIUS_PANEL } from '../../common/ui/UiTokens'
import { getIcon } from '../../common/ui/ShellIcons'
import { tintMatrixFor } from '../../common/ui/IconTint'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { SatellitePass, StationComplexMember } from '../../pages/StellariumTypes'
import { ObjectDetailCardHeader, ObjectDetailCardTabs } from './ObjectDetailCardChrome'
import { ObjectDetailObserveTab, ObjectDetailCoordinateTab, ObjectDetailDataTab } from './ObjectDetailTabs'
import { ObjectDetailActionsTab } from './ObjectDetailActionsTab'
import { ObjectSelectionPill } from './ObjectSelectionPill'
import { curves, Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 天体详情主卡片的整体外壳：页头 + 页签栏 + 分隔线 + `Scroll` 内四个页组件。
//
// 宿主侧派生值（图标 / 距离摘要 / 资料页媒体参数 / 卡片尺寸）以 `@Prop` 传入，动态查值与名称本地化
// 以回调注入，`Scroller` 与宿主共享同一实例。滚动位置上报与媒体视口高度回写留在组件内，
// 因为它们只依赖本组件的 scroller 与 `mediaStore`。
// 不用 `@BuilderParam` 承接宿主 `@Builder`——真机上会让应用在渲染该页时退出。

@Component
export struct UnifiedObjectDetailCard {
  @ObjectLink store: ObjectDetailStore
  @ObjectLink mediaStore: ObjectMediaStore
  @Prop @Watch('onActiveTabChange') activeIndex: number
  @Prop liveInfoVisible: boolean
  @Prop contentOpacity: number
  @Prop contentTranslateX: number
  @Prop cardWidth: number
  @Prop cardHeight: number
  @Prop viewLock: boolean
  @Prop speechStatus: string
  @Prop inObservingList: boolean
  @Prop iconName: string
  @Prop detailDisplayMode: string
  @Prop observeExpanded: boolean
  // 时间面板打开：整张卡形变为轻量卡（仅名称/摘要 + ✕，无展开箭头与详情按钮）。
  @Prop timeLight: boolean
  @Prop distanceText: string
  @Prop distanceSummaryText: string
  @Prop imageHeight: number
  @Prop inlineModelSize: number
  @Prop modelReady: boolean
  @Prop modelRendering: boolean
  @Prop hasModelTexture: boolean
  @Prop modelNotice: string
  @Prop warmupText: string
  @Prop fallbackKind: string
  @Prop satelliteVisible: boolean
  @Prop tleEpoch: string
  @Prop cultureVisible: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  @State private scrollBlurProgress: number = 0
  @State private topChromeHeight: number = 178
  private pendingScrollBlurOffsetY: number = 0
  private scrollBlurUpdatePending: boolean = false
  scroller: Scroller = new Scroller()
  resolve: (key: string) => string = () => ''
  nameOf: (name: string) => string = () => ''
  typeOf: (type: string) => string = () => ''
  onDragTouch: (event: TouchEvent) => void = () => {}
  onDismiss: () => void = () => {}
  onCenterObject: () => void = () => {}
  onExpandObserve: () => void = () => {}
  onCollapseObserve: () => void = () => {}
  onSelectTab: (index: number) => void = () => {}
  onLoadPasses: () => void = () => {}
  onJumpToPass: (pass: SatellitePass) => void = () => {}
  onJumpToCometTail: () => void = () => {}
  onSelectComplexMember: (member: StationComplexMember) => void = () => {}
  onMediaOpen: () => void = () => {}
  onMediaRetry: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}
  onCenter: () => void = () => {}
  onToggleLock: () => void = () => {}
  onToggleObserving: () => void = () => {}
  onRefresh: () => void = () => {}
  onReselect: () => void = () => {}
  onSpeak: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  aboutToAppear(): void {
    this.scrollBlurProgress = 0
  }

  private onActiveTabChange(): void {
    setTimeout(() => {
      this.updateScrollBlur(this.scroller.currentOffset()?.yOffset ?? 0)
    }, 32)
  }

  // 遵循华为 HarmonyOS 标题栏动态模糊规范（ui-design-navigation-dynamic-blur：0 -> 20vp 渐进）：
  // 滚动回调可能发生在布局/渲染阶段，合并到下一轮事件循环更新 @State，避免状态渲染重入。
  private updateScrollBlur(offsetY: number): void {
    this.pendingScrollBlurOffsetY = offsetY
    if (this.scrollBlurUpdatePending) return
    this.scrollBlurUpdatePending = true
    setTimeout(() => {
      this.scrollBlurUpdatePending = false
      const pending = this.pendingScrollBlurOffsetY
      const clamped = Number.isFinite(pending) ? Math.max(0, Math.min(1, pending / 20)) : 0
      if (Math.abs(clamped - this.scrollBlurProgress) >= 0.04
        || (clamped === 0 && this.scrollBlurProgress !== 0)
        || (clamped === 1 && this.scrollBlurProgress !== 1)) {
        this.scrollBlurProgress = clamped
      }
    }, 0)
  }

  // 观测极简形态：页头 + 卡片下沿展开箭头，页签栏 / 实时行 / 滚动区整体不渲染。
  private observeCompact(): boolean {
    return this.detailDisplayMode === 'observe' && !this.observeExpanded
  }

  // 观测模式（含展开态）：卡片下沿中央渲染一个箭头 —— 收起态向下（展开）、展开态向上（收起）。
  private observeMode(): boolean {
    return this.detailDisplayMode === 'observe'
  }

  build() {
    Column() {
      if (this.timeLight) {
        ObjectSelectionPill({
          store: this.store,
          iconName: this.iconName,
          pillWidth: this.cardWidth,
          distanceSummaryText: this.distanceSummaryText,
          nameOf: this.nameOf,
          typeOf: this.typeOf,
          onDismiss: () => { this.onDismiss() }
        })
      } else if (this.observeCompact()) {
        ObjectDetailCardHeader({
          store: this.store, iconName: this.iconName, liveInfoVisible: this.liveInfoVisible,
          detailDisplayMode: this.detailDisplayMode,
          // 距离摘要直接消费页头从 `@ObjectLink store` 实时读出的 distance/compact，
          // 仅用 `distanceSummaryText === '--'` 判断用户是否关闭了距离显示。
          distanceSummary: (distance: string, compact: string) => this.distanceSummaryText === '--'
            ? '--'
            : (distance.length > 0 ? (compact.length > 0 ? compact : distance) : I18n.t('distance_missing')),
          nameOf: this.nameOf, typeOf: this.typeOf,
          onDragTouch: (event: TouchEvent) => { this.onDragTouch(event) }, onDismiss: () => { this.onDismiss() },
          onCenterObject: () => { this.onCenterObject() }
        })
      } else {
        Stack({ alignContent: Alignment.Top }) {
          // 底层滚动内容区：向上穿透到吸顶页头与页签栏下方，遵循 HarmonyOS 内容穿透式顶部动态模糊规范。
          Scroll(this.scroller) {
            Column({ space: 8 }) {
              if (this.activeIndex === 0) {
                ObjectDetailObserveTab({
                  store: this.store, distanceText: this.distanceText, resolve: this.resolve,
                  onJumpToCometTail: () => { this.onJumpToCometTail() }
                })
              } else if (this.activeIndex === 1) {
                ObjectDetailCoordinateTab({ store: this.store, distanceText: this.distanceText, resolve: this.resolve })
              } else if (this.activeIndex === 2) {
                ObjectDetailDataTab({
                  store: this.store, mediaStore: this.mediaStore, tablet: false, distanceText: this.distanceText,
                  iconName: this.iconName, imageHeight: this.imageHeight, inlineModelSize: this.inlineModelSize,
                  modelReady: this.modelReady, modelRendering: this.modelRendering, hasModelTexture: this.hasModelTexture,
                  modelNotice: this.modelNotice, warmupText: this.warmupText, fallbackKind: this.fallbackKind,
                  satelliteVisible: this.satelliteVisible, tleEpoch: this.tleEpoch,
                  cultureVisible: this.cultureVisible,
                  resolve: this.resolve,
                  onLoadPasses: () => { this.onLoadPasses() },
                  onJumpToPass: (pass: SatellitePass) => { this.onJumpToPass(pass) },
                  onJumpToCometTail: () => { this.onJumpToCometTail() },
                  onSelectComplexMember: (member: StationComplexMember) => { this.onSelectComplexMember(member) },
                  onMediaOpen: () => { this.onMediaOpen() },
                  onMediaRetry: () => { this.onMediaRetry() }, onModelExpand: () => { this.onModelExpand() },
                  onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) }
                })
              } else {
                ObjectDetailActionsTab({
                  viewLock: this.viewLock,
                  speechStatus: this.speechStatus,
                  inObservingList: this.inObservingList,
                  cometTailBestDate: this.store.selectedCometTailBestJD > 0 ? this.store.selectedCometTailBestDate : '',
                  onCenter: () => { this.onCenter() },
                  onToggleLock: () => { this.onToggleLock() },
                  onToggleObserving: () => { this.onToggleObserving() },
                  onRefresh: () => { this.onRefresh() },
                  onReselect: () => { this.onReselect() },
                  onSpeak: () => { this.onSpeak() },
                  onJumpToCometTail: () => { this.onJumpToCometTail() }
                })
              }
            }
              .width('100%').padding({ left: 16, right: 16, top: this.topChromeHeight + 8, bottom: 12 })
          }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .height('100%')
            .opacity(this.contentOpacity)
            .translate({ x: this.contentTranslateX, y: 0 })
            .id('object-detail-content-scroll')
            .onDidScroll(() => {
              const offsetY = this.scroller.currentOffset()?.yOffset ?? 0
              AppStorage.setOrCreate('stellariumObjectDetailScrollY', this.scroller.currentOffset()?.yOffset ?? 0)
              this.updateScrollBlur(offsetY)
            })
            .onScrollStop(() => {
              const offsetY = this.scroller.currentOffset()?.yOffset ?? 0
              AppStorage.setOrCreate('stellariumObjectDetailScrollY', this.scroller.currentOffset()?.yOffset ?? 0)
              this.updateScrollBlur(offsetY)
            })
            .onAreaChange((_oldArea: Area, newArea: Area) => {
              const height = Number(newArea.height)
              const visibleViewport = Math.max(120, height - this.topChromeHeight)
              if (Number.isFinite(visibleViewport) && visibleViewport > 0 && Math.abs(visibleViewport - this.mediaStore.objectInspectorMediaViewportHeight) > 1) {
                this.mediaStore.objectInspectorMediaViewportHeight = visibleViewport
              }
            })

          // 顶栏下方 14vp 柔和渐隐羽化带：滚动时浮现，柔化内容区进入顶栏毛玻璃的边界
          Column()
            .width('100%')
            .height(14)
            .position({ x: 0, y: this.topChromeHeight })
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [
                [this.c.panelGlassStrong, 0.0],
                [Color.Transparent, 1.0]
              ]
            })
            .opacity(this.scrollBlurProgress * 0.72)
            .hitTestBehavior(HitTestMode.None)
            .zIndex(11)

          // 吸顶页头 + 页签栏 + 动态毛玻璃背板（随 0 -> 20vp 滚动平滑渐显）
          Stack({ alignContent: Alignment.Top }) {
            Column()
              .width('100%')
              .height(this.topChromeHeight)
              .backdropBlur(this.scrollBlurProgress > 0.02 ? Math.round(this.scrollBlurProgress * 26) : 0)
              .linearGradient({
                direction: GradientDirection.Bottom,
                colors: [
                  [this.c.panelGlassStrong, 0.0],
                  [this.c.panelGlassStrong, 0.84],
                  [Color.Transparent, 1.0]
                ]
              })
              .opacity(this.scrollBlurProgress)
              .hitTestBehavior(HitTestMode.None)

            Column() {
              ObjectDetailCardHeader({
                store: this.store, iconName: this.iconName, liveInfoVisible: this.liveInfoVisible,
                detailDisplayMode: this.detailDisplayMode,
                distanceSummary: (distance: string, compact: string) => this.distanceSummaryText === '--'
                  ? '--'
                  : (distance.length > 0 ? (compact.length > 0 ? compact : distance) : I18n.t('distance_missing')),
                nameOf: this.nameOf, typeOf: this.typeOf,
                onDragTouch: (event: TouchEvent) => { this.onDragTouch(event) }, onDismiss: () => { this.onDismiss() },
                onCenterObject: () => { this.onCenterObject() }
              })

              ObjectDetailCardTabs({ activeIndex: this.activeIndex, onSelect: (index: number) => { this.onSelectTab(index) } })

              Divider()
                .color(this.c.softStrong)
                .margin({ left: 16, right: 16 })
                .opacity(0.38 + this.scrollBlurProgress * 0.62)
            }
              .width('100%')
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                const h = Number(newArea.height)
                if (Number.isFinite(h) && h > 40 && Math.abs(h - this.topChromeHeight) > 0.5) {
                  this.topChromeHeight = h
                }
              })
          }
            .width('100%')
            .zIndex(12)
        }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
      }

      if (!this.timeLight && this.observeMode()) {
        // 展开 / 收起的唯一入口：卡片下沿正中一个箭头 —— 收起态向下（展开全量），展开态向上（收回极简）。
        // 时间面板打开时的轻量卡不提供该入口（此时应保持小卡让位给面板）。
        // 样式与面板返回按钮完全一致（无底 Button + `ic_back` 17vp 描边箭头 + 按压 opacity 0.62），
        // 只是把同一个左向箭头旋转 90°：−90° = 向下，+90° = 向上。动作作用于「这张卡的整体形态」，
        // 位置固定在下沿最容易被摸到。
        Row() {
          if (this.observeExpanded) {
            Button() {
              Image(getIcon('back', false)).width(17).height(17).supportSvg2(true).colorFilter(tintMatrixFor(this.c.dockActive)).rotate({ angle: 90 })
            }
              .id('object-detail-observe-collapse')
              .width(28).height(28).padding(0).borderRadius(0)
              .backgroundColor(Color.Transparent)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .stateStyles({ pressed: { .opacity(0.62) } })
              .accessibilityText(I18n.t('detail_observe_collapse'))
              .onClick(() => {
                this.onCollapseObserve()
              })
          } else {
            Button() {
              Image(getIcon('back', false)).width(17).height(17).supportSvg2(true).colorFilter(tintMatrixFor(this.c.dockActive)).rotate({ angle: -90 })
            }
              .id('object-detail-observe-expand')
              .width(28).height(28).padding(0).borderRadius(0)
              .backgroundColor(Color.Transparent)
              .clickEffect({ level: ClickEffectLevel.LIGHT })
              .stateStyles({ pressed: { .opacity(0.62) } })
              .accessibilityText(I18n.t('detail_observe_expand'))
              .onClick(() => {
                this.onExpandObserve()
              })
          }
        }
          .width('100%')
          .justifyContent(FlexAlign.Center)
      }

    }
      .width(this.cardWidth)
      .height(this.cardHeight)
      .backgroundColor(this.c.overlayPanel)
      .backdropBlur(28)
      .border({ width: 0.5, color: this.c.softStrong })
      .borderRadius(this.timeLight ? (this.cardWidth < 310 ? 20 : 29) : UI_RADIUS_PANEL)
      .clip(true)
      .shadow({ radius: 20, color: this.c.shadowSoft, offsetX: 0, offsetY: 8 })
      // 真实几何/位置形变（方案 A）：尺寸与圆角随时间面板开合平滑过渡。
      .animation({ duration: 280, curve: curves.springMotion(0.52, 0.9) })
  }
}
