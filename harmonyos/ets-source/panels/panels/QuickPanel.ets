import { Theme, curves } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import {
  QUICK_ACTION_COLUMNS, QuickActionItem, QUICK_ACTION_EMPTY_ID,
  isValidQuickActionOrder, quickActionById, quickActionCandidatesFor,
  quickActionDefaultOrder, quickActionItemsFor, quickCandidateRowsFor,
  quickCandidateSlotsFor, quickCandidateVisibleRowsFor
} from '../../common/derive/quickActions'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
import { NightModeStore } from '../../state/NightModeStore'
import { BridgeClient } from '../../bridge/BridgeClient'
import { QuickActionCell } from '../quick/QuickActionCell'
import { QuickActionGrid } from '../quick/QuickActionGrid'

// 「快捷操作」面板（`activePanel === 'quick'`，Dock 中间入口）的**编辑态状态与全部顺序编辑逻辑**。
//
// 放在本文件（面板自己的文件）而非宿主：宿主只负责「持有实例 + 注入落盘/提示 hooks + 传值」，
// 顺序的进入/提交/丢弃/恢复默认/拖动-替换全在这里，宿主不再散落十几处 quickXxx 私有方法。
// 落盘与提示经 hooks 注入（宿主用 @ohos.data.preferences / flashHint 实现）—— 本文件不 import NAPI，
// 与 `state/*Store.ets` 同一规矩。
//
// 语义（见 QUICK-ACTIONS-PANEL-PLAN §13.5）：编辑态只在内存里改，「完成」才提交并落盘；
// 返回 / 点面板外 = 丢弃复原。格子恒 12 个、位置固定，只做**替换**。
export interface QuickPanelHostHooks {
  saveOrder: (json: string) => void
  saveExpanded?: (expanded: boolean) => void
  hint: (text: string) => void
}

@Observed
export class QuickPanelStore {
  // 12 格顺序（条目 id 序列，长度恒 12）。
  order: string[] = quickActionDefaultOrder()
  editable: boolean = false
  // 正常态的“更多操作”区是否展开（持久化保留：关闭面板再打开仍维持上次长/短限位）。
  expanded: boolean = false
  // 进入编辑态时的顺序快照，供「丢弃」复原。
  orderSnapshot: string[] = []
  // 被拖起的候选 id（应用内拖放的负载经组件回调传到这里）。
  dragSourceId: string = ''

  private hooks: QuickPanelHostHooks = {
    saveOrder: (json: string) => {},
    hint: (text: string) => {}
  }

  configure(hooks: QuickPanelHostHooks): void {
    this.hooks = hooks
  }

  // —— 只读派生（避免各部分各自拼装）——
  items(): QuickActionItem[] {
    return quickActionItemsFor(this.order)
  }

  // 候选带：池中「当前未列入」的全部项，按 6 列补位（空位为占位项）。
  candidateSlots(): QuickActionItem[] {
    return quickCandidateSlotsFor(this.order)
  }

  // —— 正常态“更多操作”区（带状态记忆）——
  setExpanded(value: boolean, persist: boolean = true): void {
    const changed = this.expanded !== value
    this.expanded = value
    if (changed && persist && this.hooks.saveExpanded !== undefined) {
      this.hooks.saveExpanded(value)
    }
  }

  // 候选带总行数（全部可滚动行）。
  moreRows(): number {
    return quickCandidateRowsFor(this.order)
  }

  // 候选带有限位可视行数（与宿主面板高度公式同源）。
  visibleMoreRows(): number {
    return quickCandidateVisibleRowsFor(this.order)
  }

  candidateRowIndices(): number[] {
    const rows = this.moreRows()
    const indices: number[] = []
    for (let i = 0; i < rows; i++) indices.push(i)
    return indices
  }

  // —— 编辑态 ——
  toggleEdit(): void {
    if (!this.editable) {
      this.orderSnapshot = this.order.slice()
      this.editable = true
      return
    }
    this.commitEdit()
  }

  // 提交：非法顺序（长度 / 未知 id / 重复）整串回落默认，再落盘一次。
  commitEdit(): void {
    this.editable = false
    this.dragSourceId = ''
    if (!isValidQuickActionOrder(this.order)) this.order = quickActionDefaultOrder()
    this.hooks.saveOrder(JSON.stringify(this.order))
  }

  // 丢弃：复原进入编辑态前的顺序（关面板 / 返回时调用）。
  discardEdit(): void {
    if (!this.editable) return
    this.order = this.orderSnapshot.slice()
    this.editable = false
    this.dragSourceId = ''
  }

  // —— 拖动-替换 ——
  beginDrag(id: string): void {
    this.dragSourceId = id
  }

