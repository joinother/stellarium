// 视图中心坐标叠层行为控制器。
//
// 负责视图中心坐标叠层的显示开关、坐标系 / 历元切换、50ms 轮询读数刷新与叠层拖拽落位。
// 控制器不 import NAPI/UI：桥经 CommandPort；开关 / 坐标系 / 历元写 OverlayStore
//（ViewCoordinateSettings / ViewCenterCoordinateOverlay 消费）。applicationInForeground / saveAppSettings /
// stopSkyInertia 与叠层高频 @State（主副文案、偏移）留宿主，经 ViewCoordinateHostHooks 回注，避免逐帧写
// 触发重渲染；utcOffsetHours 为跨域共用（Dock 时钟 / 时间格式化 / TimeWheel），留宿主。
// 定时器 viewCoordinateTimer 由控制器自持（stopViewCoordinateTimer / syncViewCoordinateTimer）。
import { StellariumBridgeResponse } from '../pages/StellariumTypes'
import { I18n } from '../pages/I18n'
import { CommandPort } from '../bridge/CommandPort'
import { OverlayStore } from '../state/OverlayStore'
import { touchScreenX, touchScreenY } from '../common/derive/geometry'

export interface ViewCoordinateHostHooks {
  applicationInForeground(): boolean
  saveAppSettings(): void
  stopSkyInertia(): void
  viewCoordinateOffsetX(): number
  setViewCoordinateOffsetX(value: number): void
  viewCoordinateOffsetY(): number
  setViewCoordinateOffsetY(value: number): void
  setViewCoordinatePrimaryText(text: string): void
  setViewCoordinateSecondaryText(text: string): void
  viewCoordinateRestOffsetX(): number
  viewCoordinateRestOffsetY(): number
}

export class ViewCoordinateController {
  private port: CommandPort
  private overlayStore: OverlayStore
  private hooks: ViewCoordinateHostHooks
  // 拖拽/请求草稿字段：不入 @Observed store；4 个可观测 @State 留宿主经 hooks 读写。
  private viewCoordinateDragging: boolean = false
  private viewCoordinateDragStartX: number = 0
  private viewCoordinateDragStartY: number = 0
  private viewCoordinateDragStartOffsetX: number = 0
  private viewCoordinateDragStartOffsetY: number = 0
  private viewCoordinateSnapshot: StellariumBridgeResponse = {}
  private viewCoordinateTimer: number = 0
  private viewCoordinateRequestPending: boolean = false

  constructor(port: CommandPort, overlayStore: OverlayStore, hooks: ViewCoordinateHostHooks) {
    this.port = port
    this.overlayStore = overlayStore
    this.hooks = hooks
  }

  // 50ms 轮询回包 → 存快照 → 按坐标系拆文案；不可见 / 非前台 / 请求在途时跳过。
  refreshViewCenterCoordinates(): void {
    if (!this.overlayStore.viewCoordinatesVisible || !this.hooks.applicationInForeground() || this.viewCoordinateRequestPending) {
      return
    }
    this.viewCoordinateRequestPending = true
    this.port.requestWhenReady('getViewCenterCoordinates', '', (result: StellariumBridgeResponse) => {
      this.viewCoordinateRequestPending = false
      if (!this.overlayStore.viewCoordinatesVisible || !this.hooks.applicationInForeground()) { return }
      this.viewCoordinateSnapshot = result
      this.applyViewCoordinateSnapshot()
    }, () => {
      this.viewCoordinateRequestPending = false
    }, 0, 34, 8)
  }

  // 按当前坐标系 / 历元把快照转成主副读数。
  applyViewCoordinateSnapshot(): void {
    const snapshot = this.viewCoordinateSnapshot
    if (this.overlayStore.viewCoordinateFamily === 'horizontal') {
      this.hooks.setViewCoordinatePrimaryText(snapshot.azimuthText ?? '--')
      this.hooks.setViewCoordinateSecondaryText(snapshot.altitudeText ?? '--')
    } else if (this.overlayStore.viewCoordinateFamily === 'galactic') {
      this.hooks.setViewCoordinatePrimaryText(snapshot.galacticLongitude ?? '--')
      this.hooks.setViewCoordinateSecondaryText(snapshot.galacticLatitude ?? '--')
    } else if (this.overlayStore.viewEquatorialEpoch === 'ofDate') {
      this.hooks.setViewCoordinatePrimaryText(snapshot.ofDateRa ?? '--')
      this.hooks.setViewCoordinateSecondaryText(snapshot.ofDateDec ?? '--')
    } else {
      this.hooks.setViewCoordinatePrimaryText(snapshot.j2000Ra ?? '--')
      this.hooks.setViewCoordinateSecondaryText(snapshot.j2000Dec ?? '--')
    }
  }

