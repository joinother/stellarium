// 「快捷操作面板」（Dock 中间入口，activePanel === 'quick'）的候选池、默认 12 项与顺序校验。
//
// 只描述"是什么"：稳定 id、类型（开关 / 入口）、提示文案键、图标键与着色路径、图层类动作的 actionShow_*
// 标识、入口类要跳的面板 id。开关值一律来自既有 store（layer / satellite / gyro / nightMode / telescope /
// polarScope / overlay），故本模块零 store、零桥、零 IO。
// 动作分发在宿主：QuickPanel.onToggle → 宿主 quickToggle(id, value)。
//
// 文案一律复用既有键（与图层面板同词）；二期新增项的键见
// docs/harmonyos/research/QUICK-ACTIONS-PANEL-PLAN.md §13.9，三期观测模式的键见
// docs/harmonyos/specs/OBJECT-DETAIL-OBSERVE-MODE.md §8.2。

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

// 全量候选池（17 项）。顺序即默认网格顺序：**前 12 项即默认网格**。
//
// 三期变更：默认网格第 10 格由「卫星提示」换成「观测模式」开关
// （specs/OBJECT-DETAIL-OBSERVE-MODE.md §5：模式切换要在快捷面板有一格）。
// 卫星项**未从代码删除**，只是移出默认 12 项、留在池尾：它仍是图层开关
// （也可在图层面板操作），且三期已有自定义面板，用户可自行把它拖回网格。
// 其余 11 项与一期逐项、逐序一致。
export function quickActionPool(): QuickActionItem[] {
  return [
    // —— 一期 12 项（第 10 格已按三期替换为观测模式）——
    { id: 'constellation_lines', labelKey: 's0522', icon: 'bt_constellation_lines', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Lines', openPanel: '' },
    { id: 'constellation_labels', labelKey: 's0523', icon: 'bt_constellation_labels', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Labels', openPanel: '' },
    { id: 'constellation_art', labelKey: 's0525', icon: 'bt_constellation_art', kind: 'raster', type: 'toggle', actionId: 'actionShow_Constellation_Art', openPanel: '' },
    { id: 'equatorial_grid', labelKey: 's0323', icon: 'bt_equatorial_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Equatorial_Grid', openPanel: '' },
    { id: 'azimuthal_grid', labelKey: 's0324', icon: 'bt_azimuthal_grid', kind: 'raster', type: 'toggle', actionId: 'actionShow_Azimuthal_Grid', openPanel: '' },
    { id: 'ground', labelKey: 's0306', icon: 'bt_ground', kind: 'raster', type: 'toggle', actionId: 'actionShow_Ground', openPanel: '' },
    { id: 'atmosphere', labelKey: 's0305', icon: 'bt_atmosphere', kind: 'raster', type: 'toggle', actionId: 'actionShow_Atmosphere', openPanel: '' },
    { id: 'cardinal_points', labelKey: 's0533', icon: 'bt_cardinal_points', kind: 'raster', type: 'toggle', actionId: 'actionShow_Cardinal_Points', openPanel: '' },
    { id: 'nebulae', labelKey: 's0320', icon: 'bt_nebula', kind: 'raster', type: 'toggle', actionId: 'actionShow_Nebulas', openPanel: '' },
    { id: 'observe_mode', labelKey: 'detail_mode_observe', icon: 'observe_mode', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'gyroscope', labelKey: 'i0060', icon: 'gyro', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' },
    { id: 'night_mode', labelKey: 's0300', icon: 'bt_night_view', kind: 'raster', type: 'toggle', actionId: '', openPanel: '' },
    // —— 二期新增 4 项（默认网格外的候选）——
    { id: 'equatorial_mount', labelKey: 'quick_mount_mode', icon: 'bt_equatorial_mount', kind: 'raster', type: 'toggle', actionId: 'actionSwitch_Equatorial_Mount', openPanel: '' },
    { id: 'flip_horizontal', labelKey: 'quick_flip_horizontal', icon: 'bt_flip_horizontal', kind: 'raster', type: 'toggle', actionId: 'actionHorizontal_Flip', openPanel: '' },
    { id: 'observing_list', labelKey: 'more_observe_list', icon: 'bt_obs_list', kind: 'raster', type: 'entry', actionId: '', openPanel: 'observing' },
    { id: 'oculars', labelKey: 'panel_oculars', icon: 'oculars', kind: 'vector', type: 'entry', actionId: '', openPanel: 'oculars' },
    // —— 三期：卫星提示移出默认网格（保留在池中，用户可在自定义面板里拖回）——
    { id: 'satellites', labelKey: 'plugin_satellites', icon: 'satellite', kind: 'vector', type: 'toggle', actionId: '', openPanel: '' }
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

// 候选带布局：把「当前未列入」的项按 6 列补位，**上限两行**（12 格）。
// 池 17 项 → 未列入 5 项 → 1 行。若日后把池扩到 18 项以上，这里会截断，
// 届时须同步扩展 QuickPanel 的行渲染与宿主高度公式（见计划 §13.12 风险）。
export function quickCandidateSlotsFor(order: string[]): QuickActionItem[] {
  const candidates = quickActionCandidatesFor(order)
  const rows = Math.max(1, Math.min(2, Math.ceil(candidates.length / QUICK_ACTION_COLUMNS)))
  const capacity = rows * QUICK_ACTION_COLUMNS
  const slots: QuickActionItem[] = []
  for (let i = 0; i < capacity; i++) {
    slots.push(i < candidates.length ? candidates[i] : quickActionEmptyItem())
  }
  return slots
}

// 候选带占用的行数（宿主高度公式与 QuickPanel 的行渲染必须一致，故共用此函数）。
export function quickCandidateRowsFor(order: string[]): number {
  const candidates = quickActionCandidatesFor(order)
  return Math.max(1, Math.min(2, Math.ceil(candidates.length / QUICK_ACTION_COLUMNS)))
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
