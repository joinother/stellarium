import { UI_RADIUS_CONTROL } from '../../common/ui/UiTokens'

// 详情主卡片的"贴片族"组件：数据贴片、指标、日程贴片、页签与紧凑指标。
//
// 标签与数值由父方以 `@Prop` 传入（普通类型参数按值捕获后子树首帧即冻结，
// 实时数值必须由能感知状态变化的父组件重新传入）。
// 组件只负责显示规则（空值显示 `--`）与交互回调。

@Component
export struct ObjectDataTile {
  @Prop label: string
  @Prop value: string

  build() {
    Column({ space: 3 }) {
      Text(this.label).fontSize(10).fontColor('#8FBBD6').width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--').fontSize(11).fontColor('#E0F1F8').width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
      .width('100%').height(48).padding({ left: 9, right: 9, top: 6, bottom: 6 })
      .backgroundColor('rgba(255,255,255,0.045)').border({ width: 0.5, color: 'rgba(147,215,255,0.08)' }).borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectMetric {
  @Prop label: string
  @Prop value: string

  build() {
    Column() {
      Text(this.label).fontSize(10).fontColor('#8FBBD6').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 3 })
    }
      .height(58).padding({ left: 10, right: 10, top: 8, bottom: 8 }).layoutWeight(1)
      .backgroundColor('rgba(91,147,191,0.10)').border({ width: 0.5, color: 'rgba(147,215,255,0.10)' }).borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectScheduleTile {
  @Prop label: string
  @Prop value: string

  build() {
    Column() {
      Text(this.label).fontSize(10).fontColor('#8FBBD6')
      Text(this.value.length > 0 ? this.value : '--').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').margin({ top: 4 })
    }
      .height(62).layoutWeight(1).alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(91,147,191,0.12)').borderRadius(UI_RADIUS_CONTROL)
  }
}

@Component
export struct ObjectDetailTab {
  @Prop label: string
  @Prop active: boolean
  onSelect: () => void = () => {}

  build() {
    Text(this.label)
      .fontSize(12).fontWeight(this.active ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.active ? '#E8F8FF' : '#8FBBD6')
      .height(32).layoutWeight(1).textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 })
      .backgroundColor(this.active ? 'rgba(91,147,191,0.30)' : 'rgba(255,255,255,0.03)')
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

  build() {
    Column() {
      Text(this.label)
        .fontSize(10).fontColor('#8FBBD6').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.value.length > 0 ? this.value : '--')
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#E7F7FF').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).margin({ top: 1 })
    }
      .height(46).padding({ left: 8, right: 8, top: 6, bottom: 6 }).layoutWeight(1)
      .backgroundColor('rgba(91,147,191,0.10)').border({ width: 0.5, color: 'rgba(147,215,255,0.10)' }).borderRadius(UI_RADIUS_CONTROL)
  }
}
