// Unified HarmonyOS Design corner-radius tokens for Desktop Service Cards (FormKit) & Edit Page.
// Zero runtime imports so FormKit sandbox and Node test runners both consume it safely.
// Mirrors HarmonyOS Design hierarchy:
//   2vp  bar     (micro progress/horizon tracks)
//   8vp  badge   (corner_radius_level4: compact status badges & tags)
//   10vp chip    (5-day phase items, 4-tile telemetry grids, compact schedule rows)
//   12vp row     (list items, edit option cells, compact cards)
//   16vp surface (corner_radius_level8: edit page section cards & grouped surfaces)
//   999  pill    (all capsule buttons, pagers, header pills, floating overflow bars & glows)

export const WIDGET_RADIUS_BAR: number = 2
export const WIDGET_RADIUS_BADGE: number = 8
export const WIDGET_RADIUS_CHIP: number = 10
export const WIDGET_RADIUS_ROW: number = 12
export const WIDGET_RADIUS_SURFACE: number = 16
export const WIDGET_RADIUS_PILL: number = 999
