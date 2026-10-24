import { curves } from '@kit.ArkUI'
import { Theme } from '@kit.ArkUI'
import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { I18n } from '../../pages/I18n'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 「星空文化」查看器面板的五个叶件。
//
// 宿主只注入「算好的值 + 夜视三色 + 回调」，状态与桥调用留在宿主；
// 组件不接受参数化 @Builder / @BuilderParam，由 @Prop 实时驱动刷新。
// 各组件的字号 / 间距 / 圆角 / 动画时长见下。

// 分组小标题。
@Component
export struct SkyCultureSectionHeader {
  @Prop title: ResourceStr
  @Prop subtitle: ResourceStr
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 8 }) {
      Row().width(3).height(27).backgroundColor(this.c.accent).borderRadius(2)
      Column({ space: 2 }) {
        Text(this.title).fontSize(13).fontColor(this.c.text).fontWeight(FontWeight.Medium).width('100%')
        Text(this.subtitle).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').padding({ left: 2, right: 2, top: 4, bottom: 7 })
  }
}

// 元信息小块。
@Component
export struct SkyCultureMetaItem {
  @Prop label: ResourceStr
  @Prop value: string
  @Prop accent: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column({ space: 5 }) {
      Text(this.label).fontSize(10).fontColor(this.c.sub).width('100%').maxLines(1)
      Text(this.value).fontSize(12).fontColor(this.accent ? this.c.accent : this.c.text).width('100%')
        .maxLines(2).lineHeight(17).textOverflow({ overflow: TextOverflow.Ellipsis })
    }.width('47.5%').height(70).padding({ left: 11, right: 11, top: 10, bottom: 9 })
      .backgroundColor(this.c.bg).border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .margin({ bottom: 8 })
  }
}

// 标签模式选择卡片（含展开与选项列表）。
//
// 展开标记 / 当前档位 / 可选项都由宿主算好后经 @Prop 传入；展开状态变化由组件用 animateTo 驱动，
// 切换与选中通过 onToggle / onSelectMode 回注宿主（宿主内走桥调用）。
@Component
export struct SkyCultureLabelSettingCard {
  @Prop target: string
  @Prop title: ResourceStr
  @Prop options: string[]
  @Prop mode: number
  @Prop isOpen: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (target: string) => void = () => {}
  onSelectMode: (target: string, index: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Column() {
      Column() {
        Row() {
          Column({ space: 1 }) {
            Text(this.title).fontSize(10).fontColor(this.c.sub).width('100%')
            Text(this.options[this.mode])
              .fontSize(12).fontColor(this.c.text).width('100%').maxLines(2).lineHeight(17)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }.layoutWeight(1)
          Text(this.isOpen ? I18n.t('culture_collapse') : I18n.t('culture_expand')).fontSize(10)
            .fontColor(this.c.text).padding({ left: 7, right: 7, top: 4, bottom: 4 })
            .backgroundColor(this.isOpen ? this.c.textStrong : this.c.input)
            .border({ width: 1, color: this.isOpen ? this.c.accent : this.c.border })
            .borderRadius(UI_RADIUS_CONTROL)
            .animation({ duration: 160, curve: Curve.EaseInOut })
        }.height(52).width('100%').padding({ left: 12, right: 12 })
          .backgroundColor(this.isOpen ? this.c.text : this.c.sub)
          .borderRadius(UI_RADIUS_CONTROL)
          .animation({ duration: 160, curve: Curve.EaseInOut })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.onToggle(this.target)
          })
        if (this.isOpen) {
          Column({ space: 6 }) {
            ForEach(this.options, (option: string, index: number) => {
              Row({ space: 10 }) {
                Stack({ alignContent: Alignment.Center }) {
Circle().width(18).height(18).fill(index === this.mode ? this.c.accent : this.c.bg)
                    if (index === this.mode) {
                      Text('✓').fontSize(12).fontColor(this.c.textStrong).fontWeight(FontWeight.Bold)
                   }
                 }.width(20).height(20)
                 Text(option).fontSize(12).fontColor(this.c.text).layoutWeight(1)
                   .maxLines(2).lineHeight(17).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.height(44).width('100%').padding({ left: 12, right: 12 })
                .backgroundColor(index === this.mode ? this.c.textStrong : this.c.sub)
                .border({ width: 0.5, color: index === this.mode ? this.c.accent : this.c.border })
                .borderRadius(UI_RADIUS_CONTROL)
                .animation({ duration: 180, curve: Curve.EaseInOut })
                .clickEffect({ level: ClickEffectLevel.LIGHT })
                .hitTestBehavior(HitTestMode.Block)
                .onClick(() => {
                  this.onSelectMode(this.target, index)
                })
            }, (option: string) => this.target + '-' + option)
          }.width('100%').padding({ left: 7, right: 7, top: 6, bottom: 8 })
            .transition(TransitionEffect.asymmetric(
              TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut })
                .combine(TransitionEffect.translate({ x: 0, y: -7 }).animation({ duration: 180, curve: Curve.EaseOut })),
              TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
                .combine(TransitionEffect.translate({ x: 0, y: -4 }).animation({ duration: 140, curve: Curve.EaseIn }))
            ))
        }
      }.width('100%').backgroundColor(this.c.input)
        .border({ width: 1, color: this.isOpen ? this.c.accent : this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
        .animation({ duration: 180, curve: Curve.EaseInOut })
    }.width('100%')
      .border({ width: 1, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .animation({ duration: 180, curve: Curve.EaseInOut })
  }
}

// 筛选器选项行，供 SkyCultureFilterPicker 在展开列表内使用。
//
// 选中态由 selected 传入。调用方须把 selected 纳入 ForEach 键，否则同键子项不会重建、@Prop 会冻结。
@Component
export struct SkyCultureFilterOption {
  @Prop label: string
  @Prop selected: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onPick: () => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  build() {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle().width(18).height(18).fill(this.selected ? this.c.accent : this.c.bg)
        if (this.selected) {
          Text('✓').fontSize(12).fontColor(this.c.textStrong).fontWeight(FontWeight.Bold)
        }
      }.width(20).height(20)
      Text(this.label).fontSize(12).fontColor(this.c.text).layoutWeight(1)
        .maxLines(2).lineHeight(17).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.selected) {
        Text(I18n.t('culture_current')).fontSize(10).fontColor(this.c.accent)
      }
    }.height(44).width('100%').padding({ left: 12, right: 12 })
      .backgroundColor(this.selected ? this.c.textStrong : this.c.sub)
      .border({ width: 0.5, color: this.selected ? this.c.accent : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .animation({ duration: 180, curve: curves.springMotion(0.46, 0.88) })
      .clickEffect({ level: ClickEffectLevel.LIGHT })
      .onClick(() => { this.onPick() })
  }
}

