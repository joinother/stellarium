import { CustomColors, CustomTheme, Theme } from '@kit.ArkUI'

const DAY_ACCENT: string = '#5B93BF'
const NIGHT_ACCENT: string = '#F00000'
// Dock / 快捷项未激活图标：日间近白，夜间深暗红（与亮红激活态拉开对比）。
const DAY_IDLE_ICON: string = '#E5FFFFFF'
const NIGHT_IDLE_ICON: string = '#8A3020'
// 详情卡三个主要参数的数值：日间近白，夜间亮红（标签仍用暗红）。
const DAY_METRIC_VALUE: string = '#E7F7FF'
const NIGHT_METRIC_VALUE: string = '#F00000'

class StellariumDayColors implements CustomColors {
  brand: ResourceColor = 'rgba(143,187,214,0.88)'
  primary: ResourceColor = 'rgba(0,0,0,0.50)'
  onPrimary: ResourceColor = 'rgba(35,74,98,0.58)'
  container: ResourceColor = '#C9A6FF'
  warning: ResourceColor = '#FFD54F'
  alert: ResourceColor = '#C0392B'
  confirm: ResourceColor = '#81C784'
  fontPrimary: ResourceColor = '#E5FFFFFF'
  fontSecondary: ResourceColor = '#99FFFFFF'
  fontTertiary: ResourceColor = '#8FBBD6'
  fontFourth: ResourceColor = '#E7F7FF'
  fontEmphasize: ResourceColor = '#FFFFFFFF'
  fontOnPrimary: ResourceColor = '#E5FFFFFF'
  fontOnSecondary: ResourceColor = '#F59B9B'
  fontOnTertiary: ResourceColor = '#9B6E39'
  fontOnFourth: ResourceColor = '#9EC8DC'
  iconPrimary: ResourceColor = '#E5FFFFFF'
  iconSecondary: ResourceColor = '#B8E4FF'
  iconTertiary: ResourceColor = '#7FB3DC'
  iconFourth: ResourceColor = '#8EC9E9'
  iconEmphasize: ResourceColor = 'rgba(241,194,125,0.08)'
  iconSubEmphasize: ResourceColor = '#70C8FF'
  iconOnPrimary: ResourceColor = '#7D3C98'
  iconOnSecondary: ResourceColor = 'rgba(68,136,178,0.72)'
  iconOnTertiary: ResourceColor = '#555555'
  iconOnFourth: ResourceColor = 'rgba(0,0,0,0.22)'
  backgroundPrimary: ResourceColor = '#07101B'
  backgroundSecondary: ResourceColor = 'rgba(91,147,191,0.06)'
  backgroundTertiary: ResourceColor = 'rgba(2,6,12,0.72)'
  backgroundFourth: ResourceColor = 'rgba(255,255,255,0.045)'
  backgroundEmphasize: ResourceColor = DAY_ACCENT
  compForegroundPrimary: ResourceColor = '#33FFFFFF'
  compBackgroundPrimary: ResourceColor = 'rgba(255,255,255,0.06)'
  compBackgroundPrimaryTran: ResourceColor = 'rgba(91,147,191,0.12)'
  compBackgroundPrimaryContrary: ResourceColor = '#E5FFFFFF'
  compBackgroundGray: ResourceColor = 'rgba(15, 20, 30, 0.82)'
  compBackgroundSecondary: ResourceColor = 'rgba(91,147,191,0.12)'
  compBackgroundTertiary: ResourceColor = 'rgba(255,255,255,0.04)'
  compBackgroundEmphasize: ResourceColor = 'rgba(79,148,211,0.55)'
  compBackgroundNeutral: ResourceColor = 'rgba(225,241,250,0.34)'
  compEmphasizeSecondary: ResourceColor = 'rgba(91,147,191,0.92)'
  compEmphasizeTertiary: ResourceColor = 'rgba(80,140,200,0.20)'
  compDivider: ResourceColor = 'rgba(147,215,255,0.10)'
  compCommonContrary: ResourceColor = '#B8D4EF'
  compBackgroundFocus: ResourceColor = '#2E7D32'
  compFocusedPrimary: ResourceColor = 'rgba(127,179,220,0.7)'
  compFocusedSecondary: ResourceColor = 'rgba(127,179,220,0.22)'
  compFocusedTertiary: ResourceColor = '#555555'
  interactiveHover: ResourceColor = 'rgba(107,163,214,0.15)'
  interactivePressed: ResourceColor = 'rgba(255,255,255,0.05)'
  interactiveFocus: ResourceColor = 'rgba(214,238,255,0.14)'
  interactiveActive: ResourceColor = 'rgba(255,255,255,0.12)'
  interactiveSelect: ResourceColor = 'rgba(180,60,50,0.22)'
  interactiveClick: ResourceColor = 'rgba(0, 0, 0, 0.12)'
}

