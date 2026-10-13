import { curves } from '@kit.ArkUI'
import { ShellAction } from '../../pages/StellariumTypes'
import { BottomDock } from './BottomDock'
import { CompactTopQuickControls } from './CompactTopQuickControls'
import { DockClockLayer, DockFovLayer, SkyZoomLayer } from './PanelChromeExtras'
import { GyroCalibPanel } from '../sensors/GyroCalibPanel'
import { ObjectDetailConnectorLayer } from '../overlay/ObjectDetailConnectorLayer'
import { UnifiedObjectDetailCard } from '../object/UnifiedObjectDetailCard'
import { GyroStore } from '../../state/GyroStore'
import { ObjectDetailStore } from '../../state/ObjectDetailStore'
import { ObjectMediaStore } from '../../state/ObjectMediaStore'
import { OverlayStore } from '../../state/OverlayStore'

// 手机 / 折叠半折的紧凑壳。
//
// 结构：全屏星空触摸承接层（Blank + onTouch）+ 底部 Dock + Dock 时钟层 + 右上角
// 紧凑快捷区（陀螺仪 / 音频）+ 陀螺仪校准浮层 + 天体详情指向线与详情卡。
//
// 面板由宿主调用点在过渡包裹内渲染，本组件不含面板：`compactPanel()` 是宿主薄 @Builder
// （体内即 `panelContent()` 的 `activePanel` 分发链），组件无法跨边界调用宿主 @Builder
// （会触发真机退出），故面板仍由宿主渲染。
//
// 所有状态以 @Prop / @ObjectLink 注入，动作回注宿主。

@Component
export struct CompactShell {
  @ObjectLink objectDetailStore: ObjectDetailStore
  @ObjectLink objectMediaStore: ObjectMediaStore
  @ObjectLink overlayStore: OverlayStore
  @ObjectLink gyroStore: GyroStore

  @Prop skyHeight: number
  @Prop panelVisible: boolean
  @Prop isExpandedLayout: boolean
  @Prop polarScopeVisible: boolean
  @Prop activePanel: string
  @Prop languageRevision: number
  @Prop actions: ShellAction[]
  @Prop chromeOpacity: number
  @Prop chromeIsGlass: boolean
  @Prop dockWidthPercent: number
  @Prop dockIconSize: number
  @Prop dockLabelFontSize: number
  @Prop dockItemHeight: number
  @Prop dockClockText: string
  @Prop fovText: string
  @Prop chromeRowY: number
  @Prop chromeRowWidth: number
  @Prop chromeRowPosXLeft: number
  @Prop chromeRowPosXRight: number
  @Prop chromeZoomHorizontal: boolean
  @Prop dockWidth: number
  @Prop dockLeft: number
  @Prop dockTop: number
  @Prop musicEnabled: boolean
  @Prop compactQuickPressed: string
  @Prop quickX: number
  @Prop quickY: number
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
  onOpenTime: () => void = () => {}
  onZoomIn: () => void = () => {}
  onZoomOut: () => void = () => {}
  onGyro: () => void = () => {}
  onAudio: () => void = () => {}
  onCompactTopQuickTouch: (event: TouchEvent) => void = () => {}
  onFlashHint: (text: string) => void = () => {}
  onCalibrate: () => void = () => {}
  onToggleGyroscope: (enabled: boolean) => void = () => {}
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

  build() {
    Stack() {
      Column() {
        Blank()
          .width('100%')
          .height('100%')
          .hitTestBehavior(HitTestMode.Block)
          .onTouch((event: TouchEvent) => {
            this.onSkyTouch(event)
          })
      }
        .width('100%')
        .height('100%')
        .zIndex(1)

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
        .height(66)
        .justifyContent(FlexAlign.Center)
        .position({ x: 0, y: this.skyHeight - 80 })
        .hitTestBehavior(HitTestMode.Block)
        .zIndex(40)

      // 三件套（FOV 读数 / 缩放按钮 / 常驻时钟）共用宿主给的锚点：手机·半折两端取同一个 x
      // （跟随 dock 两端），平板则贴屏幕左右缘。
      if (!this.panelVisible && !this.polarScopeVisible && this.dockClockText.length > 0) {
        DockClockLayer({ clockText: this.dockClockText, layerWidth: this.chromeRowWidth, posX: this.chromeRowPosXRight, posY: this.chromeRowY, onOpenTime: () => { this.onOpenTime() } })
      }

      // FOV 读数：贴左端，与右侧时钟左右对称（纯信息展示，整层不参与命中测试）。
      // 首帧前 currentFovText 为 '--'，用 '°' 兜住，避免出现 "FOV --"。
      if (!this.panelVisible && !this.polarScopeVisible && this.fovText.indexOf('°') >= 0) {
        DockFovLayer({
          fovText: this.fovText, layerWidth: this.chromeRowWidth, posX: this.chromeRowPosXLeft,
          posY: this.chromeRowY, textColor: this.textColor
        })
      }

      // 缩放按钮：紧贴读数行上沿；手机·半折竖排、平板横排（由 chromeZoomHorizontal 决定）。
      if (!this.panelVisible && !this.polarScopeVisible) {
        SkyZoomLayer({
          layerWidth: this.chromeRowWidth, posX: this.chromeRowPosXLeft,
          rowY: this.chromeRowY, horizontal: this.chromeZoomHorizontal,
          textColor: this.textColor,
          onZoomIn: () => { this.onZoomIn() },
          onZoomOut: () => { this.onZoomOut() }
        })
      }

      // 手机端右上角常驻快捷区：陀螺仪 + 音频（与平板左侧栏入口一致）
      Stack() {
        CompactTopQuickControls({
          gyroActive: this.gyroStore.gyroscopeEnabled, audioActive: this.musicEnabled,
          pressedId: this.compactQuickPressed, chromeOpacity: this.chromeOpacity,
          textColor: this.textColor,
          onGyro: () => {
            this.onGyro()
          },
          onAudio: () => {
            this.onAudio()
          }
        })
      }
          .position({ x: this.quickX, y: this.quickY })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(30)
        // Keep a dedicated touch target above the Qt XComponent.  The native
        // surface otherwise intermittently captures the compact quick buttons.
        Stack() { }
          .width(44)
          .height(98)
          .position({ x: this.quickX, y: this.quickY })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(31)
          .onTouch((event: TouchEvent) => {
            this.onCompactTopQuickTouch(event)
          })
      // 陀螺仪校准面板（紧凑布局）
      if (this.gyroStore.gyroscopeEnabled && this.gyroStore.gyroCalibPanelOpen) {
        Stack() { GyroCalibPanel({ store: this.gyroStore, onFlashHint: (text: string) => { this.onFlashHint(text) }, onCalibrate: () => { this.onCalibrate() }, onToggle: (enabled: boolean) => { this.onToggleGyroscope(enabled) } }) }
          .position({ x: 16, y: 80 })
          .hitTestBehavior(HitTestMode.Block)
          .zIndex(60)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: -20, y: 0 }).animation({ duration: 300, curve: curves.springMotion(0.5, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseIn })
          ))
      }
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
          .zIndex(50)
          .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 260, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: 40 }).animation({ duration: 420, curve: curves.springMotion(0.55, 0.85) })),
            TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 0, y: 20 }).animation({ duration: 200, curve: Curve.EaseIn }))
          ))
      }
    }
      .width('100%')
      .height('100%')
      .zIndex(1)
      .hitTestBehavior(HitTestMode.Transparent)
  }
}
