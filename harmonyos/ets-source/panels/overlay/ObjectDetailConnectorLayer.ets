import { curves } from '@kit.ArkUI'

// 「天体详情指向线」叠层。
//
// 本组件只吃 @Prop，不持有 store：指向线几何是**叠层实时位置**，由宿主 `refreshObjectDetailConnector()`
// 按动画帧节流写入（objectDetailConnectorX/Y/Length/Angle/EndX/EndY/TargetX/TargetY/TargetOnScreen +
// AnimateGeometry），**不入被观察 store**（否则重渲染风暴），只留宿主、以 @Prop 传入。
// 唯一来自 store 的是开关 `objectDetailConnectorVisible`，同样以 `visible` 传入。
//
// 根是一个**撑满父容器**的 `Stack`：三个调用点都是 100%×100% 的 `Stack`
// （default alignContent 居中），故必须显式 100%×100% 才能让绝对定位坐标正确。
// 该 Stack 取 `.zIndex(20)` 以保持"在星空之上、面板/详情卡/底部 Dock 之下"的层序，
// 并取 `HitTestMode.None`（子节点本就全是 None）。
@Component
export struct ObjectDetailConnectorLayer {
  @Prop visible: boolean
  @Prop beamLength: number
  @Prop beamX: number
  @Prop beamY: number
  @Prop beamAngle: number
  @Prop animateGeometry: boolean
  @Prop targetOnScreen: boolean
  @Prop targetX: number
  @Prop targetY: number
  @Prop endX: number
  @Prop endY: number
  @Prop markerSize: number

  build() {
    Stack() {
      if (this.visible && this.beamLength > 0) {
        Row()
          .width(this.beamLength)
          .height(6)
          .backgroundColor('rgba(111, 196, 239, 0.12)')
          .borderRadius(3)
          .position({ x: this.beamX - this.beamLength / 2, y: this.beamY - 3 })
          .rotate({ angle: this.beamAngle })
          .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(20)
        Row()
          .width(this.beamLength)
          .height(1.25)
          .backgroundColor('rgba(198, 235, 255, 0.62)')
          .borderRadius(1)
          .position({ x: this.beamX - this.beamLength / 2, y: this.beamY - 0.625 })
          .rotate({ angle: this.beamAngle })
          .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
          .hitTestBehavior(HitTestMode.None)
          .zIndex(20)
        if (this.targetOnScreen) {
          Circle()
            .width(this.markerSize).height(this.markerSize)
            .fill('rgba(91,147,191,0.035)')
            .stroke('rgba(166,224,255,0.20)').strokeWidth(5)
            .position({ x: this.targetX - this.markerSize / 2, y: this.targetY - this.markerSize / 2 })
            .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
            .hitTestBehavior(HitTestMode.None)
            .zIndex(20)
          Circle()
            .width(this.markerSize * 0.72).height(this.markerSize * 0.72)
            .fill('rgba(0,0,0,0)')
            .stroke('rgba(207,239,255,0.68)').strokeWidth(1.25)
            .position({ x: this.targetX - this.markerSize * 0.36, y: this.targetY - this.markerSize * 0.36 })
            .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
            .hitTestBehavior(HitTestMode.None)
            .zIndex(20)
        } else {
          Circle()
            .width(10).height(10)
            .fill('rgba(180,226,250,0.34)')
            .stroke('rgba(220,244,255,0.74)').strokeWidth(1)
            .position({ x: this.endX - 5, y: this.endY - 5 })
            .animation({ duration: this.animateGeometry ? 180 : 0, curve: curves.springMotion(0.42, 0.86) })
            .hitTestBehavior(HitTestMode.None)
            .zIndex(20)
        }
      }
    }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .zIndex(20)
  }
}
