// dock 上方"读数行 + 缩放按钮"的共享几何。
//
// 为什么单独放一处：原生 XComponent 会吞掉 ArkUI 的 onClick，缩放按钮只能像右上角
// 快捷区那样按坐标分派，于是同一组按钮有两处代码在描述它的位置 ——
// 绘制在 panels/shell/PanelChromeExtras.SkyZoomLayer，命中在
// pages/MainWindowNativeNode.skyZoomButtonAt。两边各写一套数字必然漂移：抬升 40vp 时
// 就出现了"点 + 无响应、点 − 变成放大"的整体错位。常量与公式放这里，两边都引用。

/** 读数行（FOV / 时钟）胶囊高度。 */
export const CHROME_CHIP_HEIGHT: number = 36

/** 统一的垂直间距：缩放按钮→读数行、读数行→Dock 都用它。 */
export const CHROME_GAP: number = 10

/** 读数行（FOV / 时钟）上沿相对 dockTop 的偏移（胶囊高 + 间距）。 */
export const CHROME_ROW_OFFSET: number = CHROME_CHIP_HEIGHT + CHROME_GAP

/** 单枚缩放按钮边长。 */
export const CHROME_ZOOM_BUTTON_SIZE: number = 44

/** 两枚缩放按钮之间的间距（竖排与横排共用）。 */
export const CHROME_ZOOM_GAP: number = 8

/** 按钮组内缘与读数行锚点之间的水平留白（与时钟层 padding-right 对称）。 */
export const CHROME_ZOOM_EDGE_PADDING: number = 4

/** 竖排按钮组高：两枚按钮 + 一个间距（= 96）。 */
export const CHROME_ZOOM_COLUMN_HEIGHT: number = CHROME_ZOOM_BUTTON_SIZE * 2 + CHROME_ZOOM_GAP

/** 横排按钮组高：一行（= 44）。 */
export const CHROME_ZOOM_ROW_HEIGHT: number = CHROME_ZOOM_BUTTON_SIZE

/** @deprecated 统一使用 CHROME_GAP；保留别名避免外部引用断裂。 */
export const CHROME_ZOOM_ROW_GAP: number = CHROME_GAP

/** 按钮组外框高度：竖排 96，横排 44。 */
export function chromeZoomLayerHeight(horizontal: boolean): number {
  return horizontal ? CHROME_ZOOM_ROW_HEIGHT : CHROME_ZOOM_COLUMN_HEIGHT
}

/**
 * 按钮组外框上边 y。
 * @param rowY 读数行上沿（见宿主 chromeRowY()）
 */
export function chromeZoomLayerTop(rowY: number, horizontal: boolean): number {
  // 两种排列都让按钮组底边与读数行保持 CHROME_GAP。
  return rowY - CHROME_GAP - chromeZoomLayerHeight(horizontal)
}

/**
 * 第 index 枚按钮的上边 y（0 = "+" 放大，1 = "−" 缩小）。
 * 竖排自上而下为 + / −，横排自左而右为 + / −（两者 y 相同）。
 */
export function chromeZoomButtonTop(rowY: number, horizontal: boolean, index: number): number {
  const top = chromeZoomLayerTop(rowY, horizontal)
  if (horizontal) {
    return top
  }
  return index === 0 ? top : top + CHROME_ZOOM_BUTTON_SIZE + CHROME_ZOOM_GAP
}

/**
 * 第 index 枚按钮的左边 x（横排才有意义；竖排两枚 x 相同）。
 * @param layerLeft 按钮组外框左边（宿主 chromeRowPosXLeft()）
 */
export function chromeZoomButtonLeft(layerLeft: number, horizontal: boolean, index: number): number {
  const left = layerLeft + CHROME_ZOOM_EDGE_PADDING
  if (!horizontal || index === 0) {
    return left
  }
  return left + CHROME_ZOOM_BUTTON_SIZE + CHROME_ZOOM_GAP
}