class StellariumNightColors implements CustomColors {
  brand: ResourceColor = 'rgba(240,60,40,0.88)'
  primary: ResourceColor = 'rgba(8,2,1,0.60)'
  onPrimary: ResourceColor = 'rgba(90,20,12,0.60)'
  container: ResourceColor = '#FF5555'
  warning: ResourceColor = '#D4A030'
  alert: ResourceColor = '#FF3333'
  confirm: ResourceColor = '#81C784'
  fontPrimary: ResourceColor = '#F00000'
  fontSecondary: ResourceColor = '#A03020'
  fontTertiary: ResourceColor = '#A03020'
  fontFourth: ResourceColor = '#7A2818'
  fontEmphasize: ResourceColor = '#FF2222'
  fontOnPrimary: ResourceColor = '#1A0505'
  fontOnSecondary: ResourceColor = '#FF5555'
  fontOnTertiary: ResourceColor = '#9B6E39'
  fontOnFourth: ResourceColor = '#6A2015'
  iconPrimary: ResourceColor = '#F00000'
  iconSecondary: ResourceColor = '#F00000'
  iconTertiary: ResourceColor = '#8A3020'
  iconFourth: ResourceColor = '#F00000'
  iconEmphasize: ResourceColor = 'rgba(200,140,40,0.12)'
  iconSubEmphasize: ResourceColor = '#FF0000'
  iconOnPrimary: ResourceColor = '#7A2030'
  iconOnSecondary: ResourceColor = 'rgba(120,30,20,0.80)'
  iconOnTertiary: ResourceColor = '#8A3020'
  iconOnFourth: ResourceColor = 'rgba(0,0,0,0.35)'
  backgroundPrimary: ResourceColor = '#150505'
  backgroundSecondary: ResourceColor = 'rgba(120,20,10,0.15)'
  backgroundTertiary: ResourceColor = 'rgba(24,6,4,0.78)'
  backgroundFourth: ResourceColor = 'rgba(120,20,10,0.14)'
  backgroundEmphasize: ResourceColor = NIGHT_ACCENT
  compForegroundPrimary: ResourceColor = 'rgba(240,0,0,0.20)'
  compBackgroundPrimary: ResourceColor = 'rgba(120,30,15,0.50)'
  compBackgroundPrimaryTran: ResourceColor = 'rgba(140,30,15,0.25)'
  compBackgroundPrimaryContrary: ResourceColor = '#A03020'
  compBackgroundGray: ResourceColor = 'rgba(25, 6, 4, 0.85)'
  compBackgroundSecondary: ResourceColor = 'rgba(140,30,15,0.25)'
  compBackgroundTertiary: ResourceColor = 'rgba(180,40,20,0.12)'
  compBackgroundEmphasize: ResourceColor = 'rgba(180,30,15,0.55)'
  compBackgroundNeutral: ResourceColor = 'rgba(240,60,40,0.40)'
  compEmphasizeSecondary: ResourceColor = 'rgba(180,30,15,0.85)'
  compEmphasizeTertiary: ResourceColor = 'rgba(200,60,30,0.25)'
  compDivider: ResourceColor = 'rgba(200,60,30,0.20)'
  compCommonContrary: ResourceColor = '#7A2818'
  compBackgroundFocus: ResourceColor = '#9A2A1A'
  compFocusedPrimary: ResourceColor = 'rgba(200,50,30,0.5)'
  compFocusedSecondary: ResourceColor = 'rgba(120,30,20,0.18)'
  compFocusedTertiary: ResourceColor = '#4A2018'
  interactiveHover: ResourceColor = 'rgba(100,20,10,0.15)'
  interactivePressed: ResourceColor = 'rgba(160,40,20,0.12)'
  interactiveFocus: ResourceColor = 'rgba(200,60,30,0.25)'
  interactiveActive: ResourceColor = 'rgba(200,40,30,0.20)'
  interactiveSelect: ResourceColor = 'rgba(200,50,30,0.28)'
  interactiveClick: ResourceColor = 'rgba(0, 0, 0, 0.30)'
}

