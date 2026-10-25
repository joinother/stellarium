export function dockItemIndex(x: number, y: number, width: number, height: number,
  count: number, padding: number): number {
  if (count <= 0 || width <= padding * 2 || x < padding || x >= width - padding || y < 0 || y > height) {
    return -1
  }
  return Math.floor((x - padding) * count / (width - padding * 2))
}