  // 停止 50ms 轮询。
  stopViewCoordinateTimer(): void {
    if (this.viewCoordinateTimer !== 0) {
      clearInterval(this.viewCoordinateTimer)
      this.viewCoordinateTimer = 0
    }
  }

  // 可见且前台时启动 50ms 轮询，否则停止。
  syncViewCoordinateTimer(): void {
    this.stopViewCoordinateTimer()
    if (!this.overlayStore.viewCoordinatesVisible || !this.hooks.applicationInForeground()) { return }
    this.refreshViewCenterCoordinates()
    this.viewCoordinateTimer = setInterval(() => {
      this.refreshViewCenterCoordinates()
    }, 50)
  }

  // 设置坐标叠层可见性并持久化设置。
  setViewCoordinatesVisible(visible: boolean): void {
    this.overlayStore.viewCoordinatesVisible = visible
    this.hooks.saveAppSettings()
    this.syncViewCoordinateTimer()
  }

  // 切换坐标系并立即按快照刷新读数。
  setViewCoordinateFamily(family: string): void {
    this.overlayStore.viewCoordinateFamily = family
    this.applyViewCoordinateSnapshot()
    this.hooks.saveAppSettings()
  }

  // 切换赤道历元并立即按快照刷新读数。
  setViewEquatorialEpoch(epoch: string): void {
    this.overlayStore.viewEquatorialEpoch = epoch
    this.applyViewCoordinateSnapshot()
    this.hooks.saveAppSettings()
  }

  // 叠层拖拽：Down 记起点并停惯性 → Move 写偏移 → Up/Cancel 落位回夹。
  handleViewCoordinateTouch(event: TouchEvent): void {
    const points = event.touches.length > 0 ? event.touches : event.changedTouches
    if (points.length === 0) { return }
    const point = points[0]
    const x = touchScreenX(point)
    const y = touchScreenY(point)
    if (event.type === TouchType.Down) {
      this.viewCoordinateDragging = true
      this.viewCoordinateDragStartX = x
      this.viewCoordinateDragStartY = y
      this.viewCoordinateDragStartOffsetX = this.hooks.viewCoordinateOffsetX()
      this.viewCoordinateDragStartOffsetY = this.hooks.viewCoordinateOffsetY()
      this.hooks.stopSkyInertia()
      return
    }
    if (event.type === TouchType.Move && this.viewCoordinateDragging) {
      this.hooks.setViewCoordinateOffsetX(this.viewCoordinateDragStartOffsetX + x - this.viewCoordinateDragStartX)
      this.hooks.setViewCoordinateOffsetY(this.viewCoordinateDragStartOffsetY + y - this.viewCoordinateDragStartY)
      return
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.viewCoordinateDragging = false
      this.hooks.setViewCoordinateOffsetX(this.hooks.viewCoordinateRestOffsetX())
      this.hooks.setViewCoordinateOffsetY(this.hooks.viewCoordinateRestOffsetY())
    }
  }

  // 写指针坐标设置并回读状态。
  setPointerCoordinates(setting: string, value: string): void {
    // Optimistically mirror the change so the panel does not reload (and
    // flicker) on success; only reload when the bridge rejects it.
    this.applyPointerCoordinatesSetting(setting, value)
    this.port.requestWhenReady('setPointerCoordinates', setting + '|' + value, (r: StellariumBridgeResponse) => {
      if (r.ok !== true) {
        this.overlayStore.pointerCoordinatesStatus = I18n.t('plugin_action_failed')
        this.overlayStore.loadPointerCoordinates()
      }
    }, () => { this.overlayStore.pointerCoordinatesStatus = I18n.t('plugin_action_failed') }, 0, 100, 15)
  }

  private applyPointerCoordinatesSetting(setting: string, value: string): void {
    const on = value === '1' || value === 'true'
    if (setting === 'enabled') this.overlayStore.pointerCoordinatesEnabled = on
    else if (setting === 'startup') this.overlayStore.pointerCoordinatesStartup = on
    else if (setting === 'button') this.overlayStore.pointerCoordinatesButton = on
    else if (setting === 'constellation') this.overlayStore.pointerCoordinatesConstellation = on
    else if (setting === 'crossedLines') this.overlayStore.pointerCoordinatesCrossedLines = on
    else if (setting === 'elongation') this.overlayStore.pointerCoordinatesElongation = on
    else if (setting === 'system') this.overlayStore.pointerCoordinatesSystem = value
    else if (setting === 'place') this.overlayStore.pointerCoordinatesPlace = value
  }
}