export class StellariumCustomTheme implements CustomTheme {
  colors?: CustomColors
  constructor(c: CustomColors) { this.colors = c }
}

const DAY_COLORS: CustomColors = new StellariumDayColors()
const NIGHT_COLORS: CustomColors = new StellariumNightColors()
const DAY_THEME: CustomTheme = new StellariumCustomTheme(DAY_COLORS)
const NIGHT_THEME: CustomTheme = new StellariumCustomTheme(NIGHT_COLORS)

export function stellariumTheme(nightMode: boolean): CustomTheme {
  return nightMode ? NIGHT_THEME : DAY_THEME
}

export function accentForNightMode(nightMode: boolean): string {
  return nightMode ? NIGHT_ACCENT : DAY_ACCENT
}

export interface ThemeSlots {
  text: ResourceColor
  textStrong: ResourceColor
  sub: ResourceColor
  tertiary: ResourceColor
  fourth: ResourceColor
  accent: ResourceColor
  onAccent: ResourceColor
  icon: ResourceColor
  iconSecondary: ResourceColor
  iconTertiary: ResourceColor
  bg: ResourceColor
  bgStrong: ResourceColor
  rowBg: ResourceColor
  soft: ResourceColor
  softStrong: ResourceColor
  border: ResourceColor
  dividerSoft: ResourceColor
  input: ResourceColor
  chipActiveBg: ResourceColor
  chipInactiveBg: ResourceColor
  chipActiveBorder: ResourceColor
  chipInactiveBorder: ResourceColor
  chipInactiveText: ResourceColor
  hintPillBg: ResourceColor
  scrollbar: ResourceColor
  success: ResourceColor
  warning: ResourceColor
  error: ResourceColor
  overlayScrim: ResourceColor
  overlayPanel: ResourceColor
  overlayButton: ResourceColor
  panelGlass: ResourceColor
  panelGlassStrong: ResourceColor
  shadowSoft: ResourceColor
  errorText: ResourceColor
  errorBg: ResourceColor
  warningBg: ResourceColor
  dockActive: ResourceColor
  actionPositive: ResourceColor
  actionLoad: ResourceColor
  actionShare: ResourceColor
  disabled: ResourceColor
  idleIcon: ResourceColor
  isNight: boolean
  metricValue: ResourceColor
  actionConfirm: ResourceColor
  detailSub: ResourceColor
  spinner: ResourceColor
  thumbBg: ResourceColor
  accentSoft: ResourceColor
  nightMask: ResourceColor
  inputBorder: ResourceColor
  mediaCard: ResourceColor
  mediaOverlay: ResourceColor
  mediaLabelBar: ResourceColor
  mediaButton: ResourceColor
  dragHandle: ResourceColor
  ringStroke: ResourceColor
  badgePurple: ResourceColor
}

