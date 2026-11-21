// Unified HarmonyOS Design corner-radius & motion-duration tokens for the ArkUI shell.
// Follows HarmonyOS Design Guidelines ("同层统一 + 层级正相关", corner-radius-parameter):
//   2vp  micro  (progress tracks, slim indicators)
//   4vp  tag    (corner_radius_level2: micro badges, small status pills)
//   8vp  media  (corner_radius_level4: thumbnails, icon chips, inline tags)
//   12vp control (corner_radius_level6: buttons, inputs, switch rows nested inside cards)
//   16vp card   (corner_radius_level8: content cards, grouped sections, popups)
//   20vp button (corner_radius_level10: standalone primary buttons, floating bars, menus)
//   24vp panel  (corner_radius_level12: floating panels)
//   32vp sheet  (corner_radius_level16: bottom sheets & modal dialogs)
//   999  pill   (full capsule pills & circular icon buttons)

export const UI_RADIUS_MICRO: number = 2
export const UI_RADIUS_TAG: number = 4
export const UI_RADIUS_MEDIA: number = 8
export const UI_RADIUS_CONTROL: number = 12
export const UI_RADIUS_CARD: number = 16
export const UI_RADIUS_BUTTON: number = 20
export const UI_RADIUS_PANEL: number = 24
export const UI_RADIUS_SHEET: number = 32
export const UI_RADIUS_PILL: number = 999

export const UI_MOTION_FAST_MS: number = 140
export const UI_OPTION_ANIMATION_MS: number = 180
export const UI_MOTION_STANDARD_MS: number = 220
export const UI_MOTION_EMPHASIZED_MS: number = 280
