// 详情自动刷新定时器控制器：驱动详情卡数据刷新，并在授权拖拽期间暂停轮询。
//
// 依赖 ObjectDetailStore / InfoWindowStore（只读）；面板/星图状态与宿主收口点均经
// DetailRefreshHostHooks 回注；控制器不 import NAPI/UI。
import { ObjectDetailStore } from '../state/ObjectDetailStore'
import { InfoWindowStore } from '../state/InfoWindowStore'
import { BehaviorHostHooks } from './ControllerHooks'

// 宿主 → 控制器回注：不触碰 UI/宿主私有标志以外的任何 NAPI。
export interface DetailRefreshHostHooks extends BehaviorHostHooks {
  // 面板 / 星图状态读取。
  activePanel(): string
  panelVisible(): boolean
  skyDragging(): boolean
  // 宿主保留的收口点。
  refreshSelectedObject(): void
  scheduleSkyTextureStatusCheck(): void
}

export class DetailRefreshController {
  private objectDetailStore: ObjectDetailStore
  private infoWindowStore: InfoWindowStore
  private hooks: DetailRefreshHostHooks

  // ── 定时器句柄 / 草稿字段（随控制器走，不入 @Observed store）──
  private detailTimer: number = 0
  private detailRefreshing: boolean = false
  private detailRefreshGuard: number = 0

  constructor(objectDetailStore: ObjectDetailStore, infoWindowStore: InfoWindowStore, hooks: DetailRefreshHostHooks) {
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
  }

  pauseDetailRefreshForSkyDrag(): void {
    // Object-info polling uses the same ArkTS-to-Qt queue as panning. Stop it
    // for the duration of a gesture so an open detail card cannot make the sky
    // lag behind the finger.
    this.stopDetailAutoRefresh()
  }

  resumeDetailRefreshAfterSkyDrag(): void {
    if (this.infoWindowStore.infoWinVisible && this.objectDetailStore.selectedStatus === 'Selected') {
      this.startDetailAutoRefresh()
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

  // 生命周期收口（宿主 aboutToDisappear / 清除选中）：停止详情轮询。
  stop(): void {
    this.stopDetailAutoRefresh()
  }
}