  // 候选被拖到某格上松手：两者互换（槽位原项回到候选带，语义即「未列入的替换已列入的」）。
  dropOnSlot(slotId: string): void {
    const dragged = this.dragSourceId
    this.dragSourceId = ''
    if (!this.editable || dragged.length === 0 || dragged === slotId) return
    const slotIndex = this.order.indexOf(slotId)
    // 拖的必须是「当前未列入」的候选，且槽位必须存在（防跨代的陈旧投放）。
    if (slotIndex < 0 || this.order.indexOf(dragged) >= 0) return
    const next = this.order.slice()
    next[slotIndex] = dragged
    this.order = next
    const placed = quickActionById(dragged)
    if (placed !== undefined && placed.labelKey.length > 0) {
      this.hooks.hint(placed.id === 'spectral_lens' ? '多光谱透视镜' : I18n.t(placed.labelKey))
    }
  }

  // 恢复默认：只改内存（仍需「完成」提交）—— 否则「丢弃」会半途生效，语义自相矛盾。
  resetDefaults(): void {
    this.order = quickActionDefaultOrder()
    this.hooks.hint(I18n.t('quick_customize_default'))
  }

  // 从持久化恢复（宿主读 preferences 后调用）；非法或缺失一律整串回落默认，不做逐项修补。
  restoreOrder(order: string[]): void {
    this.order = isValidQuickActionOrder(order) ? order : quickActionDefaultOrder()
  }
}

// 「快捷操作」面板视图：正常态 = 2×6 = 12 个开关/入口图标；标题栏显示当前位置且本身是按钮（跳「位置」面板）。
// 编辑态 = 上面 12 格原地不动，下方多出候选带 + 一行操作条（提示 + 恢复默认）。
// 各项当前值与动作分发由宿主下发（要碰桥与各域 controller），顺序与编辑态则来自 store。
@Component
export struct QuickPanel {
  @ObjectLink store: QuickPanelStore
  @ObjectLink nightModeStore: NightModeStore
  @Prop values: Record<string, boolean>
  @Prop gyroActive: boolean = false
  @Prop arCameraActive: boolean = false
  @Prop arCameraStarting: boolean = false
  @Prop cellSize: number = 52
  @Prop dampProgress: number = 0
  @StorageLink('stellariumSpectralLensActive') spectralLensActive: boolean = false
  @State private c: ThemeSlots = DEFAULT_SLOTS
  candidateScroller: Scroller = new Scroller()
  onToggle: (id: string, value: boolean) => void = () => {}
  onToggleArCamera: () => void = () => {}
  onToggleExpand: () => void = () => {}
  onHint: (text: string) => void = () => {}

  onWillApplyTheme(theme: Theme): void { this.c = slotsFromTheme(theme) }

  private handleQuickToggle(id: string, value: boolean): void {
    if (id === 'spectral_lens') {
      const next = !this.spectralLensActive
      AppStorage.setOrCreate('stellariumSpectralLensActive', next)
      if (!next) {
        BridgeClient.send('setSpectralLens', '0')
        this.onHint('多光谱透视镜已关闭')
      } else {
        this.onHint('多光谱透视镜已开启 · 拖动圆镜，转动转柄切换 9 波段')
        AppStorage.setOrCreate('stellariumRequestBack', Date.now())
      }
      return
    }
    this.onToggle(id, value)
  }

  @Builder
  candidateSlot(item: QuickActionItem) {
    if (item.id === QUICK_ACTION_EMPTY_ID) {
      // 占位：与候选格等宽，保证候选格宽度与网格格完全一致。
      Row()
        .layoutWeight(1)
        .aspectRatio(1)
    } else {
      QuickActionCell({
        item: item,
        // 正常态直接反映开关值（候选也是可用按钮）；编辑态候选恒不点亮。
        isOn: this.store.editable ? false : (item.id === 'spectral_lens' ? this.spectralLensActive : this.values[item.id] === true),
        editable: this.store.editable,
        candidate: true,
        onToggle: (id: string, value: boolean) => { this.handleQuickToggle(id, value) },
        onHint: (text: string) => { this.onHint(text) },
        onDragBegin: (id: string) => { this.store.beginDrag(id) }
      })
    }
  }