export const DEFAULT_SLOTS: ThemeSlots = {
  text: '#E5FFFFFF',
  textStrong: '#FFFFFFFF',
  sub: '#99FFFFFF',
  tertiary: '#8FBBD6',
  fourth: '#E7F7FF',
  accent: '#5B93BF',
  onAccent: '#E5FFFFFF',
  icon: '#E5FFFFFF',
  iconSecondary: '#B8E4FF',
  iconTertiary: '#7FB3DC',
  bg: 'rgba(255,255,255,0.04)',
  bgStrong: 'rgba(91,147,191,0.12)',
  rowBg: 'rgba(255,255,255,0.045)',
  soft: 'rgba(91,147,191,0.06)',
  softStrong: 'rgba(91,147,191,0.12)',
  border: 'rgba(147,215,255,0.10)',
  dividerSoft: 'rgba(255,255,255,0.05)',
  input: 'rgba(255,255,255,0.06)',
  chipActiveBg: 'rgba(79,148,211,0.55)',
  chipInactiveBg: 'rgba(107,163,214,0.15)',
  chipActiveBorder: 'rgba(127,179,220,0.7)',
  chipInactiveBorder: 'rgba(127,179,220,0.22)',
  chipInactiveText: '#B8D4EF',
  hintPillBg: 'rgba(91,147,191,0.92)',
  scrollbar: '#33FFFFFF',
  success: '#81C784',
  warning: '#FFD54F',
  error: '#C0392B',
  overlayScrim: 'rgba(2,6,12,0.99)',
  overlayPanel: 'rgba(15, 20, 30, 0.82)',
  overlayButton: 'rgba(255,255,255,0.12)',
  panelGlass: 'rgba(2,6,12,0.72)',
  panelGlassStrong: 'rgba(15, 20, 30, 0.82)',
  shadowSoft: 'rgba(0, 0, 0, 0.12)',
  errorText: '#F59B9B',
  errorBg: 'rgba(180,60,50,0.22)',
  warningBg: 'rgba(241,194,125,0.08)',
  dockActive: '#70C8FF',
  actionPositive: '#2E7D32',
  actionLoad: '#7D3C98',
  actionShare: 'rgba(68,136,178,0.72)',
  disabled: '#555555',
  idleIcon: DAY_IDLE_ICON,
  isNight: false,
  metricValue: DAY_METRIC_VALUE,
  actionConfirm: '#9B6E39',
  detailSub: '#9EC8DC',
  spinner: '#8EC9E9',
  thumbBg: 'rgba(0,0,0,0.22)',
  accentSoft: 'rgba(80,140,200,0.20)',
  nightMask: 'rgba(0,0,0,0)',
  inputBorder: 'rgba(214,238,255,0.14)',
  mediaCard: '#07101B',
  mediaOverlay: 'rgba(2,6,12,0.72)',
  mediaLabelBar: 'rgba(0,0,0,0.50)',
  mediaButton: 'rgba(35,74,98,0.58)',
  dragHandle: 'rgba(225,241,250,0.34)',
  ringStroke: 'rgba(143,187,214,0.88)',
  badgePurple: '#C9A6FF',
}

