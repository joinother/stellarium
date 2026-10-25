// 几何 / 触摸 / 布局常量纯函数。
// 依据计划 §14.2 轨道 A1-6，逐字从 pages/MainWindowNativeNode.ets 的私有方法迁出。
// 这些函数零 this、零 IO、零桥、零 store 依赖，只依赖入参、静态常量与纯计算；
// 宿主与 panels 直连本模块（§14.8 规则 6：不 import store）。
// 触摸/命中类（pointInsideRect / pointOverlapsUiObstacle / touch*）逐字保留比较边界，
// 不得改写 <= / >= / ??

import { SkyUiObstacle } from '../../pages/MainWindowModels'
import { clamp } from './astro'

// 方位条高度（vp，1..96）。
export function azBarHeight(azimuth: number | undefined): number {
  const value: number = azimuth !== undefined ? azimuth : 0
  return Math.max(1, Math.min(96, value / 360 * 96))
}

// 点在矩形内（含 margin 外扩）。
export function pointInsideRect(x: number, y: number, left: number, top: number, right: number,
  bottom: number, margin: number = 0): boolean {
  return x >= left - margin && x <= right + margin && y >= top - margin && y <= bottom + margin
}

// 点与 UI 障碍矩形重叠（含 margin 外扩）。
export function pointOverlapsUiObstacle(x: number, y: number, obstacle: SkyUiObstacle,
  margin: number = 10): boolean {
  return x >= obstacle.left - margin && x <= obstacle.right + margin &&
    y >= obstacle.top - margin && y <= obstacle.bottom + margin
}

// 触摸窗口坐标（优先 point.x/y，回退 windowX/windowY）。
export function touchWindowX(point: TouchObject): number {
  return point.x ?? point.windowX ?? 0
}

export function touchWindowY(point: TouchObject): number {
  return point.y ?? point.windowY ?? 0
}

// 触摸屏幕坐标（优先 windowX/windowY，回退 point.x/y）。
export function touchScreenX(point: TouchObject): number {
  return point.windowX ?? point.x ?? 0
}

export function touchScreenY(point: TouchObject): number {
  return point.windowY ?? point.y ?? 0
}

// 手机端右上快捷区左上角 Y（与顶部搜索栏同高）。
export function compactTopQuickY(): number {
  return 50
}

// 平板展开布局 + 搜索面板打开时，始终用紧凑摘要（不挤完整大卡片）。
export function useExpandedDetailSummary(): boolean {
  return false
}

// 展开态摘要卡高度（vp）。
export function expandedDetailSummaryHeight(): number {
  return 230
}

// 平板对象检查器（当前构型关闭）。
export function useTabletObjectInspector(): boolean {
  return false
}

// 手机端详情卡 peek（当前构型关闭）。
export function isPhoneDetailPeek(): boolean {
  return false
}

// 紧凑对象卡 peek 基础 Y（vp）。
export function baseCompactObjectPeekY(): number {
  return 92
}

// ===========================================================================
// §14 A2-4（2026-10-04）：布局 / 几何族（A2-G）。
// 下面这批函数逐字从宿主私有方法迁出，只做两件事：
//   ① `this.<宿主字段>` → 显式入参；② 被迁函数之间的 `this.f()` → 本模块 f()。
// 比较边界 / 取整 / 回退分支逐字保留（这些是命中性与布局性代码，语义偏差不报编译错）。
// 宿主在调用点传入 `this.EDGE_MARGIN`、`this.skyWidth` 等保留字段值；
// A-保留方法（bottomCardWidth / hoverBottomCardY / clampedObjectCardOffset* / dockTop /
// guideCardWidth / compactPanelHeight / scriptControlSafeTop / detailCard* 等）仍留宿主，
// 其求值结果按需作为显式入参传入。
// ===========================================================================

// 左侧竖栏顶部留白（原宿主 railTop）。
export function railTop(edgeMargin: number): number {
  return edgeMargin
}

// 展开态主面板左缘（原宿主 expandedMainPanelLeft）。
export function expandedMainPanelLeft(edgeMargin: number, panelOffsetX: number): number {
  return edgeMargin + panelOffsetX
}