  // 候选带第 rowIndex 行（6 列）。行距与宿主高度公式一致：首行 12，后续 6。
  @Builder
  candidateRow(rowIndex: number) {
    Row({ space: 4 }) {
      ForEach(this.store.candidateSlots().slice(rowIndex * QUICK_ACTION_COLUMNS, (rowIndex + 1) * QUICK_ACTION_COLUMNS),
        (item: QuickActionItem) => { this.candidateSlot(item) },
        (item: QuickActionItem, index: number) => 'candidate-' + rowIndex + '-' + index + '-' + item.id)
    }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: rowIndex === 0 ? 12 : 6 })
  }

  build() {
    Column() {
      QuickActionGrid({
        items: this.store.items(),
        values: this.values,
        nightModeStore: this.nightModeStore,
        editable: this.store.editable,
        onToggle: (id: string, value: boolean) => { this.handleQuickToggle(id, value) },
        onHint: (text: string) => { this.onHint(text) },
        onDragBegin: (id: string) => { this.store.beginDrag(id) },
        onDropOnSlot: (slotId: string) => { this.store.dropOnSlot(slotId) }
      })
      // 开启「转动手机（陀螺仪）」后，从快捷网格下方顺滑伸出一个极简「AR 实景相机」标签，无需专门大面板。
      if (this.gyroActive && !this.store.editable) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.camera'))
            .fontSize(17)
            .fontColor([this.arCameraActive ? this.c.onAccent : this.c.accent])
          Text(this.arCameraStarting
            ? '正在开启 AR 实景…'
            : (this.arCameraActive ? 'AR 实景已开启' : 'AR 实景相机'))
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.arCameraActive ? this.c.onAccent : this.c.text)
          Text(this.arCameraActive ? '双指上下滑调抠像' : '自动抠出树叶与建筑')
            .fontSize(10.5)
            .fontColor(this.arCameraActive ? this.c.onAccent : this.c.tertiary)
            .opacity(this.arCameraActive ? 0.85 : 1)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.arCameraActive ? '关闭' : '开启')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.arCameraActive ? this.c.onAccent : this.c.accent)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(UI_RADIUS_PILL)
            .backgroundColor(this.arCameraActive ? 'rgba(255,255,255,0.20)' : this.c.accentSoft)
        }
          .width('100%')
          .height(38)
          .padding({ left: 12, right: 8 })
          .margin({ top: 10 })
          .borderRadius(UI_RADIUS_PILL)
          .backgroundColor(this.arCameraActive ? this.c.accent : this.c.input)
          .border({ width: 0.5, color: this.arCameraActive ? this.c.accent : this.c.border })
          .alignItems(VerticalAlign.Center)
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .enabled(!this.arCameraStarting)
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: -12 }).animation({ duration: 260, curve: curves.springMotion(0.45, 0.88) })),
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 0, y: -8 }).animation({ duration: 150, curve: Curve.EaseIn }))
          ))
          .onClick(() => { this.onToggleArCamera() })
      }
      // 默认只有 6×2 短限位；上滚越过阻尼（或拖动顶部抓手 / 进入编辑态）后菜单框变长至有限位高度，
      // 剩余第一/二梯队扩展开关在独立 Scroll 内顺滑滚动，同时顶部 12 格保持锚定（便于编辑态拖放替换）。
      if (this.store.expanded || this.store.editable) {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor(this.c.border)
          .margin({ top: 10 })
        Scroll(this.candidateScroller) {
          Column() {
            ForEach(this.store.candidateRowIndices(), (rowIndex: number) => {
              this.candidateRow(rowIndex)
            }, (rowIndex: number) => 'candidate-row-' + rowIndex)
          }
            .width('100%')
            .padding({ bottom: 4 })
        }
          .width('100%')
          .height(Math.max(this.cellSize + 12,
            12 + this.store.visibleMoreRows() * this.cellSize + Math.max(0, this.store.visibleMoreRows() - 1) * 6 + 4))
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .nestedScroll({
            scrollForward: NestedScrollMode.SELF_ONLY,
            scrollBackward: NestedScrollMode.SELF_ONLY
          })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: 8 }).animation({ duration: 260, curve: curves.springMotion(0.46, 0.86) })),
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
          ))
      } else {
        // 短限位底部阻尼微指示条：上滚蓄力时随 dampProgress 柔和加宽亮起，亦可轻点展开。
        Row() {
          Row()
            .width(28 + Math.round(Math.max(0, this.dampProgress) * 24))
            .height(3.5)
            .borderRadius(2)
            .backgroundColor(this.dampProgress > 0.15 ? this.c.accent : this.c.dragHandle)
            .opacity(0.45 + Math.min(0.55, Math.max(0, this.dampProgress) * 0.55))
            .animation({ duration: 140, curve: Curve.EaseOut })
        }
          .width('100%')
          .height(14)
          .margin({ top: 4 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => { this.onToggleExpand() })
      }
      if (this.store.editable) {
        Row() {
          Text(I18n.t('quick_customize_hint'))
            .fontSize(10)
            .fontColor(this.c.tertiary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button(I18n.t('quick_customize_default'))
            .fontSize(11)
            .fontColor(this.c.text)
            .backgroundColor(this.c.input)
            .borderRadius(UI_RADIUS_PILL)
            .height(28)
            .padding({ left: 10, right: 10 })
            .clickEffect({ level: ClickEffectLevel.LIGHT })
            .onClick(() => { this.store.resetDefaults() })
        }
          .width('100%')
          .height(28)
          .alignItems(VerticalAlign.Center)
          .margin({ top: 8 })
      }
    }
      .width('100%')
  }
}
