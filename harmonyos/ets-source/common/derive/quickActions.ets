// 「快捷操作面板」（Dock 中间入口，activePanel === 'quick'）的候选池、默认 12 项与顺序校验。
//
// 只描述"是什么"：稳定 id、类型（开关 / 入口）、提示文案键、图标键与着色路径、图层类动作的 actionShow_*
// 标识、入口类要跳的面板 id。开关值一律来自既有 store（layer / satellite / gyro / nightMode / telescope /
// polarScope / overlay），故本模块零 store、零桥、零 IO。
// 动作分发在宿主：QuickPanel.onToggle → 宿主 quickToggle(id, value)。
//
// 文案一律复用既有键（与图层面板同词）；二期新增项的键见
// docs/harmonyos/research/QUICK-ACTIONS-PANEL-PLAN.md §13.9。
// 详情卡固定观测模式后，原「观测模式」格子由卫星提示默认替代（见
// docs/harmonyos/specs/OBJECT-DETAIL-OBSERVE-MODE.md §13）。

export interface QuickActionItem {
  id: string
  labelKey: string
  icon: string
  kind: string
  // 'raster'（官方 PNG，走 colorFilter）| 'vector'（自研 SVG，走 fillColor）
  type: string
  // 'toggle'（开关，有 ON 态）| 'entry'（入口，点按跳面板，恒无 ON 态）
  actionId: string
  // type === 'toggle' 且属图层类时使用；其余为 ''
  openPanel: string
  // type === 'entry' 时的目标面板 id；其余为 ''
}

// 网格列数与格子数。二期自定义只做「替换」，格子数恒为 12（用户确认）。
export const QUICK_ACTION_COLUMNS: number = 6
export const QUICK_ACTION_SLOTS: number = QUICK_ACTION_COLUMNS * 2
// 展开态有限位可视行数：面板拉长到该行数后封顶，剩余候选行在区域内顺滑滚动。
export const QUICK_EXPANDED_VISIBLE_ROWS: number = 3

