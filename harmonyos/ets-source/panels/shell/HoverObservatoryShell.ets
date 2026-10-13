import { ShellAction } from '../../pages/StellariumTypes'
import { BottomDock } from './BottomDock'
import { ObjectDetailConnectorLayer } from '../overlay/ObjectDetailConnectorLayer'
import { UnifiedObjectDetailCard } from '../object/UnifiedObjectDetailCard'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { OverlayStore } from '../../state/OverlayStore'
import { UI_RADIUS_PILL, UI_RADIUS_SHEET } from '../../common/ui/UiTokens'

// 折叠展开（hover）观测壳。
//
// 结构：全屏星空触摸承接层 + 顶部观测时间/FOV 胶囊 + 分隔线 + 观测台玻璃底板
// （Column 纯装饰）+ 底部 Dock + 天体详情指向线与详情卡。
//
// 面板由宿主调用点在过渡包裹内渲染，本组件不含面板：`compactPanel()` 是宿主薄 @Builder
// （体内即 `panelContent()` 的 `activePanel` 分发链），组件无法跨边界调用宿主 @Builder
// （会触发真机退出），故面板仍由宿主渲染。
//
// 所有状态以 @Prop / @ObjectLink 注入，动作回注宿主。

@Component
export struct HoverObservatoryShell {
  @ObjectLink objectDetailStore: ObjectDetailStore
  @ObjectLink objectMediaStore: ObjectMediaStore
  @ObjectLink overlayStore: OverlayStore

  @Prop observationTimeText: string
  @Prop currentFovText: string
  @Prop skyWidth: number
  @Prop skyHeight: number
  @Prop hoverSkyPaneHeight: number
  @Prop panelIdleGlass: boolean
  @Prop panelVisible: boolean
  @Prop isExpandedLayout: boolean
  @Prop activePanel: string
  @Prop languageRevision: number
  @Prop actions: ShellAction[]
  @Prop chromeOpacity: number
  @Prop chromeIsGlass: boolean
  @Prop dockWidthPercent: number
  @Prop dockIconSize: number
  @Prop dockLabelFontSize: number
  @Prop dockItemHeight: number
  @Prop infoWinVisible: boolean
  @Prop bottomCardIndex: number
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
  @Prop starColor: string
  @Prop satelliteVisible: boolean
  @Prop tleEpoch: string
  @Prop accent: string
  @Prop cultureVisible: boolean
  @Prop textColor: string
  @Prop connectorVisible: boolean
  @Prop connectorLength: number
  @Prop connectorX: number
  @Prop connectorY: number
  @Prop connectorAngle: number
  @Prop connectorAnimateGeometry: boolean
  @Prop connectorTargetOnScreen: boolean
  @Prop connectorTargetX: number
  @Prop connectorTargetY: number
  @Prop connectorEndX: number
  @Prop connectorEndY: number
  @Prop markerSize: number
  @Prop detailX: number
  @Prop detailY: number
  @Prop detailWidth: number
  @Prop detailHeight: number

  scroller: Scroller = new Scroller()
  onSkyTouch: (event: TouchEvent) => void = () => {}
  onDockTouch: (event: TouchEvent) => void = () => {}
  onDockTap: (item: ShellAction) => void = () => {}
  onPanelTouch: (event: TouchEvent) => void = () => {}
  resolve: (key: string) => string = () => ''
  nameOf: (name: string) => string = () => ''
  typeOf: (type: string) => string = () => ''
  onDragTouch: (event: TouchEvent) => void = () => {}
  onDismiss: () => void = () => {}
  onSelectTab: (index: number) => void = () => {}
  onLoadPasses: () => void = () => {}
  onMediaOpen: () => void = () => {}
  onMediaRetry: () => void = () => {}
  onModelExpand: () => void = () => {}
  onModelTouch: (event: TouchEvent) => void = () => {}
  onCenter: () => void = () => {}
  onCenterObject: () => void = () => {}
  onExpandObserve: () => void = () => {}
  onCollapseObserve: () => void = () => {}
  onToggleLock: () => void = () => {}
  onToggleObserving: () => void = () => {}
  onRefresh: () => void = () => {}
  onReselect: () => void = () => {}
  onSpeak: () => void = () => {}

  private hoverConsoleTop(): number {
    return this.hoverSkyPaneHeight + 10
  }

