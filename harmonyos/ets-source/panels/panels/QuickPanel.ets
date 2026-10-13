import { I18n } from '../../pages/I18n'
import {
  QUICK_ACTION_COLUMNS, QuickActionItem, QUICK_ACTION_EMPTY_ID,
  isValidQuickActionOrder, quickActionById, quickActionCandidatesFor,
  quickActionDefaultOrder, quickActionItemsFor, quickCandidateSlotsFor
} from '../../common/derive/quickActions'
import { UI_RADIUS_PILL } from '../../common/ui/UiTokens'
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
  hint: (text: string) => void
}

@Observed
export class QuickPanelStore {
  // 12 格顺序（条目 id 序列，长度恒 12）。
  order: string[] = quickActionDefaultOrder()
  editable: boolean = false
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

  // 候选带：池中「当前未列入」的项，已按 6 列补位（空位为占位项），上限两行。
  candidateSlots(): QuickActionItem[] {
    return quickCandidateSlotsFor(this.order)
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
    if (placed !== undefined && placed.labelKey.length > 0) this.hooks.hint(I18n.t(placed.labelKey))
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
  @Prop values: Record<string, boolean>
  onToggle: (id: string, value: boolean) => void = () => {}
  onHint: (text: string) => void = () => {}

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
        isOn: false,
        editable: true,
        candidate: true,
        onDragBegin: (id: string) => { this.store.beginDrag(id) }
      })
    }
  }

  build() {
    Column() {
      QuickActionGrid({
        items: this.store.items(),
        values: this.values,
        editable: this.store.editable,
        onToggle: (id: string, value: boolean) => { this.onToggle(id, value) },
        onHint: (text: string) => { this.onHint(text) },
        onDragBegin: (id: string) => { this.store.beginDrag(id) },
        onDropOnSlot: (slotId: string) => { this.store.dropOnSlot(slotId) }
      })
      if (this.store.editable) {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor('rgba(159, 232, 255, 0.22)')
          .margin({ top: 10 })
        Row({ space: 4 }) {
          ForEach(this.store.candidateSlots().slice(0, QUICK_ACTION_COLUMNS), (item: QuickActionItem) => {
            this.candidateSlot(item)
          }, (item: QuickActionItem, index: number) => 'candidate-' + index + '-' + item.id)
        }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: 12 })
        if (this.store.candidateSlots().length > QUICK_ACTION_COLUMNS) {
          Row({ space: 4 }) {
            ForEach(this.store.candidateSlots().slice(QUICK_ACTION_COLUMNS, QUICK_ACTION_COLUMNS * 2), (item: QuickActionItem) => {
              this.candidateSlot(item)
            }, (item: QuickActionItem, index: number) => 'candidate2-' + index + '-' + item.id)
          }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .margin({ top: 6 })
        }
        Row() {
          Text(I18n.t('quick_customize_hint'))
            .fontSize(10)
            .fontColor('#A8C2D8')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button(I18n.t('quick_customize_default'))
            .fontSize(11)
            .fontColor('#E5FFFFFF')
            .backgroundColor('rgba(255, 255, 255, 0.06)')
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
