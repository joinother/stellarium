// 详情连接线与详情自动刷新定时器控制器：驱动详情卡数据刷新，以及详情卡指向投影目标的
// 连接线几何（遮挡避让 / 屏幕边界裁剪 / 过渡动画）。
//
// 依赖 ObjectDetailStore / InfoWindowStore（只读），宿主几何、面板/星图状态、OverlayStore
// 可见性、native 投影与指向线 @State 均经 DetailConnectorHostHooks 回注；控制器不 import
// NAPI/UI，getGyroGuidePosition 的 GyroGuideProjection 强转由宿主完成后经 hook 下发。
// 定时器自持：startDetailAutoRefresh()/startObjectDetailConnectorRefresh() 启动，stop() 收口。
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { InfoWindowStore } from '../state/InfoWindowStore'
import { GyroGuideProjection, SkyUiObstacle } from '../pages/MainWindowModels'
import { pointInsideRect } from '../common/derive/geometry'
import { BehaviorHostHooks } from './ControllerHooks'

// 宿主 → 控制器回注：不触碰 UI/宿主私有标志以外的任何 NAPI。
export interface DetailConnectorHostHooks extends BehaviorHostHooks {
  // 面板 / 星图状态读取。
  activePanel(): string
  panelVisible(): boolean
  skyDragging(): boolean
  // 几何派生（宿主保留）。
  skyWidth(): number
  skyHeight(): number
  isFoldHoverLayout(): boolean
  bottomCardY(): number
  hoverBottomCardY(): number
  detailCardX(): number
  detailCardY(): number
  detailCardWidth(): number
  detailCardHeight(): number
  // 宿主保留的控制器与收口点。
  objectDetailConnectorObstacles(): SkyUiObstacle[]
  refreshSelectedObject(): void
  scheduleSkyTextureStatusCheck(): void
  // native 投影（宿主完成 GyroGuideProjection 强转）。
  gyroGuideProjection(): GyroGuideProjection
  // OverlayStore.objectDetailConnectorVisible 读取（控制器不持该 store）。
  connectorVisible(): boolean
  // 指向线几何 9 个 @State（宿主持有，控制器逐帧 set/get）。
  connectorX(): number
  setConnectorX(value: number): void
  connectorY(): number
  setConnectorY(value: number): void
  connectorLength(): number
  setConnectorLength(value: number): void
  connectorAngle(): number
  setConnectorAngle(value: number): void
  connectorEndX(): number
  setConnectorEndX(value: number): void
  connectorEndY(): number
  setConnectorEndY(value: number): void
  connectorTargetX(): number
  setConnectorTargetX(value: number): void
  connectorTargetY(): number
  setConnectorTargetY(value: number): void
  connectorTargetOnScreen(): boolean
  setConnectorTargetOnScreen(value: boolean): void
  // 过渡动画开关（宿主 @State）。
  setConnectorAnimateGeometry(value: boolean): void
}

export class DetailConnectorController {
  private objectDetailStore: ObjectDetailStore
  private infoWindowStore: InfoWindowStore
  private hooks: DetailConnectorHostHooks

  // ── 定时器句柄 / 草稿字段（随控制器走，不入 @Observed store）──
  private detailTimer: number = 0
  private detailRefreshing: boolean = false
  private detailRefreshGuard: number = 0
  private objectDetailConnectorTimer: number = 0
  private objectDetailConnectorAnimationTimer: number = 0
  private objectDetailConnectorLastPanelVisible: boolean = false
  private objectDetailConnectorLastActivePanel: string = ''
  private objectDetailConnectorLastClippedByUi: boolean = false
  private objectCardPlacementPending: boolean = false

  constructor(objectDetailStore: ObjectDetailStore, infoWindowStore: InfoWindowStore, hooks: DetailConnectorHostHooks) {
    this.objectDetailStore = objectDetailStore
    this.infoWindowStore = infoWindowStore
    this.hooks = hooks
  }

  // ── 详情自动刷新 ──