  build() {
    Stack() {
      Stack()
        .width('100%')
        .height(this.hoverSkyPaneHeight)
        .position({ x: 0, y: 0 })
        .hitTestBehavior(HitTestMode.Block)
        .onTouch((event: TouchEvent) => {
          this.onSkyTouch(event)
        })

      Row() {
        Text(this.observationTimeText)
          .fontSize(11)
          .fontColor('rgba(229,255,255,0.78)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.currentFovText)
          .fontSize(11)
          .fontColor('rgba(229,255,255,0.78)')
          .margin({ left: 10 })
      }
        .height(34)
        .padding({ left: 16, right: 16 })
        .backgroundColor('rgba(10, 14, 26, 0.42)')
        .backdropBlur(22)
        .borderRadius(UI_RADIUS_PILL)
        .position({ x: 16, y: 12 })
        .width(Math.max(220, this.skyWidth - 32))
        .hitTestBehavior(HitTestMode.None)

      Row()
        .width(Math.max(120, this.skyWidth - 72))
        .height(2)
        .backgroundColor('rgba(147, 215, 255, 0.20)')
        .borderRadius(1)
        .position({ x: 36, y: this.hoverSkyPaneHeight + 1 })
        .hitTestBehavior(HitTestMode.None)

      Column()
        .width(Math.max(240, this.skyWidth - 24))
        .height(Math.max(220, this.skyHeight - this.hoverConsoleTop() - 14))
        .backgroundColor(this.panelIdleGlass ? 'rgba(10, 14, 26, 0.46)' : 'rgba(14, 18, 32, 0.66)')
        .backdropBlur(this.panelIdleGlass ? 42 : 30)
        .border({ width: 0.5, color: 'rgba(147, 215, 255, 0.12)' })
        .borderRadius(UI_RADIUS_SHEET)
        .position({ x: 12, y: this.hoverConsoleTop() })
        .hitTestBehavior(HitTestMode.None)

      Row() {
        BottomDock({
          actions: this.actions, isExpanded: this.isExpandedLayout,
          panelVisible: this.panelVisible, chromeOpacity: this.chromeOpacity,
          isGlass: this.chromeIsGlass, widthPercent: this.dockWidthPercent,
          languageRevision: this.languageRevision,
          iconSize: this.isExpandedLayout ? 22 : this.dockIconSize,
          labelFontSize: this.isExpandedLayout ? 10 : this.dockLabelFontSize,
          itemHeight: this.isExpandedLayout ? 44 : this.dockItemHeight,
          activePanel: this.activePanel,
          onDockTouch: (event: TouchEvent) => { this.onDockTouch(event) },
          onDockTap: (item: ShellAction) => { this.onDockTap(item) },
          onPanelTouch: (event: TouchEvent) => { this.onPanelTouch(event) }
        })
      }
        .width('100%')
        .height(54)
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: this.skyHeight - 62 })
        .hitTestBehavior(HitTestMode.Block)
        .zIndex(40)

      if (this.infoWinVisible && this.objectDetailStore.selectedName.length > 0) {
        ObjectDetailConnectorLayer({
          visible: this.connectorVisible,
          beamLength: this.connectorLength,
          beamX: this.connectorX,
          beamY: this.connectorY,
          beamAngle: this.connectorAngle,
          animateGeometry: this.connectorAnimateGeometry,
          targetOnScreen: this.connectorTargetOnScreen,
          targetX: this.connectorTargetX,
          targetY: this.connectorTargetY,
          endX: this.connectorEndX,
          endY: this.connectorEndY,
          markerSize: this.markerSize
        })
        Stack() {
          UnifiedObjectDetailCard({
            store: this.objectDetailStore, mediaStore: this.objectMediaStore, scroller: this.scroller,
            activeIndex: this.bottomCardIndex, liveInfoVisible: this.liveInfoVisible,
            contentOpacity: this.contentOpacity, contentTranslateX: this.contentTranslateX,
            cardWidth: this.cardWidth, cardHeight: this.cardHeight,
            viewLock: this.viewLock, speechStatus: this.speechStatus,
            inObservingList: this.inObservingList,
            iconName: this.iconName, distanceText: this.distanceText,
            detailDisplayMode: this.detailDisplayMode, observeExpanded: this.observeExpanded,
            distanceSummaryText: this.distanceSummaryText,
            imageHeight: this.imageHeight, inlineModelSize: this.inlineModelSize,
            modelReady: this.modelReady, modelRendering: this.modelRendering,
            hasModelTexture: this.hasModelTexture,
            modelNotice: this.modelNotice, warmupText: this.warmupText,
            fallbackKind: this.fallbackKind, starColor: this.starColor,
            satelliteVisible: this.satelliteVisible, tleEpoch: this.tleEpoch,
            accent: this.accent, cultureVisible: this.cultureVisible, textColor: this.textColor,
            resolve: (key: string) => this.resolve(key),
            nameOf: (name: string) => this.nameOf(name), typeOf: (type: string) => this.typeOf(type),
            onDragTouch: (event: TouchEvent) => { this.onDragTouch(event) },
            onDismiss: () => { this.onDismiss() },
            onCenterObject: () => { this.onCenterObject() },
            onExpandObserve: () => { this.onExpandObserve() },
            onCollapseObserve: () => { this.onCollapseObserve() },
            onSelectTab: (index: number) => { this.onSelectTab(index) },
            onLoadPasses: () => { this.onLoadPasses() },
            onMediaOpen: () => { this.onMediaOpen() },
            onMediaRetry: () => { this.onMediaRetry() },
            onModelExpand: () => { this.onModelExpand() },
            onModelTouch: (event: TouchEvent) => { this.onModelTouch(event) },
            onCenter: () => { this.onCenter() },
            onToggleLock: () => { this.onToggleLock() },
            onToggleObserving: () => { this.onToggleObserving() },
            onRefresh: () => { this.onRefresh() },
            onReselect: () => { this.onReselect() },
            onSpeak: () => { this.onSpeak() }
          })
        }
          .position({ x: this.detailX, y: this.detailY })
          .width(this.detailWidth)
          .height(this.detailHeight)
          .zIndex(35)
          .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
