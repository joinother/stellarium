import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'
import { I18n } from '../../pages/I18n'
import { getIcon } from '../../common/ui/ShellIcons'
import { QuickActionItem } from '../../common/derive/quickActions'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { tintMatrixFor } from '../../common/ui/IconTint'

// 快捷操作面板的单个图标按钮。一个组件承担两种角色（由入参决定）：
//   槽位（默认）—— 网格里的 12 个格子，编辑态下是**投放目标**；
//   候选（candidate）—— 编辑态候选带里的格子，是**拖出源**。
//
// 着色双路径（本组件唯一技术点）：
//   raster —— Stellarium 官方 `-off` PNG，用 colorFilter 颜色矩阵把 RGB 统一压成目标色、保留 alpha。
//             不能用 colorBlend：它会把透明背景一起染（ArkUI FAQ faqs-arkui-1328）。
//   vector —— 自研 `ic_*.svg`，同样走 supportSvg2 + colorFilter（fillColor 覆盖不了写死的白色描边）。
// 两条路径产出同一套「亮 = 高亮 / 灭 = 暗灰」观感；官方 `-on` 图标一律不用。
//
// 图标名、激活态、按下态、文字色由宿主以机制四槽位传入；点按语义（receiveTap 门控 +
// onToggle 回调）与长按提示语义由宿主注入；拖放语义（候选 onDragBegin / 槽位 onDropOnSlot）
// 由宿主经 editable / candidate 门控。
// 视觉：标题 12 号 #8EA0BD / 按钮高 32 / GoTo #5B93BF、同步 rgba(107,163,214,0.20)、
// 中止 rgba(255,121,121,0.14) / 状态 11 号 #99FFFFFF 高 2 行 / 外框 rgba(107,163,214,0.12)。
// 网格内不显示文字（对齐参考图），长按经 onHint 出名称提示。
// **编辑态例外**：长按要让位给统一拖拽的起手（同一手势），故编辑态内长按不再出提示（见计划 §13.5）。

@Component
export struct QuickActionCell {
  @Prop item: QuickActionItem
  @Prop isOn: boolean
  // 编辑态：格子显示可投放描边并接收拖放。
  @Prop editable: boolean
  // 本格是候选（拖出源）而非槽位（投放目标）。
  @Prop candidate: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  // 拖拽悬停在本槽位上方（仅槽位使用）。
  @State private dragOver: boolean = false
  onToggle: (id: string, value: boolean) => void = () => {}
  onHint: (text: string) => void = () => {}
  // 候选被拖起（宿主记录被拖的 id）。
  onDragBegin: (id: string) => void = () => {}
  // 本槽位收到投放（宿主按被拖 id 与槽位 id 做替换）。
  onDropOnSlot: (slotId: string) => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  // 注意：成员名不得与组件内置属性方法重名（`borderColor` 是内置属性），故加 cell 前缀。
  private cellBorderColor(): ResourceColor {
    if (this.dragOver) return this.c.accent
    if (this.isOn) return this.c.soft
    // 编辑态给槽位一圈淡描边，示意「可以放这里」；候选格不加。
    if (this.editable && !this.candidate) return this.c.accentSoft
    return Color.Transparent
  }

  build() {
    Button() {
      Column() {
        if (this.item.kind === 'raster') {
          Image(getIcon(this.item.icon, false))
            .width(38)
            .height(38)
            .objectFit(ImageFit.Contain)
            .supportSvg2(true)
            .colorFilter(this.isOn ? tintMatrixFor(this.c.dockActive) : tintMatrixFor(this.c.idleIcon))
            // Image 属 ArkUI 默认可拖拽组件，必须显式关掉：否则它会被系统挑成拖拽源，
            // 我们挂在 Button 上的 onDragStart 就永远不回调（实测 AceDrag 日志
            // `require summary: general.image-24` 即由图标自身当源）。
            .draggable(false)
        } else {
          Image(getIcon(this.item.icon, false))
            .width(34)
            .height(34)
            .objectFit(ImageFit.Contain)
            .supportSvg2(true)
            .colorFilter(this.isOn ? tintMatrixFor(this.c.dockActive) : tintMatrixFor(this.c.idleIcon))
            .draggable(false)
        }
      }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        // 关键：内部 Column/Image 不参与命中，触摸必须落在 Button 上。
        // 否则命中的是 Image（Image 属 ArkUI 默认可拖拽组件，而它自身 draggable=false），
        // 系统会判「frameNode draggable is 0」把整个拖拽取消、松手退化成点击
        // （实测日志：AceDrag `frameNode draggable is 0` → `Drag gesture has been canceled`）。
        .hitTestBehavior(HitTestMode.None)
    }
      // 锚点前缀是跨会话契约，必须保持字面量形式（check-ohos-ui-contract.mjs 按字面量扫描）。
      // 候选格与槽位格共用同一前缀且**互斥**（候选 = 池中未列入者），故不会出现同名锚点。
      .id('quick-action-' + this.item.id)
      .layoutWeight(1)
      .aspectRatio(1)
      .padding(0)
      // 只给「开」画底框：夜间模式下灭态的浅底框在暗背景里几乎不可辨，反而糊成一团。
      // 边框宽度恒为 1（颜色透明）以免开关切换时格子尺寸跳动。
      .backgroundColor(this.isOn || this.dragOver ? this.c.soft : Color.Transparent)
      .border({ width: 1, color: this.cellBorderColor() })
      .borderRadius(UI_RADIUS_CONTROL)
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .accessibilityText(I18n.t(this.item.labelKey))
      .onClick(() => {
        // 编辑态内点按不切换开关（改用拖拽替换），避免与拖拽语义打架。
        if (this.editable) return
        this.onToggle(this.item.id, !this.isOn)
      })
      // 编辑态必须把这个长按手势「作废」：系统统一拖拽在触摸场景靠长按（约 500ms）起手，
      // 而这里注册的 LongPressGesture 会在 600ms 赢下手势竞技场、把系统拖拽掐掉
      // —— 表现就是「按住能按，但松手不替换」。把 duration 拉到不可能到达即可让出竞技场。
      .gesture(LongPressGesture({ repeat: false, duration: this.editable ? 600000 : 600 }).onAction(() => {
        if (this.editable) return
        this.onHint(I18n.t(this.item.labelKey))
      }))
      // —— 编辑态拖拽：候选格可拖出，槽位可接收 ——
      // 应用内拖放**不加 `allowDrop` / `setData`**：ArkUI 官方示例（FAQ faqs-arkui-1173「图标垃圾桶」）
      // 就是「拖出方 `.draggable(true)` + `.onDragStart`，接收方 `.onDrop`」这两步。
      // 实测加上 `allowDrop([PLAIN_TEXT])` 后系统反而判「target data is not allowed to fall into」而拒收
      // （AceDrag 日志），被拖的 id 用宿主字段 `quickDragSourceId` 传递即可。
      .draggable(this.editable && this.candidate)
      .onDragStart(() => { this.onDragBegin(this.item.id) })
      .onDragEnter(() => {
        if (this.editable && !this.candidate) this.dragOver = true
      })
      .onDragLeave(() => { this.dragOver = false })
      .onDrop(() => {
        this.dragOver = false
        if (!this.editable || this.candidate) return
        this.onDropOnSlot(this.item.id)
      })
  }
}
