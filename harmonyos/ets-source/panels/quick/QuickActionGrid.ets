import { QuickActionItem, QUICK_ACTION_COLUMNS } from '../../common/derive/quickActions'
import { QuickActionCell } from './QuickActionCell'

// 快捷操作面板的 2×6 图标网格（顺序由宿主给的 items 决定：前 6 第一行、后 6 第二行）。
//
// 布局用两行 Row + 每格 layoutWeight(1) + aspectRatio(1)：单元格宽度由行均分、高度自动成正方形，
// 比固定尺寸更能适配手机/半折/平板三种宽度。
// 开关值、编辑态与全部动作经 @Prop / 回调下发，本组件不读 store、不碰桥。
@Component
export struct QuickActionGrid {
  @Prop items: QuickActionItem[]
  @Prop values: Record<string, boolean>
  // 编辑态：格子显示可投放描边并接收拖放。
  @Prop editable: boolean
  onToggle: (id: string, value: boolean) => void = () => {}
  onHint: (text: string) => void = () => {}
  onDragBegin: (id: string) => void = () => {}
  onDropOnSlot: (slotId: string) => void = () => {}

  // 入口类（type === 'entry'）不入 values，恒为 false —— 格子永不显示「永久点亮」的假开关。
  private isOn(id: string): boolean {
    return this.values[id] === true
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 4 }) {
        ForEach(this.items.slice(0, QUICK_ACTION_COLUMNS), (item: QuickActionItem) => {
          QuickActionCell({
            item: item,
            isOn: this.isOn(item.id),
            editable: this.editable,
            candidate: false,
            onToggle: (id: string, value: boolean) => { this.onToggle(id, value) },
            onHint: (text: string) => { this.onHint(text) },
            onDragBegin: (id: string) => { this.onDragBegin(id) },
            onDropOnSlot: (slotId: string) => { this.onDropOnSlot(slotId) }
          })
        }, (item: QuickActionItem) => item.id)
      }
        .width('100%')
        .alignItems(VerticalAlign.Top)
      Row({ space: 4 }) {
        ForEach(this.items.slice(QUICK_ACTION_COLUMNS, QUICK_ACTION_COLUMNS * 2), (item: QuickActionItem) => {
          QuickActionCell({
            item: item,
            isOn: this.isOn(item.id),
            editable: this.editable,
            candidate: false,
            onToggle: (id: string, value: boolean) => { this.onToggle(id, value) },
            onHint: (text: string) => { this.onHint(text) },
            onDragBegin: (id: string) => { this.onDragBegin(id) },
            onDropOnSlot: (slotId: string) => { this.onDropOnSlot(slotId) }
          })
        }, (item: QuickActionItem) => item.id)
      }
        .width('100%')
        .alignItems(VerticalAlign.Top)
    }
      .width('100%')
  }
}