function slotsFromColors(colors: CustomColors, night: boolean): ThemeSlots {
  return {
    text: colors.fontPrimary ?? DEFAULT_SLOTS.text,
    textStrong: colors.fontEmphasize ?? DEFAULT_SLOTS.textStrong,
    sub: colors.fontSecondary ?? DEFAULT_SLOTS.sub,
    tertiary: colors.fontTertiary ?? DEFAULT_SLOTS.tertiary,
    fourth: colors.fontFourth ?? DEFAULT_SLOTS.fourth,
    accent: colors.backgroundEmphasize ?? DEFAULT_SLOTS.accent,
    onAccent: colors.fontOnPrimary ?? DEFAULT_SLOTS.onAccent,
    icon: colors.iconPrimary ?? DEFAULT_SLOTS.icon,
    iconSecondary: colors.iconSecondary ?? DEFAULT_SLOTS.iconSecondary,
    iconTertiary: colors.iconTertiary ?? DEFAULT_SLOTS.iconTertiary,
    bg: colors.compBackgroundTertiary ?? DEFAULT_SLOTS.bg,
    bgStrong: colors.compBackgroundSecondary ?? DEFAULT_SLOTS.bgStrong,
    rowBg: colors.backgroundFourth ?? DEFAULT_SLOTS.rowBg,
    soft: colors.backgroundSecondary ?? DEFAULT_SLOTS.soft,
    softStrong: colors.compBackgroundPrimaryTran ?? DEFAULT_SLOTS.softStrong,
    border: colors.compDivider ?? DEFAULT_SLOTS.border,
    dividerSoft: colors.interactivePressed ?? DEFAULT_SLOTS.dividerSoft,
    input: colors.compBackgroundPrimary ?? DEFAULT_SLOTS.input,
    chipActiveBg: colors.compBackgroundEmphasize ?? DEFAULT_SLOTS.chipActiveBg,
    chipInactiveBg: colors.interactiveHover ?? DEFAULT_SLOTS.chipInactiveBg,
    chipActiveBorder: colors.compFocusedPrimary ?? DEFAULT_SLOTS.chipActiveBorder,
    chipInactiveBorder: colors.compFocusedSecondary ?? DEFAULT_SLOTS.chipInactiveBorder,
    chipInactiveText: colors.compCommonContrary ?? DEFAULT_SLOTS.chipInactiveText,
    hintPillBg: colors.compEmphasizeSecondary ?? DEFAULT_SLOTS.hintPillBg,
    scrollbar: colors.compForegroundPrimary ?? DEFAULT_SLOTS.scrollbar,
    success: colors.confirm ?? DEFAULT_SLOTS.success,
    warning: colors.warning ?? DEFAULT_SLOTS.warning,
    error: colors.alert ?? DEFAULT_SLOTS.error,
    overlayScrim: colors.compBackgroundGray ?? DEFAULT_SLOTS.overlayScrim,
    overlayPanel: colors.compBackgroundGray ?? DEFAULT_SLOTS.overlayPanel,
    overlayButton: colors.interactiveActive ?? DEFAULT_SLOTS.overlayButton,
    panelGlass: colors.backgroundTertiary ?? DEFAULT_SLOTS.panelGlass,
    panelGlassStrong: colors.compBackgroundGray ?? DEFAULT_SLOTS.panelGlassStrong,
    shadowSoft: colors.interactiveClick ?? DEFAULT_SLOTS.shadowSoft,
    errorText: colors.fontOnSecondary ?? DEFAULT_SLOTS.errorText,
    errorBg: colors.interactiveSelect ?? DEFAULT_SLOTS.errorBg,
    warningBg: colors.iconEmphasize ?? DEFAULT_SLOTS.warningBg,
    dockActive: colors.iconSubEmphasize ?? DEFAULT_SLOTS.dockActive,
    actionPositive: colors.compBackgroundFocus ?? DEFAULT_SLOTS.actionPositive,
    actionLoad: colors.iconOnPrimary ?? DEFAULT_SLOTS.actionLoad,
    actionShare: colors.iconOnSecondary ?? DEFAULT_SLOTS.actionShare,
    disabled: colors.iconOnTertiary ?? DEFAULT_SLOTS.disabled,
    idleIcon: night ? NIGHT_IDLE_ICON : DAY_IDLE_ICON,
    isNight: night,
    metricValue: night ? NIGHT_METRIC_VALUE : (colors.fontFourth ?? DAY_METRIC_VALUE),
    actionConfirm: colors.fontOnTertiary ?? DEFAULT_SLOTS.actionConfirm,
    detailSub: colors.fontOnFourth ?? DEFAULT_SLOTS.detailSub,
    spinner: colors.iconFourth ?? DEFAULT_SLOTS.spinner,
    thumbBg: colors.iconOnFourth ?? DEFAULT_SLOTS.thumbBg,
    accentSoft: colors.compEmphasizeTertiary ?? DEFAULT_SLOTS.accentSoft,
    nightMask: night ? 'rgba(60,12,8,0.62)' : 'rgba(0,0,0,0)',
    inputBorder: colors.interactiveFocus ?? DEFAULT_SLOTS.inputBorder,
    mediaCard: colors.backgroundPrimary ?? DEFAULT_SLOTS.mediaCard,
    mediaOverlay: colors.backgroundTertiary ?? DEFAULT_SLOTS.mediaOverlay,
    mediaLabelBar: colors.primary ?? DEFAULT_SLOTS.mediaLabelBar,
    mediaButton: colors.onPrimary ?? DEFAULT_SLOTS.mediaButton,
    dragHandle: colors.compBackgroundNeutral ?? DEFAULT_SLOTS.dragHandle,
    ringStroke: colors.brand ?? DEFAULT_SLOTS.ringStroke,
    badgePurple: colors.container ?? DEFAULT_SLOTS.badgePurple,
  }
}

export function slotsFromTheme(theme: Theme): ThemeSlots {
  // Theme carries a copy of CustomColors, so object/class identity is not a
  // reliable night-mode signal. AppStorage is the app-wide night flag written
  // by NightModeStore before WithTheme re-renders.
  const night = AppStorage.get<boolean>('stellariumNightMode') === true
  return slotsFromColors(theme.colors, night)
}

export function slotsForNightMode(nightMode: boolean): ThemeSlots {
  return slotsFromColors(nightMode ? NIGHT_COLORS : DAY_COLORS, nightMode)
}

