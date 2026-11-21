import { Theme } from '@kit.ArkUI'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { LayerPresetDefinition } from '../../common/types/MainWindowModels'
import { LayerPresetStore } from '../../state/LayerPresetStore'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 本组件职责：「图层」面板顶部的图层预设条。
//
// 5 个内置预设 + 最多 3 个自定义预设；选中的预设高亮，已修改/已偏离的预设以 * 标记。
// 手动修改后预设保持选中并标记为已修改——这是固定语义，不再提供“保持”开关；
// 预设管理（保存/改名/排序/启停/详情/还原）在「图层预设」页签中完成。
//
// 选中项可能在横向可视区外（尤其是自定义预设位于末尾时）。只在组件首次挂载
// （打开图层面板）时滚动一次，把选中 chip 滚入视野；此后用户手动滚动由用户控制，
// 选中项变化也不再自动滚动，避免滚动松手后被弹回选中项。
@Component
export struct LayerPresetBar {
  @ObjectLink presetStore: LayerPresetStore
  @State private c: ThemeSlots = DEFAULT_SLOTS
  private presetScroller: Scroller = new Scroller()
  // 只记录宽度；x 偏移由「左侧 chip 宽度 + Row 间距」累加得出，
  // 不受滚动位置影响（Area.position 在部分版本会随滚动变化，不能作为内容偏移）。
  private chipWidths: Map<string, number> = new Map<string, number>()
  private barWidth: number = 0
  private initialRevealPending: boolean = true

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  private chipOffset(id: string): number {
    let offset = 2
    const presets = this.presetStore.enabledPresets()
    for (const preset of presets) {
      const width = this.chipWidths.get(preset.id)
      if (width === undefined) return -1
      if (preset.id === id) return offset
      offset += width + 5
    }
    return -1
  }

  // 挂载后只执行一次：等 Scroll 宽度与所有 chip 宽度就绪后，把选中项滚入视野。
  private maybeRevealInitial(): void {
    if (!this.initialRevealPending || this.barWidth <= 0) return
    const selectedId = this.presetStore.selectedId
    if (selectedId.length === 0) {
      this.initialRevealPending = false
      return
    }
    const offset = this.chipOffset(selectedId)
    const width = this.chipWidths.get(selectedId)
    if (offset < 0 || width === undefined) return
    this.initialRevealPending = false
    const viewRight = this.barWidth - 12
    if (offset >= 2 && offset + width <= viewRight) return
    const target = offset + width > viewRight ? offset + width - this.barWidth + 12 : offset - 8
    try {
      this.presetScroller.scrollTo({ xOffset: Math.max(0, target), yOffset: 0, animation: true })
    } catch (err) {
      // Scroller 尚未绑定；保留 pending，下一次 area 回调再试。
      this.initialRevealPending = true
    }
  }

  build() {
    Column({ space: 3 }) {
      Text(I18n.t('layer_presets_tab'))
        .fontSize(10).fontColor(this.c.sub).width('100%').padding({ left: 2 })
      Scroll(this.presetScroller) {
        Row({ space: 5 }) {
          ForEach(this.presetStore.enabledPresets(), (preset: LayerPresetDefinition) => {
            Text(this.presetStore.labelWithMarker(preset))
              .fontSize(10)
              .fontColor(this.presetStore.selectedId === preset.id ? this.c.onAccent : this.c.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .backgroundColor(this.presetStore.selectedId === preset.id ? this.c.accent : this.c.bg)
              .borderRadius(UI_RADIUS_CONTROL)
              .constraintSize({ minHeight: 28, maxWidth: 148 })
              .padding({ left: 9, right: 9, top: 5, bottom: 5 })
              .onClick(() => { this.presetStore.applyPreset(preset.id) })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                const w = Number(newArea.width)
                if (!Number.isFinite(w) || w <= 0) return
                this.chipWidths.set(preset.id, w)
                this.maybeRevealInitial()
              })
          }, (preset: LayerPresetDefinition) => preset.id + '|'
            + (this.presetStore.selectedId === preset.id ? 'sel' : '') + '|'
            + (this.presetStore.isMarked(preset) ? 'mark' : '') + '|' + preset.customName)
        }.padding({ left: 2, right: 12 })
      }
      .width('100%')
      .height(32)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w = Number(newArea.width)
        if (!Number.isFinite(w) || w <= 0) return
        this.barWidth = w
        this.maybeRevealInitial()
      })
    }
    .width('100%')
    .margin({ bottom: 4 })
  }
}