  // 启动「详情自动刷新」：仅在【目标详情面板打开 + 有已选中天体 + 未在拖动星图】时才拉数据，避免无谓的桥调用。
  startDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { return }
    this.detailTimer = setInterval(() => {
      if (this.hooks.skyDragging()) { return }
      if (this.objectDetailStore.selectedStatus === 'Selected' && ((this.hooks.activePanel() === 'object' && this.hooks.panelVisible()) || this.infoWindowStore.infoWinVisible)) {
        // The one-shot full-details request owns the initial structured card
        // load. Do not race it with a second request from the live-value poll.
        if (!this.objectDetailStore.selectedDetailLoaded && this.objectDetailStore.selectedDetailTimer !== 0) { return }
        this.hooks.refreshSelectedObject()
      }
    }, 180)
    this.startObjectDetailConnectorRefresh()
  }

  pauseDetailRefreshForSkyDrag(): void {
    // Object-info polling uses the same ArkTS-to-Qt queue as panning. Stop it
    // for the duration of a gesture so an open detail card cannot make the sky
    // lag behind the finger. The connector is only a lightweight projection
    // read and must keep running so its line follows the native sky gesture.
    this.stopDetailAutoRefresh()
  }

  resumeDetailRefreshAfterSkyDrag(): void {
    if (this.infoWindowStore.infoWinVisible && this.objectDetailStore.selectedStatus === 'Selected') {
      this.startDetailAutoRefresh()
      this.refreshObjectDetailConnector()
      this.hooks.scheduleSkyTextureStatusCheck()
    }
  }

  stopDetailAutoRefresh(): void {
    if (this.detailTimer !== 0) { clearInterval(this.detailTimer); this.detailTimer = 0 }
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard); this.detailRefreshGuard = 0 }
    this.detailRefreshing = false
  }

  // 以下三法供宿主保留方法 refreshSelectedObject（SelectionService 侧）与控制器交互：
  // detailRefreshing / detailRefreshGuard 的所有权在本控制器。
  isDetailRefreshing(): boolean {
    return this.detailRefreshing
  }

  beginDetailRefresh(): void {
    this.detailRefreshing = true
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard) }
    this.detailRefreshGuard = setTimeout(() => { this.detailRefreshing = false }, 1800)
  }

  endDetailRefresh(): void {
    this.detailRefreshing = false
    if (this.detailRefreshGuard !== 0) { clearTimeout(this.detailRefreshGuard); this.detailRefreshGuard = 0 }
  }

  // 宿主 handleApplicationLifecycle 判「是否需要在回前台时重启详情轮询」。
  hasDetailTimer(): boolean {
    return this.detailTimer !== 0
  }

  // 宿主选中/展开详情卡时置位；连接线刷新时消费一次。
  markObjectCardPlacementPending(): void {
    this.objectCardPlacementPending = true
  }

  // ── 指向线刷新 ──

  startObjectDetailConnectorRefresh(): void {
    if (this.objectDetailConnectorTimer !== 0) { return }
    this.objectDetailConnectorTimer = setInterval(() => {
      this.refreshObjectDetailConnector()
    }, 32)
    this.refreshObjectDetailConnector()
  }

  stopObjectDetailConnectorRefresh(): void {
    if (this.objectDetailConnectorTimer !== 0) {
      clearInterval(this.objectDetailConnectorTimer)
      this.objectDetailConnectorTimer = 0
    }
    if (this.objectDetailConnectorAnimationTimer !== 0) {
      clearTimeout(this.objectDetailConnectorAnimationTimer)
      this.objectDetailConnectorAnimationTimer = 0
    }
    this.hooks.setConnectorAnimateGeometry(false)
  }

  // 生命周期收口（宿主 aboutToDisappear / 清除选中）：停止详情轮询与连接线刷新。
  stop(): void {
    this.stopDetailAutoRefresh()
    this.stopObjectDetailConnectorRefresh()
  }

  armObjectDetailConnectorTransition(): void {
    this.hooks.setConnectorAnimateGeometry(true)
    if (this.objectDetailConnectorAnimationTimer !== 0) {
      clearTimeout(this.objectDetailConnectorAnimationTimer)
    }
    this.objectDetailConnectorAnimationTimer = setTimeout(() => {
      this.hooks.setConnectorAnimateGeometry(false)
      this.objectDetailConnectorAnimationTimer = 0
    }, 190)
  }

  objectDetailCardY(): number {
    return this.hooks.isFoldHoverLayout() ? this.hooks.hoverBottomCardY() : this.hooks.bottomCardY()
  }

  private rayRectIntersection(originX: number, originY: number, targetX: number, targetY: number,
    left: number, top: number, right: number, bottom: number): number[] {
    const dx = targetX - originX
    const dy = targetY - originY
    const intersections: number[][] = []
    if (Math.abs(dx) > 0.0001) {
      const leftT = (left - originX) / dx
      const leftY = originY + leftT * dy
      if (leftT > 0 && leftY >= top - 0.5 && leftY <= bottom + 0.5) intersections.push([leftT, left, leftY])
      const rightT = (right - originX) / dx
      const rightY = originY + rightT * dy
      if (rightT > 0 && rightY >= top - 0.5 && rightY <= bottom + 0.5) intersections.push([rightT, right, rightY])
    }
    if (Math.abs(dy) > 0.0001) {
      const topT = (top - originY) / dy
      const topX = originX + topT * dx
      if (topT > 0 && topX >= left - 0.5 && topX <= right + 0.5) intersections.push([topT, topX, top])
      const bottomT = (bottom - originY) / dy
      const bottomX = originX + bottomT * dx
      if (bottomT > 0 && bottomX >= left - 0.5 && bottomX <= right + 0.5) intersections.push([bottomT, bottomX, bottom])
    }
    if (intersections.length === 0) return []
    intersections.sort((a: number[], b: number[]) => a[0] - b[0])
    return [intersections[0][1], intersections[0][2]]
  }

  private segmentRectEntryFraction(startX: number, startY: number, endX: number, endY: number,
    left: number, top: number, right: number, bottom: number): number {
    const dx = endX - startX
    const dy = endY - startY
    const p: number[] = [-dx, dx, -dy, dy]
    const q: number[] = [startX - left, right - startX, startY - top, bottom - startY]
    let entry = 0
    let exit = 1
    for (let index = 0; index < 4; index++) {
      if (Math.abs(p[index]) < 0.0001) {
        if (q[index] < 0) return -1
        continue
      }
      const fraction = q[index] / p[index]
      if (p[index] < 0) {
        if (fraction > exit) return -1
        if (fraction > entry) entry = fraction
      } else {
        if (fraction < entry) return -1
        if (fraction < exit) exit = fraction
      }
    }
    return entry >= 0 && entry <= 1 && entry <= exit ? entry : -1
  }

  clearObjectDetailConnector(): void {
    this.hooks.setConnectorLength(0)
  }

  refreshObjectDetailConnector(): void {
    if (!this.hooks.connectorVisible() || !this.infoWindowStore.infoWinVisible || this.objectDetailStore.selectedStatus !== 'Selected' ||
      this.objectDetailStore.selectedName.length === 0) {
      this.clearObjectDetailConnector()
      return
    }
    const projection = this.hooks.gyroGuideProjection()
    if (projection.ok !== true || projection.valid !== true ||
      typeof projection.xRatio !== 'number' || typeof projection.yRatio !== 'number') {
      this.clearObjectDetailConnector()
      return
    }
    const targetX = projection.xRatio * this.hooks.skyWidth()
    const targetY = projection.yRatio * this.hooks.skyHeight()
    if (!Number.isFinite(targetX) || !Number.isFinite(targetY)) {
      this.clearObjectDetailConnector()
      return
    }
    const targetOnScreen = projection.visible === true && targetX >= 0 && targetX <= this.hooks.skyWidth() && targetY >= 0 && targetY <= this.hooks.skyHeight()
    if (this.objectCardPlacementPending) {
      this.objectCardPlacementPending = false
    }
    const left = this.hooks.detailCardX()
    const top = this.hooks.detailCardY()
    const right = left + this.hooks.detailCardWidth()
    const bottom = top + this.hooks.detailCardHeight()
    if (targetOnScreen && pointInsideRect(targetX, targetY, left, top, right, bottom, 2)) {
      this.clearObjectDetailConnector()
      return
    }
    const centerX = (left + right) / 2
    const centerY = (top + bottom) / 2
    const cardIntersection = this.rayRectIntersection(centerX, centerY, targetX, targetY, left, top, right, bottom)
    if (cardIntersection.length !== 2) {
      this.clearObjectDetailConnector()
      return
    }
    let endX = targetX
    let endY = targetY
    if (!targetOnScreen) {
      const screenIntersection = this.rayRectIntersection(centerX, centerY, targetX, targetY, 12, 12, this.hooks.skyWidth() - 12, this.hooks.skyHeight() - 12)
      if (screenIntersection.length !== 2) {
        this.clearObjectDetailConnector()
        return
      }
      endX = screenIntersection[0]
      endY = screenIntersection[1]
    }
    const directionX = endX - centerX
    const directionY = endY - centerY
    const directionLength = Math.sqrt(directionX * directionX + directionY * directionY)
    if (!Number.isFinite(directionLength) || directionLength < 1) {
      return
    }
    const unitX = directionX / directionLength
    const unitY = directionY / directionLength
    const anchorX = cardIntersection[0] + unitX * 5
    const anchorY = cardIntersection[1] + unitY * 5
    if (targetOnScreen) {
      endX -= unitX * 16
      endY -= unitY * 16
    }

    let clippedByUi = false
    let clipFraction = 1
    const connectorUiGap = 6
    const connectorObstacles = this.hooks.objectDetailConnectorObstacles()
    for (let index = 0; index < connectorObstacles.length; index++) {
      const obstacle = connectorObstacles[index]
      const fraction = this.segmentRectEntryFraction(anchorX, anchorY, endX, endY,
        obstacle.left - connectorUiGap, obstacle.top - connectorUiGap,
        obstacle.right + connectorUiGap, obstacle.bottom + connectorUiGap)
      if (fraction < 0) continue
      if (fraction <= 0.015) {
        this.clearObjectDetailConnector()
        return
      }
      if (fraction < clipFraction) {
        clipFraction = fraction
        clippedByUi = true
      }
    }
    const menuStateChanged = this.hooks.connectorLength() > 0 &&
      (this.objectDetailConnectorLastPanelVisible !== this.hooks.panelVisible() ||
        this.objectDetailConnectorLastActivePanel !== this.hooks.activePanel())
    const avoidanceStateChanged = this.hooks.connectorLength() > 0 &&
      this.objectDetailConnectorLastClippedByUi !== clippedByUi
    if (menuStateChanged || avoidanceStateChanged) {
      this.armObjectDetailConnectorTransition()
    }
    this.objectDetailConnectorLastPanelVisible = this.hooks.panelVisible()
    this.objectDetailConnectorLastActivePanel = this.hooks.activePanel()
    this.objectDetailConnectorLastClippedByUi = clippedByUi
    if (clippedByUi) {
      const fullDistance = Math.sqrt(Math.pow(endX - anchorX, 2) + Math.pow(endY - anchorY, 2))
      const safeFraction = Math.max(0, clipFraction - connectorUiGap / Math.max(1, fullDistance))
      endX = anchorX + (endX - anchorX) * safeFraction
      endY = anchorY + (endY - anchorY) * safeFraction
    }
    const dx = endX - anchorX
    const dy = endY - anchorY
    const length = Math.sqrt(dx * dx + dy * dy)
    if (!Number.isFinite(length) || length < 18) {
      this.clearObjectDetailConnector()
      return
    }
    const nextX = (endX + anchorX) / 2
    const nextY = (endY + anchorY) / 2
    const nextLength = Math.min(length, Math.max(this.hooks.skyWidth(), this.hooks.skyHeight()) * 1.5)
    let nextAngle = Math.atan2(dy, dx) * 180 / Math.PI
    while (nextAngle - this.hooks.connectorAngle() > 180) nextAngle -= 360
    while (nextAngle - this.hooks.connectorAngle() < -180) nextAngle += 360
    const nextEndX = endX
    const nextEndY = endY
    const nextTargetOnScreen = targetOnScreen && !clippedByUi
    const nextTargetX = nextTargetOnScreen ? targetX : endX
    const nextTargetY = nextTargetOnScreen ? targetY : endY
    const geometryChanged = this.hooks.connectorLength() <= 0 ||
      Math.abs(nextX - this.hooks.connectorX()) >= 0.75 ||
      Math.abs(nextY - this.hooks.connectorY()) >= 0.75 ||
      Math.abs(nextLength - this.hooks.connectorLength()) >= 0.75 ||
      Math.abs(nextAngle - this.hooks.connectorAngle()) >= 0.35 ||
      Math.abs(nextEndX - this.hooks.connectorEndX()) >= 0.75 ||
      Math.abs(nextEndY - this.hooks.connectorEndY()) >= 0.75 ||
      Math.abs(nextTargetX - this.hooks.connectorTargetX()) >= 0.75 ||
      Math.abs(nextTargetY - this.hooks.connectorTargetY()) >= 0.75 ||
      nextTargetOnScreen !== this.hooks.connectorTargetOnScreen()
    if (!geometryChanged) { return }
    this.hooks.setConnectorX(nextX)
    this.hooks.setConnectorY(nextY)
    this.hooks.setConnectorLength(nextLength)
    this.hooks.setConnectorAngle(nextAngle)
    this.hooks.setConnectorEndX(nextEndX)
    this.hooks.setConnectorEndY(nextEndY)
    this.hooks.setConnectorTargetX(nextTargetX)
    this.hooks.setConnectorTargetY(nextTargetY)
    this.hooks.setConnectorTargetOnScreen(nextTargetOnScreen)
  }
}