// 分类 / 地区筛选器。
//
// 选中的下标由宿主演算成 selectedIndex 传入；展开时用选定下标参与 ForEach 键，保证选中高亮实时刷新。
@Component
export struct SkyCultureFilterPicker {
  @Prop kind: string
  @Prop labels: string[]
  @Prop selectedIndex: number
  @Prop isOpen: boolean
  @State c: ThemeSlots = DEFAULT_SLOTS
  onToggle: (kind: string) => void = () => {}
  onPick: (kind: string, index: number) => void = () => {}

  onWillApplyTheme(theme: Theme): void {
    this.c = slotsFromTheme(theme)
  }

  private pickerTitle(): ResourceStr {
    return this.kind === 'classification' ? I18n.t('culture_type') : I18n.t('culture_region')
  }

  build() {
    Column({ space: 2 }) {
      Row() {
        Column({ space: 3 }) {
          Text(this.pickerTitle())
            .fontSize(10).fontColor(this.c.sub).width('100%')
          Text(this.labels[this.selectedIndex]).fontSize(12).fontColor(this.c.text).width('100%')
            .maxLines(2).lineHeight(17).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.isOpen ? I18n.t('culture_collapse') : I18n.t('culture_choose')).fontSize(10).fontColor(this.c.accent)
          .padding({ left: 5, right: 5, top: 3, bottom: 3 })
          .backgroundColor(this.isOpen ? this.c.textStrong : this.c.input)
          .border({ width: 1, color: this.isOpen ? this.c.accent : this.c.border })
          .borderRadius(UI_RADIUS_CONTROL)
      }.height(54).width('100%').padding({ left: 12, right: 12 })
        .backgroundColor(this.isOpen ? this.c.text : this.c.sub)
        .border({ width: 1, color: this.isOpen ? this.c.accent : this.c.border })
        .borderRadius(UI_RADIUS_CONTROL)
        .animation({ duration: 180, curve: Curve.EaseInOut })
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => { this.onToggle(this.kind) })
      if (this.isOpen) {
        Column({ space: 6 }) {
          ForEach(this.labels, (label: string, index: number) => {
            SkyCultureFilterOption({
               label: label,
               selected: index === this.selectedIndex,
              onPick: () => { this.onPick(this.kind, index) }
            })
          }, (label: string, index: number) => this.kind + '-' + label + (index === this.selectedIndex ? '-s' : ''))
        }.width('100%').padding({ left: 7, right: 7, top: 6, bottom: 8 })
          .transition(TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseOut })
              .combine(TransitionEffect.translate({ x: 0, y: -8 }).animation({ duration: 220, curve: curves.springMotion(0.46, 0.88) })),
            TransitionEffect.OPACITY.animation({ duration: 120, curve: Curve.EaseIn })
              .combine(TransitionEffect.translate({ x: 0, y: -4 }).animation({ duration: 150, curve: Curve.EaseIn }))
          ))
      }
    }.width('100%')
      .backgroundColor(this.isOpen ? this.c.input : this.c.rowBg)
      .border({ width: 1, color: this.isOpen ? this.c.accent : this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
      .animation({ duration: 220, curve: curves.springMotion(0.46, 0.88) })
  }
}