// 面板顶缘（原宿主 panelTop）。
export function panelTop(edgeMargin: number, panelOffsetY: number): number {
  return edgeMargin + panelOffsetY
}

// 面板命中区左缘（原宿主 panelLeft）。
export function panelLeft(isExpandedLayout: boolean, skyWidth: number, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  if (isExpandedLayout) {
    return expandedMainPanelLeft(edgeMargin, panelOffsetX)
  }
  return skyWidth - panelWidth + panelOffsetX
}

// 面板命中区右缘（原宿主 panelRight）。
export function panelRight(isExpandedLayout: boolean, skyWidth: number, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  return panelLeft(isExpandedLayout, skyWidth, panelWidth, panelOffsetX, edgeMargin) + panelWidth
}

// 展开态详情区可用宽度（原宿主 expandedDetailAvailableWidth）。
export function expandedDetailAvailableWidth(skyWidth: number, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  const detailLeft = expandedMainPanelLeft(edgeMargin, panelOffsetX) + panelWidth + 18
  return skyWidth - edgeMargin - detailLeft
}

// 展开态摘要卡基础 X（原宿主 baseExpandedDetailSummaryX）。
export function baseExpandedDetailSummaryX(panelWidth: number, panelOffsetX: number,
  edgeMargin: number): number {
  return expandedMainPanelLeft(edgeMargin, panelOffsetX) + panelWidth + 18
}

// 展开态摘要卡基础 Y（原宿主 baseExpandedDetailSummaryY）。
export function baseExpandedDetailSummaryY(edgeMargin: number): number {
  return Math.max(edgeMargin + 16, 48)
}

// 平板检查器基础 X（原宿主 baseTabletInspectorX）。
export function baseTabletInspectorX(edgeMargin: number): number {
  return edgeMargin + 12
}

// 平板检查器基础 Y（原宿主 baseTabletInspectorY）。
export function baseTabletInspectorY(edgeMargin: number): number {
  return Math.max(edgeMargin + 56, 58)
}

// 平板检查器高度（原宿主 tabletInspectorHeight）。
export function tabletInspectorHeight(skyHeight: number, edgeMargin: number): number {
  return Math.max(360, skyHeight - baseTabletInspectorY(edgeMargin) - 84)
}

// 底部详情卡基础 X（原宿主 baseBottomCardX）。
export function baseBottomCardX(isExpandedLayout: boolean, isFoldHoverLayout: boolean,
  skyWidth: number, edgeMargin: number, bottomCardWidth: number): number {
  if (!isExpandedLayout && !isFoldHoverLayout) { return 16 }
  if (!isExpandedLayout) { return Math.max(24, (skyWidth - bottomCardWidth) / 2) }
  return Math.max(edgeMargin + 92, skyWidth - bottomCardWidth - edgeMargin + 16)
}

// 底部详情卡基础 Y（原宿主 baseBottomCardY）。
// 手机 / 半折：**贴在安全区顶部** —— 详情卡是浮在星图上的读数卡，顶部留白只会挤掉天空，
// 故不再保留旧的 86–126vp 下限（用户要求「整体浮窗继续往上提」）。
// 平板（展开态）：让开左侧轨道（`edgeMargin + 76`，下限 92），同时不高于安全区。
export function baseBottomCardY(isExpandedLayout: boolean, skyHeight: number,
  edgeMargin: number, safeTop: number): number {
  if (isExpandedLayout) { return Math.max(edgeMargin + 76, 92, safeTop) }
  return Math.max(0, Math.min(safeTop, skyHeight - 120))
}

// 展开态 Dock 左占用（原宿主 expandedDockOccupiedLeft）。
export function expandedDockOccupiedLeft(panelVisible: boolean, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  if (panelVisible) {
    return expandedMainPanelLeft(edgeMargin, panelOffsetX) + panelWidth + 16
  }
  return edgeMargin
}

// 展开态 Dock 宽度（原宿主 expandedDockWidth）。
export function expandedDockWidth(skyWidth: number, panelVisible: boolean, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  const right = edgeMargin
  const available = Math.max(280, skyWidth - expandedDockOccupiedLeft(panelVisible, panelWidth, panelOffsetX, edgeMargin) - right)
  const squeeze = Math.max(0, expandedDockOccupiedLeft(panelVisible, panelWidth, panelOffsetX, edgeMargin) - edgeMargin)
  const target = skyWidth >= 520 ? 720 : 640
  return clamp(target - squeeze * 0.55, Math.min(360, available), Math.min(target, available))
}