export class AstroColors {
  static readonly ringFill: string = 'rgba(65,130,170,0.10)'
  static readonly ringStroke: string = 'rgba(151,215,248,0.22)'
  static readonly cometTail: string = 'rgba(133,211,255,0.14)'
  static readonly cometCore: string = 'rgba(208,244,255,0.76)'
  static readonly cometIcon: string = '#B7E8FF'
  static readonly asteroidFill: string = 'rgba(159,178,191,0.26)'
  static readonly asteroidStroke: string = 'rgba(222,239,247,0.50)'
  static readonly asteroidIcon: string = '#D6E5EB'
  static readonly crater: string = 'rgba(7,16,25,0.36)'
  static readonly galaxyFill: string = 'rgba(158,181,255,0.12)'
  static readonly galaxyStroke: string = 'rgba(171,204,255,0.38)'
  static readonly galaxyCore: string = 'rgba(240,250,255,0.75)'
  static readonly galaxyIcon: string = '#C5DEFF'
  static readonly clusterFill: string = 'rgba(244,224,177,0.12)'
  static readonly clusterPoint: string = '#EAF7FF'
  static readonly clusterIcon: string = '#D8EEFF'
  static readonly nebulaFill: string = 'rgba(143,128,210,0.13)'
  static readonly nebulaIcon: string = '#D7E8FF'
  static readonly constellationIcon: string = '#C5E8FA'
  static readonly satelliteIcon: string = '#A9DAF3'
  static readonly moonIcon: string = '#D9EAF5'
  static readonly solar: string = '#F4C454'
  static readonly solarDim: string = '#9C6A24'
  static readonly solarText: string = '#30240D'

  // 星空文化领地地图（Canvas）固定数据色。
  static readonly cultureMapStroke: string = 'rgba(255, 219, 115, 0.96)'
  static readonly cultureMapFill: string = 'rgba(255, 194, 76, 0.18)'
  static readonly cultureLine: string = '#B9D8FF'
  static readonly cultureLabel: string = '#D9E9FF'
  static readonly cultureBoundary: string = '#DB8B8B'
  static readonly cultureHull: string = '#A66C6C'
  static readonly cultureZodiac: string = '#FFE36E'
  static readonly cultureLunar: string = '#7DE7B5'
  static readonly cultureAsterismLine: string = '#B1C7FF'
  static readonly cultureAsterismLabel: string = '#D5DEFF'
  static readonly cultureRayHelper: string = '#A9E2D2'

  // 高度曲线低于阈值的淡出占位色。
  static readonly altitudeFaded: string = '#33FFFFFF'

  // 陀螺仪快捷控件的固定状态色（待机/启用/未启用）。
  static readonly gyroPending: string = '#FFD36E'
  static readonly gyroEnabled: string = '#72E0A0'
  static readonly gyroIdle: string = 'rgba(255, 255, 255, 0.42)'

  // 起始星点遮罩与星点。
  static readonly starPoint: string = '#FFFFFF'
  static readonly windowBase: string = '#000000'

  // 天文卡片（form）固定插画色：按卡片类型区分主色与表面渐变。
  static readonly cardSatelliteAccent: string = '#8FE4D0'
  static readonly cardMeteorAccent: string = '#C9B8FF'
  static readonly cardMoonAccent: string = '#F3C78B'
  static readonly cardDefaultAccent: string = '#86CFF1'
  static readonly cardSatelliteSurface: string = '#123741'
  static readonly cardMeteorSurface: string = '#2B2349'
  static readonly cardMoonSurface: string = '#403145'
  static readonly cardDefaultSurface: string = '#193B58'
  static readonly cardVisualBg: string = 'rgba(5,16,29,0.72)'
  static readonly cardSatelliteOrbit: string = '#D5F5EF'
  static readonly cardSatelliteBody: string = '#507F8A'
  static readonly cardMeteorTrail: string = '#E7E0FF'
  static readonly cardMoonShadow: string = '#263C50'
  static readonly cardMoonLit: string = '#F5E9D4'
  static readonly cardMoonGlyph: string = '#C8DCE7'
  static readonly cardMoonBorder: string = 'rgba(245,229,202,0.40)'
  static readonly cardPlanetFill: string = '#3B6880'
  static readonly cardPlanetStroke: string = '#C5E5F2'
  static readonly cardGradientMid: string = '#0C1B2A'
  static readonly cardGradientEnd: string = '#08111D'
  static readonly cardSatelliteOrbitSoft: string = 'rgba(143,228,208,0.26)'
  static readonly cardSatelliteOrbitStrong: string = 'rgba(143,228,208,0.42)'
}