// 全量候选池（39 项 = 默认 12 项 + 27 项扩展候选）。顺序即默认网格顺序：**前 12 项即默认网格**。
//
// 详情卡固定观测模式后，快捷面板不再提供「观测模式」开关；原第 10 格的
// 「卫星提示」回到默认网格，保持一期 12 项的语义。
export function quickActionPool(): QuickActionItem[] {
  return [
    // —— 一期 12 项（默认网格）——
    { id: 'constellation_lines', labelKey: 's0522', icon: 'bt_constellation_lines', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Lines', openPanel: '' },
    { id: 'constellation_labels', labelKey: 's0523', icon: 'bt_constellation_labels', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Labels', openPanel: '' },
    { id: 'constellation_art', labelKey: 's0525', icon: 'bt_constellation_art', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Art', openPanel: '' },
    { id: 'equatorial_grid', labelKey: 's0323', icon: 'bt_equatorial_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Equatorial_Grid', openPanel: '' },
    { id: 'azimuthal_grid', labelKey: 's0324', icon: 'bt_azimuthal_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Azimuthal_Grid', openPanel: '' },
    { id: 'ground', labelKey: 's0306', icon: 'bt_ground', kind: 'raster', type: 'toggle', actionId: 'actionShow_Ground', openPanel: '' },
    { id: 'atmosphere', labelKey: 's0305', icon: 'bt_atmosphere', kind: 'raster', type: 'toggle', actionId: 'actionShow_Atmosphere', openPanel: '' },
    { id: 'cardinal_points', labelKey: 's0533', icon: 'bt_cardinal_points', kind: 'raster', type: 'toggle', actionId: 'actionShow_Cardinal_Points', openPanel: '' },
    { id: 'nebulae', labelKey: 's0320', icon: 'bt_nebula', kind: 'raster', type: 'toggle', actionId: 'actionShow_Nebulas', openPanel: '' },
    { id: 'satellites', labelKey: 'plugin_satellites', icon: 'satellite', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'gyroscope', labelKey: 'i0060', icon: 'gyro', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'night_mode', labelKey: 's0300', icon: 'bt_night_view', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    // —— 二期候选 6 项 ——
    { id: 'equatorial_mount', labelKey: 'quick_mount_mode', icon: 'bt_equatorial_mount', kind: 'raster', type: 'toggle', actionId: 'actionSwitch_Equatorial_Mount', openPanel: '' },
    { id: 'flip_horizontal', labelKey: 'quick_flip_horizontal', icon: 'bt_flip_horizontal', kind: 'raster', type: 'toggle', actionId: 'actionHorizontal_Flip', openPanel: '' },
    { id: 'observing_list', labelKey: 'more_observe_list', icon: 'bt_obs_list', kind: 'raster', type: 'entry', actionId: '', openPanel: 'observing' },
    { id: 'oculars', labelKey: 'panel_oculars', icon: 'oculars', kind: 'vector', type: 'entry', actionId: '', openPanel: 'oculars' },
    { id: 'red_light', labelKey: 'quick_red_light', icon: 'red_light', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'spectral_lens', labelKey: 'quick_spectral_lens', icon: 'spectral_lens', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' },
    // —— 第一梯队（高频观星与天文摄影，6 项）——
    { id: 'constellation_boundaries', labelKey: 's0524', icon: 'bt_constellation_boundaries', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Boundaries', openPanel: '' },
    { id: 'meteor_showers', labelKey: 'plugin_meteor_showers', icon: 'bt_meteor_showers', kind: 'raster', type: 'toggle', actionId: 'actionShow_MeteorShowers', openPanel: '' },
    { id: 'angle_measure', labelKey: 'panel_angle_measure', icon: 'bt_angle_measure', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'asterism_lines', labelKey: 's0528', icon: 'bt_asterism_lines', kind: 'raster', type: 'toggle', actionId: 'actionShow_Asterism_Lines', openPanel: '' },
    { id: 'hips_surveys', labelKey: 's0600', icon: 'bt_hips', kind: 'raster', type: 'toggle', actionId: 'actionShow_Hips_Surveys', openPanel: '' },
    { id: 'flip_vertical', labelKey: 's0310', icon: 'bt_flip_vertical', kind: 'raster', type: 'toggle', actionId: 'actionVertical_Flip', openPanel: '' },
    // —— 第二梯队（进阶望远镜、构图、坐标与专业天体，15 项）——
    { id: 'ccd_sensor', labelKey: 'c_ccd_frame', icon: 'bt_sensor', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'telrad', labelKey: 'quick_telrad', icon: 'bt_telrad', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'mosaic_camera', labelKey: 'Mosaic Camera', icon: 'bt_mosaic_camera', kind: 'raster', type: 'entry', actionId: '', openPanel: 'mosaicCamera' },
    { id: 'compass_marks', labelKey: 'quick_compass_marks', icon: 'bt_compass_marks', kind: 'raster', type: 'toggle', actionId: 'actionShow_Compass_Marks', openPanel: '' },
    { id: 'ecliptic_grid', labelKey: 's0505', icon: 'bt_ecliptic_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Ecliptic_Grid', openPanel: '' },
    { id: 'galactic_grid', labelKey: 'quick_galactic_grid', icon: 'bt_galactic_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Galactic_Grid', openPanel: '' },
    { id: 'planets', labelKey: 's0311', icon: 'bt_planets', kind: 'raster', type: 'toggle', actionId: 'actionShow_Planets', openPanel: '' },
    { id: 'archaeo_lines', labelKey: 'quick_archaeo_lines', icon: 'bt_archaeo_lines', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'telescope', labelKey: 'panel_telescope_control', icon: 'bt_telescope', kind: 'raster', type: 'entry', actionId: '', openPanel: 'telescope' },
    { id: 'nav_stars', labelKey: 'panel_nav_stars', icon: 'bt_nav_stars', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'calendars', labelKey: 'plugin_calendars', icon: 'bt_calendars', kind: 'raster', type: 'entry', actionId: '', openPanel: 'calendars' },
    { id: 'exoplanets', labelKey: 'plugin_exoplanets', icon: 'bt_exoplanets', kind: 'raster', type: 'toggle', actionId: 'actionShow_Exoplanets', openPanel: '' },
    { id: 'pulsars', labelKey: 'plugin_pulsars', icon: 'bt_pulsars', kind: 'raster', type: 'toggle', actionId: 'actionShow_Pulsars', openPanel: '' },
    { id: 'quasars', labelKey: 'plugin_quasars', icon: 'bt_quasars', kind: 'raster', type: 'toggle', actionId: 'actionShow_Quasars', openPanel: '' },
    { id: 'fullscreen', labelKey: 'quick_fullscreen', icon: 'bt_fullscreen', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' }
  ]
}

export function quickActionById(id: string): QuickActionItem | undefined {
  const pool = quickActionPool()
  for (const item of pool) {
    if (item.id === id) return item
  }
  return undefined
}

// 默认网格 = 池中前 12 项（= 一期现状）。
export function quickActionDefaultOrder(): string[] {
  const pool = quickActionPool()
  const order: string[] = []
  for (let i = 0; i < QUICK_ACTION_SLOTS && i < pool.length; i++) {
    order.push(pool[i].id)
  }
  return order
}

// 按持久化的 id 序列取出条目；未知 id 静默跳过（写入前须先过 isValidQuickActionOrder）。
export function quickActionItemsFor(order: string[]): QuickActionItem[] {
  const items: QuickActionItem[] = []
  for (const id of order) {
    const item = quickActionById(id)
    if (item !== undefined) items.push(item)
  }
  return items
}

// 默认 12 项（= 一期行为），供未接入自定义顺序的调用点使用。
export function quickActionItems(): QuickActionItem[] {
  return quickActionItemsFor(quickActionDefaultOrder())
}

// 池中「当前未列入」的候选 —— 二期编辑态候选带的来源。
export function quickActionCandidatesFor(order: string[]): QuickActionItem[] {
  const candidates: QuickActionItem[] = []
  for (const item of quickActionPool()) {
    if (order.indexOf(item.id) < 0) candidates.push(item)
  }
  return candidates
}

// 候选带空位的占位 id（只用于补齐整列，不会出现在网格里）。
export const QUICK_ACTION_EMPTY_ID: string = '__quick_empty__'

export function quickActionEmptyItem(): QuickActionItem {
  return { id: QUICK_ACTION_EMPTY_ID, labelKey: '', icon: '', kind: 'vector', type: 'entry', actionId: '', openPanel: '' }
}

// 候选带布局：把「当前未列入」的全部项按 6 列补位，不再截断；
// 展开时菜单框只拉长到 QUICK_EXPANDED_VISIBLE_ROWS 行（有限位），其余行在候选带内顺滑滚动。
export function quickCandidateSlotsFor(order: string[]): QuickActionItem[] {
  const candidates = quickActionCandidatesFor(order)
  const rows = Math.max(1, Math.ceil(candidates.length / QUICK_ACTION_COLUMNS))
  const capacity = rows * QUICK_ACTION_COLUMNS
  const slots: QuickActionItem[] = []
  for (let i = 0; i < capacity; i++) {
    slots.push(i < candidates.length ? candidates[i] : quickActionEmptyItem())
  }
  return slots
}

// 候选带总行数（全部候选行，用于逐行渲染）。
export function quickCandidateRowsFor(order: string[]): number {
  const candidates = quickActionCandidatesFor(order)
  return Math.max(1, Math.ceil(candidates.length / QUICK_ACTION_COLUMNS))
}

// 候选带有限位可视行数（宿主面板高度公式与 QuickPanel 滚动视口共用）。
export function quickCandidateVisibleRowsFor(order: string[]): number {
  return Math.min(QUICK_EXPANDED_VISIBLE_ROWS, quickCandidateRowsFor(order))
}

// 持久化序列校验：长度必须等于格子数、元素必须都在池内、且不得重复。
// 任一不满足由调用方整串回落默认（不做逐项修补，避免半新半旧的网格）。
export function isValidQuickActionOrder(order: string[]): boolean {
  if (order.length !== QUICK_ACTION_SLOTS) return false
  const seen = new Set<string>()
  for (const id of order) {
    if (quickActionById(id) === undefined || seen.has(id)) return false
    seen.add(id)
  }
  return true
}