// 展开态 Dock 左缘（原宿主 expandedDockLeft）。
export function expandedDockLeft(skyWidth: number, panelVisible: boolean, panelWidth: number,
  panelOffsetX: number, edgeMargin: number): number {
  const available = Math.max(280, skyWidth - expandedDockOccupiedLeft(panelVisible, panelWidth, panelOffsetX, edgeMargin) - edgeMargin)
  return expandedDockOccupiedLeft(panelVisible, panelWidth, panelOffsetX, edgeMargin) +
    Math.max(0, (available - expandedDockWidth(skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin)) / 2)
}

// Dock 像素宽度（原宿主 dockWidthPixels）。
export function dockWidthPixels(isExpandedLayout: boolean, skyWidth: number, panelVisible: boolean,
  panelWidth: number, panelOffsetX: number, edgeMargin: number,
  compactDockWidthPercent: number): number {
  return isExpandedLayout
    ? expandedDockWidth(skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin)
    : skyWidth * compactDockWidthPercent / 100
}

// Dock 左缘（原宿主 dockLeft）。
export function dockLeft(isExpandedLayout: boolean, skyWidth: number, panelVisible: boolean,
  panelWidth: number, panelOffsetX: number, edgeMargin: number,
  compactDockWidthPercent: number): number {
  if (isExpandedLayout) {
    return expandedDockLeft(skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin)
  }
  return Math.max(0, (skyWidth - dockWidthPixels(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)) / 2)
}

// chrome 行左缘（原宿主 chromeRowPosXLeft）。
export function chromeRowPosXLeft(isExpandedLayout: boolean, edgeMargin: number, skyWidth: number,
  panelVisible: boolean, panelWidth: number, panelOffsetX: number,
  compactDockWidthPercent: number): number {
  return isExpandedLayout
    ? edgeMargin
    : dockLeft(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)
}

// chrome 行右缘（原宿主 chromeRowPosXRight）。
export function chromeRowPosXRight(isExpandedLayout: boolean, skyWidth: number, edgeMargin: number,
  panelVisible: boolean, panelWidth: number, panelOffsetX: number,
  compactDockWidthPercent: number): number {
  if (isExpandedLayout) {
    return skyWidth - edgeMargin - dockWidthPixels(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)
  }
  return dockLeft(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)
}

// 导览卡高度（原宿主 guideCardHeight）。
export function guideCardHeight(skyHeight: number, scriptControlSafeTop: number): number {
  return Math.max(160, Math.min(390, skyHeight - scriptControlSafeTop - 24))
}

// 导览卡 X（原宿主 guideCardX）。
export function guideCardX(isExpandedLayout: boolean, skyWidth: number, guideCardWidth: number,
  scriptControlOffsetX: number): number {
  return clamp((isExpandedLayout ? 12 : (skyWidth - guideCardWidth) / 2) + scriptControlOffsetX,
    8, Math.max(8, skyWidth - guideCardWidth - 8))
}

// 导览卡 Y（原宿主 guideCardY）。
export function guideCardY(skyHeight: number, cardHeight: number, scriptControlSafeTop: number,
  scriptControlOffsetY: number): number {
  return clamp(skyHeight - cardHeight - 16 + scriptControlOffsetY,
    scriptControlSafeTop, Math.max(scriptControlSafeTop, skyHeight - cardHeight - 12))
}

// 脚本控制条宽度（原宿主 scriptControlWidth）。
export function scriptControlWidth(skyWidth: number, replaying: boolean): number {
  return Math.max(280, Math.min(skyWidth - 24, replaying ? 520 : 500))
}

// 脚本控制条 X（原宿主 scriptControlX）。
export function scriptControlX(skyWidth: number, replaying: boolean, scriptControlOffsetX: number): number {
  const maxX = Math.max(8, skyWidth - scriptControlWidth(skyWidth, replaying) - 8)
  return clamp(12 + scriptControlOffsetX, 8, maxX)
}

