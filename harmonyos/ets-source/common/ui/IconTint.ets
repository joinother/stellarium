// 单色图标着色矩阵：把 RGB 统一压成目标色，保留图标自身 alpha。
// 图标资产里写死的白色 fill/stroke 无法被 Image.fillColor 覆盖，统一用
// colorFilter（SVG 需配合 supportSvg2(true)）着色。
export function tintMatrixFor(color: ResourceColor): number[] {
  if (typeof color === 'string') {
    // 支持 #RRGGBB 与 #AARRGGBB：取末 6 位作为 RGB，alpha 交给图标自身。
    const hex = color.length === 9 ? color.slice(3) : color.slice(1)
    const r = parseInt(hex.slice(0, 2), 16) / 255
    const g = parseInt(hex.slice(2, 4), 16) / 255
    const b = parseInt(hex.slice(4, 6), 16) / 255
    return [
      0, 0, 0, 0, r,
      0, 0, 0, 0, g,
      0, 0, 0, 0, b,
      0, 0, 0, 1, 0
    ]
  }
  return [
    0, 0, 0, 0, 1,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0
  ]
}
