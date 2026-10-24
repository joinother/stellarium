import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'
import { Theme } from '@kit.ArkUI'
import { DEFAULT_SLOTS, ThemeSlots, slotsFromTheme } from '../../state/StellariumTheme'

// 详情主卡片的"贴片族"组件：数据贴片、指标、日程贴片、页签与紧凑指标。
//
// 标签与数值由父方以 `@Prop` 传入（普通类型参数按值捕获后子树首帧即冻结，
// 实时数值必须由能感知状态变化的父组件重新传入）。
// 组件只负责显示规则（空值显示 `--`）与交互回调。
@Component
export struct ObjectDataTile {
  @Prop label: string
  @Prop value: string
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column({ space: 3 }) {
      Text(this.label).fontSize(10).fontColor(this.c.tertiary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--').fontSize(11).fontColor(this.c.fourth).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').height(48).padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor(this.c.rowBg)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectMetric {
  @Prop label: string
  @Prop value: string
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column() {
      Text(this.label).fontSize(10).fontColor(this.c.tertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
    }
      .height(58).padding({ left: 10, right: 10, top: 8, bottom: 8 }).layoutWeight(1)
      .backgroundColor(this.c.soft)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectScheduleTile {
  @Prop label: string
  @Prop value: string
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column() {
      Text(this.label).fontSize(10).fontColor(this.c.tertiary)
      Text(this.value.length > 0 ? this.value : '--').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.c.fourth).margin({ top: 4 })
    }
      .height(62).layoutWeight(1).alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor(this.c.softStrong).borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectDetailTab {
  @Prop label: string
  @Prop active: boolean
  @State private c: ThemeSlots = DEFAULT_SLOTS
  onSelect: () => void = () => {}

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Text(this.label)
      .fontSize(12).fontWeight(this.active ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.active ? this.c.textStrong : this.c.tertiary)
      .height(32).layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 })
      .backgroundColor(this.active ? this.c.softStrong : this.c.bg)
      .borderRadius(UI_RADIUS_CONTROL)
      .scale({ x: this.active ? 1.02 : 1, y: this.active ? 1.02 : 1 })
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
      .onClick(() => { this.onSelect() })
  }
}

@Component
export struct ObjectCompactMetric {
  @Prop label: string
  @Prop value: string
  @State private c: ThemeSlots = DEFAULT_SLOTS

  onWillApplyTheme(theme: Theme) { this.c = slotsFromTheme(theme) }

  build() {
    Column() {
      Text(this.label)
        .fontSize(10).fontColor(this.c.tertiary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.c.metricValue).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 })
    }
      .height(46).padding({ left: 8, right: 8, top: 6, bottom: 6 }).layoutWeight(1)
      .backgroundColor(this.c.soft)
      .border({ width: 0.5, color: this.c.border })
      .borderRadius(UI_RADIUS_CONTROL)
  }
}