// 脚本控制条 Y（原宿主 scriptControlY）。
export function scriptControlY(skyHeight: number, scriptControlSafeTop: number, controlHeight: number,
  scriptControlOffsetY: number): number {
  const safeTop = scriptControlSafeTop
  const maxY = Math.max(safeTop, skyHeight - controlHeight - 12)
  return clamp(safeTop + scriptControlOffsetY, safeTop, maxY)
}

// 面板返回命中（原宿主 isPanelBackPoint）。
export function isPanelBackPoint(x: number, y: number, canGoBack: boolean,
  isExpandedLayout: boolean, isFoldHoverLayout: boolean, panelWidth: number, skyWidth: number,
  compactPanelTop: number, panelOffsetX: number,
  edgeMargin: number, expandedPanelTopValue: number): boolean {
  if (!canGoBack) return false
  const width = isExpandedLayout ? panelWidth : skyWidth * (isFoldHoverLayout ? 0.72 : 0.94)
  const left = isExpandedLayout ? panelLeft(isExpandedLayout, skyWidth, panelWidth, panelOffsetX, edgeMargin) : (skyWidth - width) / 2
  const top = isExpandedLayout ? expandedPanelTopValue : compactPanelTop
  return x >= left - 8 && x <= left + Math.min(width * 0.52, 142) && y >= top - 10 && y <= top + 82
}

// Dock 命中（原宿主 isDockPoint）。
export function isDockPoint(x: number, y: number, polarScopeVisible: boolean,
  isExpandedLayout: boolean, skyWidth: number, skyHeight: number, panelVisible: boolean,
  panelWidth: number, panelOffsetX: number, edgeMargin: number, compactDockWidthPercent: number,
  dockTopValue: number, dockHeightValue: number): boolean {
  if (polarScopeVisible) return false
  const left = dockLeft(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)
  const right = left + dockWidthPixels(isExpandedLayout, skyWidth, panelVisible, panelWidth, panelOffsetX, edgeMargin, compactDockWidthPercent)
  const top = dockTopValue
  // The hit layer stops at the Dock's own bottom so the navigation strip below
  // it is not swallowed by the sky-blocking layer.
  const bottom = top + dockHeightValue
  return x >= left - 8 && x <= right + 8 && y >= top - 8 && y <= bottom
}

// 对象操作条 Y（原宿主 objectActionBarY）。
export function objectActionBarY(bottomCardY: number, expandedDetailSummaryY: number,
  compactObjectPeekY: number, hoverBottomCardY: number, isFoldHoverLayout: boolean): number {
  let cardY = bottomCardY
  if (useExpandedDetailSummary()) { cardY = expandedDetailSummaryY }
  if (isPhoneDetailPeek()) { cardY = compactObjectPeekY }
  if (isFoldHoverLayout && !useExpandedDetailSummary()) { cardY = hoverBottomCardY }
  return Math.max(8, cardY - 44)
}

// 对象详情卡命中（原宿主 isObjectDetailCardPoint）。
export function isObjectDetailCardPoint(x: number, y: number, isRendered: boolean, left: number,
  top: number, cardWidth: number, cardHeight: number): boolean {
  if (!isRendered) { return false }
  return x >= left - 8 && x <= left + cardWidth + 8 &&
    y >= top - 8 && y <= top + cardHeight + 8
}

// 展开型详情摘要是否可显示 / 其可用宽（原宿主 canShowExpandedDetailSummary /
// expandedDetailSummaryWidth，A2-6）。均只读宿主布局字段（skyWidth/panelWidth/panelOffsetX）
// 与未登记常量 EDGE_MARGIN，改为显式入参；函数体逐字搬入。
export function canShowExpandedDetailSummary(skyWidth: number, panelWidth: number, panelOffsetX: number,
  edgeMargin: number): boolean {
  return expandedDetailAvailableWidth(skyWidth, panelWidth, panelOffsetX, edgeMargin) >= 140
}

export function expandedDetailSummaryWidth(skyWidth: number, panelWidth: number, panelOffsetX: number,
  edgeMargin: number): number {
  return clamp(expandedDetailAvailableWidth(skyWidth, panelWidth, panelOffsetX, edgeMargin), 140, 300)
}
